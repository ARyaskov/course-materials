#include <algorithm>
#include <vector>

#include "veclens/distance.cuh"
#include "veclens/ivf_index.hpp"
#include "veclens/nvtx.hpp"
#include "veclens/topk.hpp"

namespace veclens {

FlatIndex::FlatIndex(const IndexParams& params) : params_(params) {}

void FlatIndex::build(const Dataset& base, cudaStream_t stream) {
  if (base.dim != params_.dim) {
    throw std::invalid_argument("FlatIndex::build: размерность базы не совпадает с параметрами");
  }
  Dataset copy = base;
  if (params_.metric == Metric::Cosine) normalize_rows(copy);
  store_.upload(copy, params_.dim_padded(), stream);
}

SearchResult FlatIndex::search(const Dataset& queries, const SearchParams& params,
                               Timing* timing) {
  VL_NVTX_RANGE("flat_search");

  const int nq = static_cast<int>(queries.n);
  const std::int64_t n = store_.size();
  const int dim_padded = store_.dim_padded();

  SearchResult result;
  result.resize(nq, params.k);
  if (n == 0 || nq == 0) return result;

  Stream stream;
  Event t0(cudaEventDefault), t1(cudaEventDefault), t2(cudaEventDefault), t3(cudaEventDefault);

  Dataset q = queries;
  if (params_.metric == Metric::Cosine) normalize_rows(q);

  VectorStore query_store;
  t0.record(stream);
  query_store.upload(q, dim_padded, stream);
  t1.record(stream);

  // Матрица расстояний nq x n целиком: при большой базе это гигабайты,
  // поэтому Flat остаётся эталоном для проверки, а не рабочим режимом.
  const std::int64_t elements = static_cast<std::int64_t>(nq) * n;
  scratch_distances_.resize(static_cast<size_t>(elements));

  launch_brute_force(store_.data(), store_.norms(), n, query_store.data(), query_store.norms(), nq,
                     dim_padded, params_.metric, scratch_distances_.data(), params.block_size,
                     stream);
  t2.record(stream);

  DeviceBuffer<float> out_dist(static_cast<size_t>(nq) * params.k);
  DeviceBuffer<VectorId> out_ids(static_cast<size_t>(nq) * params.k);

  const TopKAlgo algo =
      params.topk_algo == TopKAlgo::Auto ? select_topk_algo(params.k, static_cast<int>(n))
                                         : params.topk_algo;
  const size_t scratch_bytes = topk_scratch_bytes(nq, static_cast<int>(n), params.k, algo);
  DeviceBuffer<char> scratch(scratch_bytes);

  launch_topk(scratch_distances_.data(), store_.ids(), nq, static_cast<int>(n), params.k,
              params_.metric, out_dist.data(), out_ids.data(), algo, scratch.data(), scratch_bytes,
              stream);
  t3.record(stream);

  out_dist.copy_to_host(result.distances.data(), result.distances.size(), stream);
  out_ids.copy_to_host(result.ids.data(), result.ids.size(), stream);
  stream.synchronize();

  if (timing) {
    timing->h2d_ms = Event::elapsed_ms(t0, t1);
    timing->scan_ms = Event::elapsed_ms(t1, t2);
    timing->topk_ms = Event::elapsed_ms(t2, t3);
    timing->total_ms = Event::elapsed_ms(t0, t3);
  }
  return result;
}

double recall_at_k(const SearchResult& approx, const SearchResult& exact, int k) {
  if (approx.nq != exact.nq || approx.nq == 0) return 0.0;
  k = std::min({k, approx.k, exact.k});

  std::int64_t hits = 0;
  std::vector<VectorId> truth;
  truth.reserve(k);

  for (int q = 0; q < approx.nq; ++q) {
    truth.assign(exact.row_ids(q), exact.row_ids(q) + k);
    std::sort(truth.begin(), truth.end());
    const VectorId* found = approx.row_ids(q);
    for (int i = 0; i < k; ++i) {
      if (found[i] != kInvalidId && std::binary_search(truth.begin(), truth.end(), found[i])) {
        ++hits;
      }
    }
  }
  return static_cast<double>(hits) / (static_cast<double>(approx.nq) * k);
}

}  // namespace veclens
