#include "veclens/multi_gpu.hpp"

#include <cuda_runtime.h>

#if defined(VECLENS_WITH_NCCL)
#include <nccl.h>
#endif

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <exception>
#include <memory>
#include <numeric>
#include <stdexcept>
#include <thread>
#include <vector>

#include "veclens/common.hpp"
#include "veclens/distance.cuh"
#include "veclens/kmeans.hpp"
#include "veclens/nvtx.hpp"
#include "veclens/stream.hpp"
#include "veclens/topk.hpp"

namespace veclens {
namespace {

constexpr int kRemapBlock = 256;

// Замер P2P делается на достаточно крупном блоке: на мелких копиях виден
// не канал, а латентность запуска.
constexpr size_t kP2PBytes = 64ull << 20;
constexpr int kP2PIters = 5;

// Порог NVLink. PCIe 4.0 x16 даёт около 25 ГБ/с в одну сторону, PCIe 5.0 —
// около 50; всё, что выше 40 ГБ/с на однонаправленной копии, реализуемо
// только по NVLink.
constexpr double kNvlinkThresholdGbps = 40.0;

#if defined(VECLENS_WITH_NCCL)
void nccl_check(ncclResult_t res, const char* expr, const char* file, int line) {
  if (res != ncclSuccess) {
    throw std::runtime_error(std::string(file) + ':' + std::to_string(line) + ": " + expr +
                             " -> " + ncclGetErrorString(res));
  }
}
#define VL_NCCL_CHECK(expr) nccl_check((expr), #expr, __FILE__, __LINE__)
#endif

// Локальный номер вектора внутри шарда меняется на глобальный: шард ничего
// не знает об исходной нумерации базы, он видит только свой поддатасет.
__global__ void remap_ids_kernel(VectorId* __restrict__ ids, std::int64_t count,
                                 const VectorId* __restrict__ map, std::int64_t map_size) {
  const std::int64_t stride = static_cast<std::int64_t>(gridDim.x) * kRemapBlock;
  for (std::int64_t i = blockIdx.x * kRemapBlock + threadIdx.x; i < count; i += stride) {
    const VectorId local = ids[i];
    ids[i] = (local == kInvalidId || static_cast<std::int64_t>(local) >= map_size)
                 ? kInvalidId
                 : map[local];
  }
}

// Собранные части лежат как [шард][запрос][k], а слиянию нужен порядок
// [запрос][шард][k]: части одного запроса должны быть рядом.
__global__ void interleave_parts_kernel(const float* __restrict__ src_dist,
                                        const VectorId* __restrict__ src_ids, int n_parts, int nq,
                                        int k, float* __restrict__ dst_dist,
                                        VectorId* __restrict__ dst_ids) {
  const std::int64_t total = static_cast<std::int64_t>(n_parts) * nq * k;
  const std::int64_t stride = static_cast<std::int64_t>(gridDim.x) * kRemapBlock;
  for (std::int64_t i = blockIdx.x * kRemapBlock + threadIdx.x; i < total; i += stride) {
    const std::int64_t j = i % k;
    const std::int64_t q = (i / k) % nq;
    const std::int64_t p = i / (static_cast<std::int64_t>(k) * nq);
    const std::int64_t dst = (q * n_parts + p) * k + j;
    dst_dist[dst] = src_dist[i];
    dst_ids[dst] = src_ids[i];
  }
}

struct DeviceGuard {
  explicit DeviceGuard(int device) {
    VL_CUDA_CHECK(cudaGetDevice(&previous_));
    if (previous_ != device) VL_CUDA_CHECK(cudaSetDevice(device));
  }
  DeviceGuard(const DeviceGuard&) = delete;
  DeviceGuard& operator=(const DeviceGuard&) = delete;
  ~DeviceGuard() { VL_CUDA_CHECK_NOTHROW(cudaSetDevice(previous_)); }

 private:
  int previous_ = 0;
};

double measure_p2p_gbps(int from, int to) {
  DeviceGuard guard(from);

  void* src = nullptr;
  void* dst = nullptr;
  if (cudaMalloc(&src, kP2PBytes) != cudaSuccess) {
    (void)cudaGetLastError();
    return 0.0;
  }
  if (cudaSetDevice(to) != cudaSuccess || cudaMalloc(&dst, kP2PBytes) != cudaSuccess) {
    (void)cudaGetLastError();
    (void)cudaSetDevice(from);
    (void)cudaFree(src);
    return 0.0;
  }
  VL_CUDA_CHECK(cudaSetDevice(from));

  double gbps = 0.0;
  try {
    Stream stream;
    Event begin, end;
    // Прогрев: первая копия оплачивает создание отображений в BAR.
    VL_CUDA_CHECK(cudaMemcpyPeerAsync(dst, to, src, from, kP2PBytes, stream.get()));
    VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));

    begin.record(stream.get());
    for (int i = 0; i < kP2PIters; ++i) {
      VL_CUDA_CHECK(cudaMemcpyPeerAsync(dst, to, src, from, kP2PBytes, stream.get()));
    }
    end.record(stream.get());
    VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));

    const double ms = static_cast<double>(Event::elapsed_ms(begin, end));
    if (ms > 0.0) {
      gbps = static_cast<double>(kP2PBytes) * kP2PIters / (ms * 1e-3) / 1e9;
    }
  } catch (const CudaError&) {
    gbps = 0.0;
  }

  (void)cudaFree(src);
  (void)cudaSetDevice(to);
  (void)cudaFree(dst);
  (void)cudaSetDevice(from);
  return gbps;
}

}  // namespace

TopologyInfo query_topology() {
  VL_NVTX_RANGE("topology");
  TopologyInfo topo;
  int count = 0;
  VL_CUDA_CHECK(cudaGetDeviceCount(&count));
  topo.device_count = count;
  if (count == 0) return topo;

  topo.names.resize(static_cast<size_t>(count));
  topo.peer_access.assign(static_cast<size_t>(count),
                          std::vector<bool>(static_cast<size_t>(count), false));
  topo.p2p_gbps.assign(static_cast<size_t>(count),
                       std::vector<double>(static_cast<size_t>(count), 0.0));

  for (int i = 0; i < count; ++i) {
    cudaDeviceProp prop{};
    VL_CUDA_CHECK(cudaGetDeviceProperties(&prop, i));
    topo.names[static_cast<size_t>(i)] = prop.name;
  }

  for (int i = 0; i < count; ++i) {
    for (int j = 0; j < count; ++j) {
      if (i == j) continue;
      int can = 0;
      VL_CUDA_CHECK(cudaDeviceCanAccessPeer(&can, i, j));
      topo.peer_access[static_cast<size_t>(i)][static_cast<size_t>(j)] = (can != 0);
      if (!can) continue;

      // Доступ включается только на время замера: постоянное включение —
      // решение владельца индекса, а не функции опроса топологии.
      {
        DeviceGuard guard(i);
        const cudaError_t st = cudaDeviceEnablePeerAccess(j, 0);
        if (st != cudaSuccess && st != cudaErrorPeerAccessAlreadyEnabled) {
          (void)cudaGetLastError();
          continue;
        }
        (void)cudaGetLastError();
      }
      const double gbps = measure_p2p_gbps(i, j);
      topo.p2p_gbps[static_cast<size_t>(i)][static_cast<size_t>(j)] = gbps;
      if (gbps >= kNvlinkThresholdGbps) topo.has_nvlink = true;
    }
  }
  return topo;
}

void print_topology(const TopologyInfo& topo) {
  std::printf("Карт видно: %d%s\n", topo.device_count, topo.has_nvlink ? " (есть NVLink)" : "");
  for (int i = 0; i < topo.device_count; ++i) {
    std::printf("  GPU %d: %s\n", i, topo.names[static_cast<size_t>(i)].c_str());
  }
  if (topo.device_count < 2) return;

  std::printf("\nP2P (ГБ/с, строка = источник, '-' = нет прямого доступа):\n      ");
  for (int j = 0; j < topo.device_count; ++j) std::printf("%8d", j);
  std::printf("\n");
  for (int i = 0; i < topo.device_count; ++i) {
    std::printf("  %3d ", i);
    for (int j = 0; j < topo.device_count; ++j) {
      if (i == j) {
        std::printf("%8s", "self");
      } else if (!topo.peer_access[static_cast<size_t>(i)][static_cast<size_t>(j)]) {
        std::printf("%8s", "-");
      } else {
        std::printf("%8.1f", topo.p2p_gbps[static_cast<size_t>(i)][static_cast<size_t>(j)]);
      }
    }
    std::printf("\n");
  }
}

// ----------------------------------------------------------------- шардинг

struct ShardedIvfIndex::Impl {
  struct Shard {
    Shard(int dev, const IndexParams& params) : device(dev) {
      DeviceGuard guard(device);
      index = std::make_unique<IvfFlatIndex>(params);
      stream = std::make_unique<Stream>();
    }

    Shard(const Shard&) = delete;
    Shard& operator=(const Shard&) = delete;

    ~Shard() {
      // Освобождение памяти и потока должно идти в контексте своей карты,
      // поэтому буферы гасятся явно, а не в произвольном порядке разрушения.
      int previous = 0;
      VL_CUDA_CHECK_NOTHROW(cudaGetDevice(&previous));
      VL_CUDA_CHECK_NOTHROW(cudaSetDevice(device));
      d_queries.release();
      d_distances.release();
      d_ids.release();
      id_map.release();
      gathered_dist.release();
      gathered_ids.release();
      stream.reset();
      index.reset();
      VL_CUDA_CHECK_NOTHROW(cudaSetDevice(previous));
    }

    int device = 0;
    std::unique_ptr<IvfFlatIndex> index;
    std::unique_ptr<Stream> stream;

    std::vector<VectorId> global_ids;   // локальный номер -> глобальный
    DeviceBuffer<VectorId> id_map;

    DeviceBuffer<float> d_queries;
    DeviceBuffer<float> d_distances;
    DeviceBuffer<VectorId> d_ids;
    DeviceBuffer<float> gathered_dist;  // используется только на ранге 0 / NCCL
    DeviceBuffer<VectorId> gathered_ids;
  };

  Impl(const IndexParams& ip, const MultiGpuParams& mp) : index_params(ip), params(mp) {
    int count = 0;
    VL_CUDA_CHECK(cudaGetDeviceCount(&count));
    if (count == 0) throw std::runtime_error("ShardedIvfIndex: не найдено ни одной карты CUDA");

    devices = params.devices;
    if (devices.empty()) {
      devices.resize(static_cast<size_t>(count));
      std::iota(devices.begin(), devices.end(), 0);
    }
    for (int d : devices) {
      if (d < 0 || d >= count) throw std::invalid_argument("ShardedIvfIndex: неверный номер карты");
    }

    if (params.enable_peer_access) enable_peer_access();

    shards.reserve(devices.size());
    for (int d : devices) shards.push_back(std::make_unique<Shard>(d, index_params));
  }

  ~Impl() {
#if defined(VECLENS_WITH_NCCL)
    for (auto& comm : comms) {
      if (comm) ncclCommDestroy(comm);
    }
#endif
    shards.clear();
  }

  void enable_peer_access() {
    for (size_t i = 0; i < devices.size(); ++i) {
      DeviceGuard guard(devices[i]);
      for (size_t j = 0; j < devices.size(); ++j) {
        if (i == j) continue;
        int can = 0;
        VL_CUDA_CHECK(cudaDeviceCanAccessPeer(&can, devices[i], devices[j]));
        if (!can) continue;
        const cudaError_t st = cudaDeviceEnablePeerAccess(devices[j], 0);
        if (st != cudaSuccess && st != cudaErrorPeerAccessAlreadyEnabled) {
          throw CudaError(st, "cudaDeviceEnablePeerAccess", __FILE__, __LINE__);
        }
        (void)cudaGetLastError();
      }
    }
  }

  // Каждая карта обслуживается своим потоком ОС: драйверные вызовы разных
  // карт независимы, а последовательный обход превратил бы N карт в одну.
  template <typename F>
  void run_on_shards(F&& fn) {
    std::vector<std::thread> workers;
    std::vector<std::exception_ptr> errors(shards.size());
    workers.reserve(shards.size());

    for (size_t i = 0; i < shards.size(); ++i) {
      workers.emplace_back([&, i] {
        try {
          VL_CUDA_CHECK(cudaSetDevice(shards[i]->device));
          fn(i);
        } catch (...) {
          errors[i] = std::current_exception();
        }
      });
    }
    for (auto& w : workers) w.join();
    for (auto& e : errors) {
      if (e) std::rethrow_exception(e);
    }
  }

  IndexParams index_params;
  MultiGpuParams params;
  std::vector<int> devices;
  std::vector<std::unique_ptr<Shard>> shards;
  bool trained = false;
  bool built = false;

#if defined(VECLENS_WITH_NCCL)
  std::vector<ncclComm_t> comms;
#endif
};

ShardedIvfIndex::ShardedIvfIndex(const IndexParams& index_params, const MultiGpuParams& params)
    : impl_(std::make_unique<Impl>(index_params, params)) {}

ShardedIvfIndex::~ShardedIvfIndex() = default;

void ShardedIvfIndex::train(const Dataset& train_set) {
  VL_NVTX_RANGE("sharded.train");
  Impl& s = *impl_;
  if (train_set.dim != s.index_params.dim) {
    throw std::invalid_argument("ShardedIvfIndex::train: размерность не совпадает");
  }

  // Центроиды реплицируются: таблица мала (nlist x dim), а нужна каждому
  // запросу на каждой карте. Обучение идёт от одних и тех же данных, seed'а
  // и числа итераций, поэтому таблицы совпадают на всех картах.
  s.run_on_shards([&](size_t i) {
    s.shards[i]->index->train(train_set, s.shards[i]->stream->get());
    VL_CUDA_CHECK(cudaStreamSynchronize(s.shards[i]->stream->get()));
  });
  s.trained = true;
}

void ShardedIvfIndex::build(const Dataset& base) {
  VL_NVTX_RANGE("sharded.build");
  Impl& s = *impl_;
  if (!s.trained) throw std::runtime_error("ShardedIvfIndex::build: сначала train()");
  if (base.dim != s.index_params.dim) {
    throw std::invalid_argument("ShardedIvfIndex::build: размерность не совпадает");
  }

  const int nlist = s.index_params.nlist;
  const int dim_padded = s.index_params.dim_padded();
  const int n_shards = static_cast<int>(s.shards.size());

  // 1. Назначение векторов спискам считается один раз на нулевой карте:
  // центроиды у всех одинаковые, поэтому результат от карты не зависит.
  std::vector<int> assign(static_cast<size_t>(base.n));
  {
    DeviceGuard guard(s.shards[0]->device);
    Stream stream;

    const DeviceBuffer<float>& centroids = s.shards[0]->index->centroids();
    DeviceBuffer<float> centroid_norms(static_cast<size_t>(nlist));
    launch_compute_norms(centroids.data(), nlist, dim_padded, centroid_norms.data(),
                         stream.get());

    const std::int64_t chunk = std::max<std::int64_t>(1, std::min<std::int64_t>(base.n, 1 << 18));
    DeviceBuffer<float> d_chunk(static_cast<size_t>(chunk) * dim_padded);
    DeviceBuffer<int> d_assign(static_cast<size_t>(chunk));
    DeviceBuffer<float> d_assign_dist(static_cast<size_t>(chunk));
    std::vector<float> padded(static_cast<size_t>(chunk) * dim_padded, 0.0f);

    for (std::int64_t begin = 0; begin < base.n; begin += chunk) {
      const std::int64_t rows = std::min(chunk, base.n - begin);
      std::fill(padded.begin(), padded.end(), 0.0f);
      for (std::int64_t r = 0; r < rows; ++r) {
        std::memcpy(padded.data() + r * dim_padded, base.row(begin + r),
                    sizeof(float) * base.dim);
      }
      d_chunk.copy_from_host(padded.data(), static_cast<size_t>(rows) * dim_padded, stream.get());
      launch_assign_clusters(d_chunk.data(), rows, centroids.data(), centroid_norms.data(), nlist,
                             dim_padded, s.index_params.metric, d_assign.data(),
                             d_assign_dist.data(), stream.get());
      d_assign.copy_to_host(assign.data() + begin, static_cast<size_t>(rows), stream.get());
      VL_CUDA_CHECK(cudaStreamSynchronize(stream.get()));
    }
  }

  // 2. Жадное распределение списков по картам: списки перебираются по
  // убыванию длины и уходят на самую свободную карту. Классическая LPT-эвристика
  // даёт дисбаланс не хуже 4/3 от оптимального и стоит один sort.
  std::vector<std::int64_t> list_len(static_cast<size_t>(nlist), 0);
  for (std::int64_t i = 0; i < base.n; ++i) {
    const int a = assign[static_cast<size_t>(i)];
    if (a < 0 || a >= nlist) throw std::runtime_error("ShardedIvfIndex::build: назначение вне диапазона");
    ++list_len[static_cast<size_t>(a)];
  }

  std::vector<int> order(static_cast<size_t>(nlist));
  std::iota(order.begin(), order.end(), 0);
  std::sort(order.begin(), order.end(), [&](int a, int b) {
    if (list_len[a] != list_len[b]) return list_len[a] > list_len[b];
    return a < b;
  });

  std::vector<int> owner(static_cast<size_t>(nlist), 0);
  std::vector<std::int64_t> load(static_cast<size_t>(n_shards), 0);
  for (int list : order) {
    const size_t target =
        static_cast<size_t>(std::min_element(load.begin(), load.end()) - load.begin());
    owner[static_cast<size_t>(list)] = static_cast<int>(target);
    load[target] += list_len[static_cast<size_t>(list)];
  }

  // 3. Поддатасеты. Списки не пересекаются, значит и векторы не пересекаются:
  // объединение результатов шардов равно результату одиночного индекса.
  std::vector<Dataset> parts(static_cast<size_t>(n_shards));
  for (int sh = 0; sh < n_shards; ++sh) {
    parts[static_cast<size_t>(sh)].dim = base.dim;
    parts[static_cast<size_t>(sh)].n = 0;
    parts[static_cast<size_t>(sh)].data.reserve(static_cast<size_t>(load[sh]) * base.dim);
    s.shards[static_cast<size_t>(sh)]->global_ids.clear();
    s.shards[static_cast<size_t>(sh)]->global_ids.reserve(static_cast<size_t>(load[sh]));
  }
  for (std::int64_t i = 0; i < base.n; ++i) {
    const int sh = owner[static_cast<size_t>(assign[static_cast<size_t>(i)])];
    Dataset& part = parts[static_cast<size_t>(sh)];
    part.data.insert(part.data.end(), base.row(i), base.row(i) + base.dim);
    ++part.n;
    s.shards[static_cast<size_t>(sh)]->global_ids.push_back(static_cast<VectorId>(i));
  }

  s.run_on_shards([&](size_t i) {
    Impl::Shard& shard = *s.shards[i];
    shard.index->build(parts[i], shard.stream->get());
    shard.id_map.allocate(shard.global_ids.size());
    if (!shard.global_ids.empty()) {
      shard.id_map.copy_from_host(shard.global_ids.data(), shard.global_ids.size(),
                                  shard.stream->get());
    }
    VL_CUDA_CHECK(cudaStreamSynchronize(shard.stream->get()));
  });

#if defined(VECLENS_WITH_NCCL)
  if (s.params.use_nccl && s.comms.empty()) {
    s.comms.assign(s.shards.size(), nullptr);
    VL_NCCL_CHECK(ncclCommInitAll(s.comms.data(), static_cast<int>(s.devices.size()),
                                  s.devices.data()));
  }
#endif
  s.built = true;
}

SearchResult ShardedIvfIndex::search(const Dataset& queries, const SearchParams& params,
                                     Timing* timing) {
  VL_NVTX_RANGE("sharded.search");
  Impl& s = *impl_;
  if (!s.built) throw std::runtime_error("ShardedIvfIndex::search: индекс не построен");
  if (queries.dim != s.index_params.dim) {
    throw std::invalid_argument("ShardedIvfIndex::search: размерность запросов не совпадает");
  }

  const int nq = static_cast<int>(queries.n);
  const int k = params.k;
  const int n_shards = static_cast<int>(s.shards.size());
  const int dim_padded = s.index_params.dim_padded();

  SearchResult result;
  result.resize(nq, k);
  if (nq == 0 || k == 0) return result;

  std::vector<float> padded(static_cast<size_t>(nq) * dim_padded, 0.0f);
  for (int i = 0; i < nq; ++i) {
    std::memcpy(padded.data() + static_cast<size_t>(i) * dim_padded, queries.row(i),
                sizeof(float) * queries.dim);
  }

  const size_t part_elems = static_cast<size_t>(nq) * k;
  const auto t0 = std::chrono::steady_clock::now();

  // Каждая карта считает свои k и сразу переводит локальные номера в
  // глобальные: после этого части сравнимы между собой.
  s.run_on_shards([&](size_t i) {
    Impl::Shard& shard = *s.shards[i];
    cudaStream_t stream = shard.stream->get();

    shard.d_queries.resize(padded.size());
    shard.d_distances.resize(part_elems);
    shard.d_ids.resize(part_elems);

    shard.d_queries.copy_from_host(padded.data(), padded.size(), stream);
    shard.index->search_device(shard.d_queries.data(), nq, params, shard.d_distances.data(),
                               shard.d_ids.data(), stream);

    const int blocks = static_cast<int>(
        std::min<std::int64_t>((static_cast<std::int64_t>(part_elems) + kRemapBlock - 1) / kRemapBlock, 4096));
    remap_ids_kernel<<<blocks, kRemapBlock, 0, stream>>>(
        shard.d_ids.data(), static_cast<std::int64_t>(part_elems), shard.id_map.data(),
        static_cast<std::int64_t>(shard.global_ids.size()));
    VL_KERNEL_CHECK();
    VL_CUDA_CHECK(cudaStreamSynchronize(stream));
  });

  // ------------------------------------------------------------- сбор частей
  Impl::Shard& root = *s.shards[0];
  DeviceGuard guard(root.device);
  Stream merge_stream;

  DeviceBuffer<float> d_gathered(static_cast<size_t>(n_shards) * part_elems);
  DeviceBuffer<VectorId> d_gathered_ids(static_cast<size_t>(n_shards) * part_elems);

  bool gathered_on_device = false;
#if defined(VECLENS_WITH_NCCL)
  if (s.params.use_nccl && !s.comms.empty()) {
    // AllGather кладёт части в порядке рангов: [ранг][запрос][k].
    for (size_t i = 0; i < s.shards.size(); ++i) {
      // Приёмный буфер AllGather обязан лежать на той же карте, что и ранг,
      // поэтому выделение идёт под её контекстом, а не под текущим.
      DeviceGuard g(s.shards[i]->device);
      s.shards[i]->gathered_dist.resize(static_cast<size_t>(n_shards) * part_elems);
      s.shards[i]->gathered_ids.resize(static_cast<size_t>(n_shards) * part_elems);
    }
    VL_NCCL_CHECK(ncclGroupStart());
    for (size_t i = 0; i < s.shards.size(); ++i) {
      VL_NCCL_CHECK(ncclAllGather(s.shards[i]->d_distances.data(),
                                  s.shards[i]->gathered_dist.data(), part_elems, ncclFloat32,
                                  s.comms[i], s.shards[i]->stream->get()));
    }
    VL_NCCL_CHECK(ncclGroupEnd());

    VL_NCCL_CHECK(ncclGroupStart());
    for (size_t i = 0; i < s.shards.size(); ++i) {
      VL_NCCL_CHECK(ncclAllGather(s.shards[i]->d_ids.data(), s.shards[i]->gathered_ids.data(),
                                  part_elems, ncclUint32, s.comms[i],
                                  s.shards[i]->stream->get()));
    }
    VL_NCCL_CHECK(ncclGroupEnd());

    for (size_t i = 0; i < s.shards.size(); ++i) {
      DeviceGuard g(s.shards[i]->device);
      VL_CUDA_CHECK(cudaStreamSynchronize(s.shards[i]->stream->get()));
    }
    VL_CUDA_CHECK(cudaMemcpyAsync(d_gathered.data(), root.gathered_dist.data(),
                                  d_gathered.bytes(), cudaMemcpyDeviceToDevice,
                                  merge_stream.get()));
    VL_CUDA_CHECK(cudaMemcpyAsync(d_gathered_ids.data(), root.gathered_ids.data(),
                                  d_gathered_ids.bytes(), cudaMemcpyDeviceToDevice,
                                  merge_stream.get()));
    gathered_on_device = true;
  }
#endif

  if (!gathered_on_device) {
    // Путь без NCCL: части едут через хост. Для nq x k чисел это дешевле,
    // чем сложность настройки коммуникатора ради одного AllGather.
    std::vector<float> host_dist(static_cast<size_t>(n_shards) * part_elems);
    std::vector<VectorId> host_ids(static_cast<size_t>(n_shards) * part_elems);
    s.run_on_shards([&](size_t i) {
      Impl::Shard& shard = *s.shards[i];
      shard.d_distances.copy_to_host(host_dist.data() + i * part_elems, part_elems,
                                     shard.stream->get());
      shard.d_ids.copy_to_host(host_ids.data() + i * part_elems, part_elems, shard.stream->get());
      VL_CUDA_CHECK(cudaStreamSynchronize(shard.stream->get()));
    });
    d_gathered.copy_from_host(host_dist.data(), host_dist.size(), merge_stream.get());
    d_gathered_ids.copy_from_host(host_ids.data(), host_ids.size(), merge_stream.get());
  }

  DeviceBuffer<float> d_parts(static_cast<size_t>(n_shards) * part_elems);
  DeviceBuffer<VectorId> d_part_ids(static_cast<size_t>(n_shards) * part_elems);
  {
    const std::int64_t total = static_cast<std::int64_t>(n_shards) * part_elems;
    const int blocks =
        static_cast<int>(std::min<std::int64_t>((total + kRemapBlock - 1) / kRemapBlock, 4096));
    interleave_parts_kernel<<<blocks, kRemapBlock, 0, merge_stream.get()>>>(
        d_gathered.data(), d_gathered_ids.data(), n_shards, nq, k, d_parts.data(),
        d_part_ids.data());
    VL_KERNEL_CHECK();
  }

  DeviceBuffer<float> d_out(part_elems);
  DeviceBuffer<VectorId> d_out_ids(part_elems);
  launch_merge_topk(d_parts.data(), d_part_ids.data(), nq, n_shards, k, k,
                    s.index_params.metric, d_out.data(), d_out_ids.data(), merge_stream.get());

  d_out.copy_to_host(result.distances.data(), result.distances.size(), merge_stream.get());
  d_out_ids.copy_to_host(result.ids.data(), result.ids.size(), merge_stream.get());
  VL_CUDA_CHECK(cudaStreamSynchronize(merge_stream.get()));

  if (timing) {
    const auto t1 = std::chrono::steady_clock::now();
    timing->total_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
  }
  return result;
}

std::vector<IndexStats> ShardedIvfIndex::shard_stats() const {
  std::vector<IndexStats> out;
  out.reserve(impl_->shards.size());
  for (const auto& shard : impl_->shards) {
    DeviceGuard guard(shard->device);
    out.push_back(shard->index->stats());
  }
  return out;
}

int ShardedIvfIndex::shard_count() const { return static_cast<int>(impl_->shards.size()); }

}  // namespace veclens
