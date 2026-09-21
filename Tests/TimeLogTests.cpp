#include "GitTracker.hpp"
#include "ReportFormatter.hpp"
#include "TimeLog.hpp"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <unistd.h>

namespace {

std::string shellQuote(const std::string& value) {
    std::string result = "'";
    for (const char character : value) {
        if (character == '\'') {
            result += "'\\''";
        } else {
            result += character;
        }
    }
    result += '\'';
    return result;
}

void requireCommand(const std::string& command) {
    assert(std::system(command.c_str()) == 0);
}

} // namespace

int main() {
    using namespace std::chrono_literals;

    timelogger::TimeLog log;
    assert(!log.timeIn().has_value());
    assert(!log.timeOut().has_value());

    const timelogger::Timestamp start{1000s};
    const timelogger::Timestamp replacementStart{1500s};
    const timelogger::Timestamp end{2000s};

    log.startWork(start, "/example/repository");
    assert(log.timeIn() == start);
    assert(!log.timeOut().has_value());
    assert(log.targetDirectory() == "/example/repository");

    // Match the original app: pressing START again replaces the displayed time.
    log.startWork(replacementStart, "/example/other");
    assert(log.timeIn() == replacementStart);
    assert(log.targetDirectory() == "/example/other");

    log.endWork(end);
    assert(log.timeOut() == end);
    assert(log.isComplete());

    const timelogger::GitCommit webFix{
        "abc", replacementStart + 1s,
        "fix(web): queued messages are delivered in order",
        {"static/chat.js"}
    };
    assert(timelogger::formatCommit(webFix) ==
           "fixed: queued messages are delivered in order (web)");

    const timelogger::GitCommit mobileFeature{
        "def", replacementStart + 2s,
        "feat: add background notifications",
        {"mobile/lib/notifications.dart"}
    };
    assert(timelogger::formatCommit(mobileFeature) ==
           "added: add background notifications (mobile)");

    const timelogger::GitCommit sharedFix{
        "ghi", replacementStart + 3s,
        "fixed: keep unread totals consistent",
        {"static/inbox.js", "android/Inbox.kt"}
    };
    assert(timelogger::formatCommit(sharedFix) ==
           "fixed: keep unread totals consistent (web+mobile)");

    const auto longEnd = replacementStart + timelogger::kMaximumReportDuration + 1s;
    const timelogger::GitCommit boundaryCommit{
        "jkl", replacementStart + timelogger::kMaximumReportDuration,
        "chore: begin the next report", {}
    };
    const auto sections = timelogger::splitReport(
        {webFix, boundaryCommit}, replacementStart, longEnd);
    assert(sections.size() == 2);
    assert(sections[0].commits.size() == 1);
    assert(sections[1].commits.size() == 1);

    const auto shortReport = timelogger::formatReport(
        {webFix, mobileFeature}, replacementStart, end);
    assert(shortReport ==
           "1.fixed: queued messages are delivered in order (web)\n"
           "2.added: add background notifications (mobile)");

    const auto splitReport = timelogger::formatReport(
        {webFix, boundaryCommit}, replacementStart, longEnd);
    assert(splitReport.find("Report 1/2\n") == 0);
    assert(splitReport.find("\n\nReport 2/2\n") != std::string::npos);

    const auto repository = std::filesystem::temp_directory_path() /
        ("timelogger-git-test-" + std::to_string(getpid()));
    const auto webDirectory = repository / "web";
    std::filesystem::create_directories(webDirectory);

    const auto quotedRepository = shellQuote(repository.string());
    requireCommand("/usr/bin/git init -q " + quotedRepository);
    requireCommand("/usr/bin/git -C " + quotedRepository +
                   " config user.name 'Time Logger Test'");
    requireCommand("/usr/bin/git -C " + quotedRepository +
                   " config user.email 'timelogger@example.invalid'");

    {
        std::ofstream file(webDirectory / "queue.js");
        file << "export const queued = true;\n";
    }
    requireCommand("/usr/bin/git -C " + quotedRepository + " add web/queue.js");

    const auto trackingStart = std::chrono::system_clock::now() - 60s;
    requireCommand("/usr/bin/git -C " + quotedRepository +
                   " commit -q -m 'fix(web): send queued messages in order'");
    const auto trackingEnd = std::chrono::system_clock::now() + 60s;

    assert(timelogger::GitTracker::validateDirectory(webDirectory.string()).empty());
    const auto gitResult = timelogger::GitTracker::commitsBetween(
        webDirectory.string(), trackingStart, trackingEnd);
    assert(gitResult.succeeded());
    assert(gitResult.commits.size() == 1);
    assert(gitResult.commits.front().subject ==
           "fix(web): send queued messages in order");
    assert(timelogger::formatCommit(gitResult.commits.front()) ==
           "fixed: send queued messages in order (web)");

    std::filesystem::remove_all(repository);

    return 0;
}
