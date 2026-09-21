#include "TimeLog.hpp"

namespace timelogger {

void TimeLog::startWork(const Timestamp timestamp,
                        std::vector<std::string> targetDirectories) {
    timeIn_ = timestamp;
    timeOut_.reset();
    targetDirectories_ = std::move(targetDirectories);
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

const std::vector<std::string>& TimeLog::targetDirectories() const noexcept {
    return targetDirectories_;
}

bool TimeLog::isComplete() const noexcept {
    return timeIn_.has_value() && timeOut_.has_value() && *timeOut_ >= *timeIn_;
}

} // namespace timelogger
