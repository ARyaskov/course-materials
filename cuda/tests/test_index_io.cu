#define VL_TEST_MAIN
#include "test_main.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <cstdio>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

#include "veclens/common.hpp"
#include "veclens/dataset.hpp"
#include "veclens/index_io.hpp"
#include "veclens/ivf_index.hpp"

using namespace veclens;

namespace {

constexpr int kDim = 50;      // не кратно 4: заодно проверяется дополнение до dim_padded
constexpr int kNlist = 16;
constexpr std::int64_t kN = 8000;
constexpr int kNq = 32;

const char* kPath = "veclens_test_index.vlx";

IndexParams make_params() {
  IndexParams params;
  params.dim = kDim;
  params.nlist = kNlist;
  params.metric = Metric::L2;
  params.kmeans_iters = 10;
  params.seed = 777ull;
  return params;
}

Dataset take_prefix(const Dataset& base, std::int64_t rows) {
  Dataset out;
  out.resize(std::min(rows, base.n), base.dim);
  std::copy(base.data.begin(), base.data.begin() + out.data.size(), out.data.begin());
  return out;
}

struct FileGuard {
  explicit FileGuard(const char* path) : path_(path) {}
  ~FileGuard() { std::remove(path_); }
  const char* path_;
};

}  // namespace

VL_TEST(index_io_roundtrip_preserves_search) {
  const IndexParams params = make_params();
  const Dataset base = generate_clustered(kN, kDim, kNlist / 2, 0.2f, params.seed);
  const Dataset queries = generate_queries(base, kNq, 0.02f, params.seed + 1);

  SearchParams search;
  search.k = 10;
  search.nprobe = 8;

  SearchResult before;
  std::vector<std::int32_t> lengths_before;
  {
    IvfFlatIndex index(params);
    index.train(take_prefix(base, 4000), nullptr);
    index.build(base, nullptr);
    before = index.search(queries, search, nullptr);
    lengths_before = index.list_lengths();

    FileGuard guard(kPath);
    IndexSerializer::save(index, kPath);

    // Заголовок читается отдельно от данных: так утилита может показать
    // параметры индекса, не загружая гигабайты в память.
    const IndexFileHeader header = IndexSerializer::read_header(kPath);
    VL_CHECK(header.magic == kIndexMagic);
    VL_CHECK(header.version == kIndexVersion);
    VL_CHECK(header.dim == kDim);
    VL_CHECK(header.dim_padded == params.dim_padded());
    VL_CHECK(header.nlist == kNlist);
    VL_CHECK(header.n_vectors == kN);
    VL_CHECK(header.metric == static_cast<std::int32_t>(Metric::L2));

    // Секции выровнены на 256 байт, смещения строго возрастают.
    VL_CHECK(header.centroids_offset % 256 == 0);
    VL_CHECK(header.offsets_offset % 256 == 0);
    VL_CHECK(header.data_offset % 256 == 0);
    VL_CHECK(header.ids_offset % 256 == 0);
    VL_CHECK(header.centroids_offset < header.offsets_offset);
    VL_CHECK(header.offsets_offset < header.data_offset);
    VL_CHECK(header.data_offset < header.ids_offset);
    VL_CHECK(header.ids_offset < header.total_bytes);

    std::ifstream file(kPath, std::ios::binary | std::ios::ate);
    VL_CHECK(static_cast<std::uint64_t>(file.tellg()) == header.total_bytes);

    const std::unique_ptr<IvfFlatIndex> loaded = IndexSerializer::load(kPath);
    VL_CHECK(loaded != nullptr);
    VL_CHECK(loaded->trained());
    VL_CHECK(loaded->size() == kN);
    VL_CHECK(loaded->params().dim == kDim);
    VL_CHECK(loaded->params().nlist == kNlist);

    const std::vector<std::int32_t> lengths_after = loaded->list_lengths();
    VL_CHECK(lengths_after.size() == lengths_before.size());
    for (size_t i = 0; i < lengths_after.size(); ++i) {
      VL_CHECK(lengths_after[i] == lengths_before[i]);
    }

    // Главная проверка: загруженный индекс ищет то же самое. Списки не
    // пересобираются, поэтому результат обязан совпасть побитово.
    const SearchResult after = loaded->search(queries, search, nullptr);
    VL_CHECK(after.nq == before.nq);
    VL_CHECK(after.k == before.k);
    for (size_t i = 0; i < before.ids.size(); ++i) {
      VL_CHECK(after.ids[i] == before.ids[i]);
      VL_CHECK_NEAR(after.distances[i], before.distances[i], 1e-5);
    }
  }
}

VL_TEST(index_io_rejects_foreign_file) {
  const char* path = "veclens_test_not_an_index.bin";
  FileGuard guard(path);
  {
    std::ofstream out(path, std::ios::binary);
    const std::vector<char> junk(1024, 0x5A);
    out.write(junk.data(), static_cast<std::streamsize>(junk.size()));
  }

  bool threw = false;
  try {
    IndexSerializer::read_header(path);
  } catch (const std::exception&) {
    threw = true;
  }
  VL_CHECK(threw);
}

VL_TEST(index_io_rejects_missing_file) {
  bool threw = false;
  try {
    IndexSerializer::read_header("veclens_test_definitely_absent.vlx");
  } catch (const std::exception&) {
    threw = true;
  }
  VL_CHECK(threw);
}

VL_TEST(index_io_rejects_wrong_version) {
  const char* path = "veclens_test_old_version.vlx";
  FileGuard guard(path);
  {
    IndexFileHeader header{};
    header.magic = kIndexMagic;
    header.version = kIndexVersion + 1;
    header.dim = kDim;
    header.dim_padded = kDim;
    header.nlist = kNlist;
    header.n_vectors = 0;
    std::ofstream out(path, std::ios::binary);
    out.write(reinterpret_cast<const char*>(&header), sizeof(header));
  }

  bool threw = false;
  try {
    IndexSerializer::read_header(path);
  } catch (const std::exception&) {
    threw = true;
  }
  VL_CHECK(threw);
}
