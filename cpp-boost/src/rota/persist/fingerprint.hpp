#pragma once

// Content fingerprints with Boost.Hash2: a SHA-256 over the described members of a
// pipeline_spec, so the daemon (and the API) can tell whether a pipeline definition changed
// between restarts without comparing files byte by byte.

#include "rota/model/pipeline.hpp"

#include <string>
#include <string_view>

namespace rota::persist {

std::string sha256_hex(std::string_view bytes);
std::string pipeline_fingerprint(const model::pipeline_spec& spec);

} // namespace rota::persist
