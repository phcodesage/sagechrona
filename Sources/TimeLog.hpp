#pragma once

#include <chrono>
#include <optional>

namespace timelogger {

using Timestamp = std::chrono::system_clock::time_point;

// Domain state is independent of AppKit so persistence, reporting, and project
// tracking can be added without coupling those features to the macOS UI.
class TimeLog final {
public:
    void startWork(Timestamp timestamp) noexcept;
    void endWork(Timestamp timestamp) noexcept;

    [[nodiscard]] const std::optional<Timestamp>& timeIn() const noexcept;
    [[nodiscard]] const std::optional<Timestamp>& timeOut() const noexcept;

private:
    std::optional<Timestamp> timeIn_;
    std::optional<Timestamp> timeOut_;
};

} // namespace timelogger
