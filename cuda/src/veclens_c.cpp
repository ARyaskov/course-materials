#include "veclens/veclens_c.h"

#include <cstring>
#include <exception>
#include <memory>
#include <new>
#include <stdexcept>
#include <string>

#include "veclens/common.hpp"
#include "veclens/index_io.hpp"
#include "veclens/ivf_index.hpp"

// Дескриптор индекса для C-мира. Наружу отдаётся указатель на неполный тип:
// вызывающий не может ни скопировать его, ни залезть внутрь.
struct vl_index_s {
  std::unique_ptr<veclens::IvfFlatIndex> index;
};

namespace {

// Текст ошибки живёт по потоку: два потока, одновременно получившие ошибку,
// не должны затирать сообщения друг друга.
thread_local std::string g_last_error;

void set_error(const std::string& text) { g_last_error = text; }

vl_status_t status_from_exception() {
  // Единственное место, где исключения C++ превращаются в коды: пропустить
  // исключение через границу C — это UB, поэтому здесь ловится всё.
  try {
    throw;
  } catch (const veclens::CudaError& e) {
    set_error(e.what());
    return (e.code() == cudaErrorMemoryAllocation) ? VL_ERR_OUT_OF_MEMORY : VL_ERR_CUDA;
  } catch (const std::bad_alloc& e) {
    set_error(e.what());
    return VL_ERR_OUT_OF_MEMORY;
  } catch (const std::invalid_argument& e) {
    set_error(e.what());
    return VL_ERR_INVALID_ARGUMENT;
  } catch (const std::exception& e) {
    set_error(e.what());
    return VL_ERR_INTERNAL;
  } catch (...) {
    set_error("неизвестная ошибка");
    return VL_ERR_INTERNAL;
  }
}

template <typename F>
vl_status_t guard(F&& fn, vl_status_t generic = VL_ERR_INTERNAL) {
  try {
    g_last_error.clear();
    return fn();
  } catch (const veclens::CudaError&) {
    return status_from_exception();
  } catch (const std::bad_alloc&) {
    return status_from_exception();
  } catch (const std::invalid_argument&) {
    return status_from_exception();
  } catch (const std::exception& e) {
    // Для операций ввода-вывода общий код заменяется на VL_ERR_IO: вызывающему
    // важно отличить «файл не читается» от «внутри всё сломалось».
    set_error(e.what());
    return generic;
  } catch (...) {
    return status_from_exception();
  }
}

veclens::Metric to_metric(vl_metric_t metric) {
  switch (metric) {
    case VL_METRIC_L2: return veclens::Metric::L2;
    case VL_METRIC_IP: return veclens::Metric::InnerProduct;
    case VL_METRIC_COSINE: return veclens::Metric::Cosine;
  }
  throw std::invalid_argument("неизвестная метрика в vl_index_params_t");
}

veclens::Dataset make_dataset(const float* vectors, std::int64_t n, int dim) {
  if (!vectors) throw std::invalid_argument("указатель на векторы равен NULL");
  if (n <= 0) throw std::invalid_argument("число векторов должно быть положительным");
  veclens::Dataset ds;
  ds.resize(n, dim);
  std::memcpy(ds.data.data(), vectors, sizeof(float) * static_cast<size_t>(n) * dim);
  return ds;
}

}  // namespace

extern "C" {

vl_status_t vl_index_create(const vl_index_params_t* params, vl_index_t* out_index) {
  return guard([&]() -> vl_status_t {
    if (!params || !out_index) {
      set_error("vl_index_create: NULL-аргумент");
      return VL_ERR_INVALID_ARGUMENT;
    }
    if (params->dim <= 0 || params->nlist <= 0) {
      set_error("vl_index_create: dim и nlist должны быть положительными");
      return VL_ERR_INVALID_ARGUMENT;
    }

    veclens::IndexParams p;
    p.dim = params->dim;
    p.nlist = params->nlist;
    p.metric = to_metric(params->metric);
    p.kmeans_iters = params->kmeans_iters > 0 ? params->kmeans_iters : p.kmeans_iters;
    p.seed = params->seed != 0 ? params->seed : p.seed;

    auto handle = std::make_unique<vl_index_s>();
    handle->index = std::make_unique<veclens::IvfFlatIndex>(p);
    *out_index = handle.release();
    return VL_OK;
  });
}

void vl_index_free(vl_index_t index) { delete index; }

vl_status_t vl_index_train(vl_index_t index, const float* vectors, int64_t n) {
  return guard([&]() -> vl_status_t {
    if (!index) {
      set_error("vl_index_train: index == NULL");
      return VL_ERR_INVALID_ARGUMENT;
    }
    const veclens::Dataset ds = make_dataset(vectors, n, index->index->params().dim);
    index->index->train(ds, nullptr);
    return VL_OK;
  });
}

vl_status_t vl_index_build(vl_index_t index, const float* vectors, int64_t n) {
  return guard([&]() -> vl_status_t {
    if (!index) {
      set_error("vl_index_build: index == NULL");
      return VL_ERR_INVALID_ARGUMENT;
    }
    if (!index->index->trained()) {
      set_error("vl_index_build: индекс не обучен, сначала vl_index_train");
      return VL_ERR_NOT_TRAINED;
    }
    const veclens::Dataset ds = make_dataset(vectors, n, index->index->params().dim);
    index->index->build(ds, nullptr);
    return VL_OK;
  });
}

vl_status_t vl_index_save(vl_index_t index, const char* path) {
  return guard(
      [&]() -> vl_status_t {
        if (!index || !path) {
          set_error("vl_index_save: NULL-аргумент");
          return VL_ERR_INVALID_ARGUMENT;
        }
        veclens::IndexSerializer::save(*index->index, path);
        return VL_OK;
      },
      VL_ERR_IO);
}

vl_status_t vl_index_load(const char* path, vl_index_t* out_index) {
  return guard(
      [&]() -> vl_status_t {
        if (!path || !out_index) {
          set_error("vl_index_load: NULL-аргумент");
          return VL_ERR_INVALID_ARGUMENT;
        }
        auto handle = std::make_unique<vl_index_s>();
        // Загрузчик уже отдаёт владеющий указатель, перекладывать нечего.
        handle->index = veclens::IndexSerializer::load(path);
        *out_index = handle.release();
        return VL_OK;
      },
      VL_ERR_IO);
}

vl_status_t vl_index_search(vl_index_t index, const float* queries, int32_t nq,
                            const vl_search_params_t* params, float* out_distances,
                            uint32_t* out_ids) {
  return guard([&]() -> vl_status_t {
    if (!index || !queries || !params || !out_distances || !out_ids) {
      set_error("vl_index_search: NULL-аргумент");
      return VL_ERR_INVALID_ARGUMENT;
    }
    if (nq <= 0 || params->k <= 0 || params->nprobe <= 0) {
      set_error("vl_index_search: nq, k и nprobe должны быть положительными");
      return VL_ERR_INVALID_ARGUMENT;
    }
    if (!index->index->trained()) {
      set_error("vl_index_search: индекс не обучен");
      return VL_ERR_NOT_TRAINED;
    }

    const veclens::Dataset ds = make_dataset(queries, nq, index->index->params().dim);

    veclens::SearchParams sp;
    sp.k = params->k;
    sp.nprobe = params->nprobe;
    sp.refine_factor = params->refine_factor > 0 ? params->refine_factor : 1;

    const veclens::SearchResult result = index->index->search(ds, sp, nullptr);

    // Владение выходными массивами остаётся за вызывающим: движок только
    // заполняет уже выделенную им память.
    std::memcpy(out_distances, result.distances.data(),
                sizeof(float) * result.distances.size());
    std::memcpy(out_ids, result.ids.data(), sizeof(uint32_t) * result.ids.size());
    return VL_OK;
  });
}

int64_t vl_index_size(vl_index_t index) {
  if (!index || !index->index) return 0;
  return static_cast<int64_t>(index->index->size());
}

const char* vl_status_string(vl_status_t status) {
  switch (status) {
    case VL_OK: return "ok";
    case VL_ERR_INVALID_ARGUMENT: return "invalid argument";
    case VL_ERR_NOT_TRAINED: return "index is not trained";
    case VL_ERR_CUDA: return "CUDA error";
    case VL_ERR_IO: return "I/O error";
    case VL_ERR_UNSUPPORTED_DEVICE: return "unsupported device";
    case VL_ERR_OUT_OF_MEMORY: return "out of memory";
    case VL_ERR_INTERNAL: return "internal error";
  }
  return "unknown status";
}

const char* vl_last_error(void) { return g_last_error.c_str(); }

const char* vl_version(void) { return "veclens 1.0.0"; }

}  // extern "C"
