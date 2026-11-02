// Sample Rota executor plugin: "echo". It writes the payload and arguments into the result
// message and succeeds unless the payload starts with "fail:". Useful for smoke tests and
// as a template for real plugins (notifications, HTTP calls, database jobs).

#include "rota/exec/plugin_api.h"

#include <cstdio>
#include <cstring>
#include <string>

namespace {

int echo_execute(const rota_exec_request_v1* req, rota_exec_result_v1* res) {
    std::string text = req->payload ? req->payload : "";
    for (int i = 0; i < req->argc; ++i) {
        text += ' ';
        text += req->argv[i];
    }
    std::snprintf(res->message, sizeof(res->message), "[echo] run=%s task=%s attempt=%d: %s",
                  req->run_id, req->task, req->attempt, text.c_str());
    res->exit_code = text.rfind("fail:", 0) == 0 ? 1 : 0;
    return 0;
}

const rota_plugin_api_v1 api{ROTA_PLUGIN_ABI_VERSION, "echo", &echo_execute};

} // namespace

extern "C" ROTA_PLUGIN_EXPORT const rota_plugin_api_v1* rota_plugin_entry(void) {
    return &api;
}
