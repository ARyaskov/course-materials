/* C-API для встраивания движка в сервисы на других языках.
 * В публичном заголовке нет ни CUDA-типов, ни C++: подключить его можно
 * из любого рантайма, умеющего вызывать C-функции. */
#ifndef VECLENS_C_H
#define VECLENS_C_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vl_index_s* vl_index_t;

typedef enum {
  VL_OK = 0,
  VL_ERR_INVALID_ARGUMENT = 1,
  VL_ERR_NOT_TRAINED = 2,
  VL_ERR_CUDA = 3,
  VL_ERR_IO = 4,
  VL_ERR_UNSUPPORTED_DEVICE = 5,
  VL_ERR_OUT_OF_MEMORY = 6,
  VL_ERR_INTERNAL = 7
} vl_status_t;

typedef enum { VL_METRIC_L2 = 0, VL_METRIC_IP = 1, VL_METRIC_COSINE = 2 } vl_metric_t;

typedef struct {
  int32_t dim;
  int32_t nlist;
  vl_metric_t metric;
  int32_t kmeans_iters;
  uint64_t seed;
} vl_index_params_t;

typedef struct {
  int32_t k;
  int32_t nprobe;
  int32_t refine_factor;
} vl_search_params_t;

/* Владение памятью: вызывающий владеет всеми массивами, движок владеет
 * дескриптором индекса и освобождает его в vl_index_free. */
vl_status_t vl_index_create(const vl_index_params_t* params, vl_index_t* out_index);
void        vl_index_free(vl_index_t index);

vl_status_t vl_index_train(vl_index_t index, const float* vectors, int64_t n);
vl_status_t vl_index_build(vl_index_t index, const float* vectors, int64_t n);
vl_status_t vl_index_save(vl_index_t index, const char* path);
vl_status_t vl_index_load(const char* path, vl_index_t* out_index);

vl_status_t vl_index_search(vl_index_t index, const float* queries, int32_t nq,
                            const vl_search_params_t* params, float* out_distances,
                            uint32_t* out_ids);

int64_t     vl_index_size(vl_index_t index);
const char* vl_status_string(vl_status_t status);
const char* vl_last_error(void);
const char* vl_version(void);

#ifdef __cplusplus
}
#endif

#endif /* VECLENS_C_H */
