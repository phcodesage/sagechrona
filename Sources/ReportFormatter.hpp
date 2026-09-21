#pragma once

#include "GitTracker.hpp"

#include <chrono>
#include <string>
#include <vector>

namespace timelogger {

inline constexpr auto kMaximumReportDuration = std::chrono::minutes{492};

struct ReportSection final {
    Timestamp start;
    Timestamp end;
    std::vector<GitCommit> commits;
};

[[nodiscard]] std::vector<ReportSection> splitReport(const std::vector<GitCommit>& commits,
                                                     Timestamp start,
                                                     Timestamp end);
[[nodiscard]] std::string formatCommit(const GitCommit& commit);
[[nodiscard]] std::string formatReport(const std::vector<GitCommit>& commits,
                                       Timestamp start,
                                       Timestamp end);

} // namespace timelogger
