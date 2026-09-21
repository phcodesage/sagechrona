#pragma once

#include "TimeLog.hpp"

#include <string>
#include <vector>

namespace timelogger {

struct GitCommit final {
    std::string hash;
    Timestamp committedAt;
    std::string subject;
    std::vector<std::string> changedPaths;
};

struct GitResult final {
    std::vector<GitCommit> commits;
    std::string error;

    [[nodiscard]] bool succeeded() const noexcept { return error.empty(); }
};

class GitTracker final {
public:
    [[nodiscard]] static std::string validateDirectory(const std::string& directory);
    [[nodiscard]] static GitResult commitsBetween(const std::string& directory,
                                                  Timestamp start,
                                                  Timestamp end);
};

} // namespace timelogger
