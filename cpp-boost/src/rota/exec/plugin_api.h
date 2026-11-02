#pragma once

/*
 * Rota executor plugin ABI (version 1).
 *
 * A plugin is a shared library exporting one C function:
 *
 *     const rota_plugin_api_v1* rota_plugin_entry(void);
 *
 * Only C types cross the boundary: no std::string, no exceptions, no Boost types.
 * The daemon loads plugins with Boost.DLL and checks abi_version before any call.
 */

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ROTA_PLUGIN_ABI_VERSION 1u
#define ROTA_PLUGIN_ENTRY_NAME "rota_plugin_entry"

typedef struct rota_exec_request_v1 {
    const char* run_id;
    const char* task;
    int attempt;
    const char* payload;            /* task_spec.command */
    int argc;
    const char* const* argv;        /* task_spec.args */
    const char* workdir;
} rota_exec_request_v1;

typedef struct rota_exec_result_v1 {
    int exit_code;                  /* 0 = success */
    char message[1024];             /* NUL-terminated; shown as output tail */
} rota_exec_result_v1;

typedef struct rota_plugin_api_v1 {
    unsigned abi_version;           /* must equal ROTA_PLUGIN_ABI_VERSION */
    const char* name;               /* executor name used in task_spec.executor */
    /* Executes one attempt synchronously; returns 0 if the call itself succeeded. */
    int (*execute)(const rota_exec_request_v1* request, rota_exec_result_v1* result);
} rota_plugin_api_v1;

typedef const rota_plugin_api_v1* (*rota_plugin_entry_fn)(void);

#if defined(_WIN32)
#define ROTA_PLUGIN_EXPORT __declspec(dllexport)
#else
#define ROTA_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
}
#endif
