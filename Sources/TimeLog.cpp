#include "TimeLog.hpp"

namespace timelogger {

void TimeLog::startWork(const Timestamp timestamp) noexcept {
    timeIn_ = timestamp;
}

void TimeLog::endWork(const Timestamp timestamp) noexcept {
    timeOut_ = timestamp;
}

const std::optional<Timestamp>& TimeLog::timeIn() const noexcept {
    return timeIn_;
}

const std::optional<Timestamp>& TimeLog::timeOut() const noexcept {
    return timeOut_;
}

} // namespace timelogger
