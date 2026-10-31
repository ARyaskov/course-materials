#include "veclens/index_io.hpp"

#include <cuda_runtime_api.h>

#include <algorithm>
#include <cstring>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include "veclens/common.hpp"

namespace veclens {

// distance.cuh содержит __device__-код и хостовым компилятором не собирается,
// поэтому нужная отсюда функция объявляется повторно. Определение одно — в
// distance.cu, компоновщик сведёт объявления вместе.
void launch_compute_norms(const float* data, std::int64_t n, int dim_padded, float* out_norms,
                          cudaStream_t stream);

namespace {

// Секции выравниваются на 256 байт: это гарантия cudaMalloc и требование
// векторизованных загрузок, так что файл можно при желании отобразить в память
// и передать в ядро без перекладывания.
constexpr std::uint64_t kAlignment = 256;

std::uint64_t align_up(std::uint64_t value) {
  return (value + kAlignment - 1) / kAlignment * kAlignment;
}

void write_padding(std::ofstream& out, std::uint64_t written, std::uint64_t target) {
  static const char kZeros[kAlignment] = {};
  while (written < target) {
    const std::uint64_t chunk = std::min<std::uint64_t>(kAlignment, target - written);
    out.write(kZeros, static_cast<std::streamsize>(chunk));
    written += chunk;
  }
}

void check_stream(const std::ifstream& in, const std::string& path) {
  if (!in) throw std::runtime_error("IndexSerializer: ошибка чтения " + path);
}

}  // namespace

IndexFileHeader IndexSerializer::read_header(const std::string& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) throw std::runtime_error("IndexSerializer: не удалось открыть " + path);

  IndexFileHeader header{};
  in.read(reinterpret_cast<char*>(&header), sizeof(header));
  if (!in) throw std::runtime_error("IndexSerializer: файл короче заголовка: " + path);

  if (header.magic != kIndexMagic) {
    throw std::runtime_error("IndexSerializer: " + path +
                             " не является индексом veclens (magic 0x" +
                             std::to_string(header.magic) + ", ожидался 0x" +
                             std::to_string(kIndexMagic) + ')');
  }
  if (header.version != kIndexVersion) {
    throw std::runtime_error("IndexSerializer: " + path + " версии " +
                             std::to_string(header.version) + ", поддерживается версия " +
                             std::to_string(kIndexVersion) +
                             ". Индекс нужно перестроить.");
  }
  if (header.dim <= 0 || header.dim_padded < header.dim || header.nlist <= 0 ||
      header.n_vectors < 0) {
    throw std::runtime_error("IndexSerializer: повреждённый заголовок " + path);
  }
  return header;
}

void IndexSerializer::save(const IvfFlatIndex& index, const std::string& path) {
  const IndexParams& params = index.params();
  const int nlist = params.nlist;
  const int dim_padded = params.dim_padded();
  const std::int64_t n = index.size();

  IndexFileHeader header{};
  header.magic = kIndexMagic;
  header.version = kIndexVersion;
  header.dim = params.dim;
  header.dim_padded = dim_padded;
  header.nlist = nlist;
  header.metric = static_cast<std::int32_t>(params.metric);
  header.storage = static_cast<std::int32_t>(params.storage);
  header.n_vectors = n;

  const std::uint64_t centroids_bytes =
      static_cast<std::uint64_t>(nlist) * dim_padded * sizeof(float);
  const std::uint64_t offsets_bytes =
      (static_cast<std::uint64_t>(nlist) + 1) * sizeof(std::int32_t);
  const std::uint64_t data_bytes = static_cast<std::uint64_t>(n) * dim_padded * sizeof(float);
  const std::uint64_t ids_bytes = static_cast<std::uint64_t>(n) * sizeof(VectorId);

  std::uint64_t cursor = align_up(sizeof(IndexFileHeader));
  header.centroids_offset = cursor;
  cursor = align_up(cursor + centroids_bytes);
  header.offsets_offset = cursor;
  cursor = align_up(cursor + offsets_bytes);
  header.data_offset = cursor;
  cursor = align_up(cursor + data_bytes);
  header.ids_offset = cursor;
  cursor = align_up(cursor + ids_bytes);
  header.total_bytes = cursor;

  // Данные забираются с устройства целиком: индекс на диск пишется редко,
  // а поблочная выгрузка здесь усложнила бы код без выигрыша.
  const std::vector<float> centroids = index.centroids().to_host();
  const std::vector<std::int32_t> offsets = index.list_offsets().to_host();
  const std::vector<float> data = index.list_data().to_host();
  const std::vector<VectorId> ids = index.list_ids().to_host();

  if (centroids.size() * sizeof(float) < centroids_bytes ||
      offsets.size() * sizeof(std::int32_t) < offsets_bytes ||
      data.size() * sizeof(float) < data_bytes || ids.size() * sizeof(VectorId) < ids_bytes) {
    throw std::runtime_error("IndexSerializer::save: буферы индекса меньше заявленных размеров");
  }

  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  if (!out) throw std::runtime_error("IndexSerializer: не удалось открыть для записи " + path);

  out.write(reinterpret_cast<const char*>(&header), sizeof(header));
  write_padding(out, sizeof(header), header.centroids_offset);

  out.write(reinterpret_cast<const char*>(centroids.data()),
            static_cast<std::streamsize>(centroids_bytes));
  write_padding(out, header.centroids_offset + centroids_bytes, header.offsets_offset);

  out.write(reinterpret_cast<const char*>(offsets.data()),
            static_cast<std::streamsize>(offsets_bytes));
  write_padding(out, header.offsets_offset + offsets_bytes, header.data_offset);

  out.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data_bytes));
  write_padding(out, header.data_offset + data_bytes, header.ids_offset);

  out.write(reinterpret_cast<const char*>(ids.data()), static_cast<std::streamsize>(ids_bytes));
  write_padding(out, header.ids_offset + ids_bytes, header.total_bytes);

  out.flush();
  if (!out) throw std::runtime_error("IndexSerializer: ошибка записи " + path);
}

std::unique_ptr<IvfFlatIndex> IndexSerializer::load(const std::string& path) {
  const IndexFileHeader header = read_header(path);

  IndexParams params;
  params.dim = header.dim;
  params.nlist = header.nlist;
  params.metric = static_cast<Metric>(header.metric);
  params.storage = static_cast<StorageType>(header.storage);
  if (params.dim_padded() != header.dim_padded) {
    throw std::runtime_error("IndexSerializer::load: dim_padded в файле не согласован с dim");
  }

  const std::int64_t n = header.n_vectors;
  const int nlist = header.nlist;
  const int dim_padded = header.dim_padded;

  std::ifstream in(path, std::ios::binary);
  if (!in) throw std::runtime_error("IndexSerializer: не удалось открыть " + path);

  std::vector<float> centroids(static_cast<size_t>(nlist) * dim_padded);
  in.seekg(static_cast<std::streamoff>(header.centroids_offset));
  in.read(reinterpret_cast<char*>(centroids.data()),
          static_cast<std::streamsize>(centroids.size() * sizeof(float)));
  check_stream(in, path);

  std::vector<std::int32_t> offsets(static_cast<size_t>(nlist) + 1);
  in.seekg(static_cast<std::streamoff>(header.offsets_offset));
  in.read(reinterpret_cast<char*>(offsets.data()),
          static_cast<std::streamsize>(offsets.size() * sizeof(std::int32_t)));
  check_stream(in, path);

  if (offsets.front() != 0 || offsets.back() != static_cast<std::int32_t>(n)) {
    throw std::runtime_error("IndexSerializer::load: список смещений не соответствует n");
  }

  std::vector<float> data(static_cast<size_t>(n) * dim_padded);
  in.seekg(static_cast<std::streamoff>(header.data_offset));
  in.read(reinterpret_cast<char*>(data.data()),
          static_cast<std::streamsize>(data.size() * sizeof(float)));
  check_stream(in, path);

  std::vector<VectorId> ids(static_cast<size_t>(n));
  in.seekg(static_cast<std::streamoff>(header.ids_offset));
  in.read(reinterpret_cast<char*>(ids.data()),
          static_cast<std::streamsize>(ids.size() * sizeof(VectorId)));
  check_stream(in, path);

  auto holder = std::make_unique<IvfFlatIndex>(params);
  IvfFlatIndex& index = *holder;

  // Доступ к приватным полям — через friend-объявление в IvfFlatIndex:
  // загрузка не пересобирает списки, она просто кладёт их на место.
  index.n_ = n;
  index.trained_ = true;

  index.centroids_.allocate(centroids.size());
  index.centroids_.copy_from_host(centroids.data(), centroids.size());
  index.list_offsets_.allocate(offsets.size());
  index.list_offsets_.copy_from_host(offsets.data(), offsets.size());
  index.list_data_.allocate(data.size());
  if (!data.empty()) index.list_data_.copy_from_host(data.data(), data.size());
  index.list_ids_.allocate(ids.size());
  if (!ids.empty()) index.list_ids_.copy_from_host(ids.data(), ids.size());
  VL_CUDA_CHECK(cudaStreamSynchronize(nullptr));

  // Нормы в файле не хранятся: они однозначно выводятся из векторов, а
  // пересчёт на карте дешевле, чем лишние 4 байта на вектор на диске.
  index.centroid_norms_.allocate(static_cast<size_t>(nlist));
  launch_compute_norms(index.centroids_.data(), nlist, dim_padded,
                       index.centroid_norms_.data(), nullptr);
  index.list_norms_.allocate(static_cast<size_t>(n));
  if (n > 0) {
    launch_compute_norms(index.list_data_.data(), n, dim_padded, index.list_norms_.data(),
                         nullptr);
  }
  VL_CUDA_CHECK(cudaStreamSynchronize(nullptr));

  return holder;
}

}  // namespace veclens
