#include "TimeLog.hpp"

#include <cassert>
#include <chrono>

int main() {
    using namespace std::chrono_literals;

    timelogger::TimeLog log;
    assert(!log.timeIn().has_value());
    assert(!log.timeOut().has_value());

    const timelogger::Timestamp start{1000s};
    const timelogger::Timestamp replacementStart{1500s};
    const timelogger::Timestamp end{2000s};

    log.startWork(start);
    assert(log.timeIn() == start);
    assert(!log.timeOut().has_value());

    // Match the original app: pressing START again replaces the displayed time.
    log.startWork(replacementStart);
    assert(log.timeIn() == replacementStart);

    log.endWork(end);
    assert(log.timeOut() == end);

    return 0;
}
