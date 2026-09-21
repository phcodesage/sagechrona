#include "TimeLog.hpp"

namespace timelogger {

void TimeLog::startWork(const Timestamp timestamp, std::string targetDirectory) {
    timeIn_ = timestamp;
    timeOut_.reset();
    targetDirectory_ = std::move(targetDirectory);
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

const std::string& TimeLog::targetDirectory() const noexcept {
    return targetDirectory_;
}

bool TimeLog::isComplete() const noexcept {
    return timeIn_.has_value() && timeOut_.has_value() && *timeOut_ >= *timeIn_;
}

} // namespace timelogger
