#pragma once

// Run archive: finished runs are written as gzip-compressed JSON (Boost.Iostreams filter
// chains) into data/archive/<run-id>.json.gz, and read back through the same chain.

#include "rota/core/errors.hpp"
#include "rota/model/run.hpp"

#include <filesystem>
#include <string>

namespace rota::ops {

class run_archive {
public:
    explicit run_archive(std::filesystem::path dir);

    result<std::filesystem::path> write(const model::run& run) const;
    result<model::run> read(const run_id& id) const;

    // Reads any .gz text file through a gzip_decompressor; used by rota-cli.
    static result<std::string> read_gzip_text(const std::filesystem::path& file);
    static result<void> write_gzip_text(const std::filesystem::path& file, std::string_view text);

    const std::filesystem::path& dir() const noexcept { return dir_; }

private:
    std::filesystem::path dir_;
};

} // namespace rota::ops
