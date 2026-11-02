#pragma once

#include <algorithm>
#include <string_view>

namespace rota {

// Task names also become directory components on every supported platform.
inline bool valid_task_name(std::string_view name) {
    return !name.empty() && name.size() <= 100 &&
        std::ranges::all_of(name, [](unsigned char c) {
            return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                   (c >= '0' && c <= '9') || c == '-' || c == '_';
        });
}

} // namespace rota
