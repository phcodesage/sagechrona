#include "GitTracker.hpp"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <iterator>
#include <spawn.h>
#include <string_view>
#include <sys/wait.h>
#include <unistd.h>
#include <utility>

extern char** environ;

namespace timelogger {
namespace {

struct CommandResult final {
    int exitCode{-1};
    std::string output;
};

std::string trim(std::string value) {
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return {};
    }
    const auto last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

CommandResult runGit(std::vector<std::string> arguments) {
    int outputPipe[2];
    if (pipe(outputPipe) != 0) {
        return {-1, std::string("Could not create a Git output pipe: ") + std::strerror(errno)};
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outputPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outputPipe[1]);

    std::vector<std::string> storage;
    storage.reserve(arguments.size() + 1);
    storage.emplace_back("/usr/bin/git");
    for (auto& argument : arguments) {
        storage.push_back(std::move(argument));
    }

    std::vector<char*> argv;
    argv.reserve(storage.size() + 1);
    for (auto& argument : storage) {
        argv.push_back(argument.data());
    }
    argv.push_back(nullptr);

    pid_t process = 0;
    const int spawnResult = posix_spawn(&process, argv.front(), &actions, nullptr,
                                        argv.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    close(outputPipe[1]);

    if (spawnResult != 0) {
        close(outputPipe[0]);
        return {-1, std::string("Could not start Git: ") + std::strerror(spawnResult)};
    }

    std::string output;
    char buffer[4096];
    ssize_t count = 0;
    while ((count = read(outputPipe[0], buffer, sizeof(buffer))) > 0) {
        output.append(buffer, static_cast<std::size_t>(count));
    }
    close(outputPipe[0]);

    int status = 0;
    while (waitpid(process, &status, 0) == -1 && errno == EINTR) {
    }

    const int exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    return {exitCode, std::move(output)};
}

std::vector<std::string> lines(const std::string& value) {
    std::vector<std::string> result;
    std::size_t start = 0;
    while (start < value.size()) {
        const auto end = value.find('\n', start);
        auto line = trim(value.substr(start, end - start));
        if (!line.empty()) {
            result.push_back(std::move(line));
        }
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return result;
}

std::string gitError(const CommandResult& result, const std::string& fallback) {
    const auto detail = trim(result.output);
    return detail.empty() ? fallback : detail;
}

} // namespace

std::string GitTracker::validateDirectory(const std::string& directory) {
    if (directory.empty()) {
        return "Select a Git directory first.";
    }

    const auto result = runGit({"-C", directory, "rev-parse", "--is-inside-work-tree"});
    if (result.exitCode != 0 || trim(result.output) != "true") {
        return gitError(result, "The selected directory is not inside a Git repository.");
    }
    return {};
}

GitResult GitTracker::commitsBetween(const std::string& directory,
                                     const Timestamp start,
                                     const Timestamp end) {
    if (const auto validationError = validateDirectory(directory); !validationError.empty()) {
        return {{}, validationError};
    }
    if (end < start) {
        return {{}, "The work session ends before it starts."};
    }

    const auto startSeconds = std::chrono::duration_cast<std::chrono::seconds>(
        start.time_since_epoch()).count();
    const auto endSeconds = std::chrono::duration_cast<std::chrono::seconds>(
        end.time_since_epoch()).count();

    const auto logResult = runGit({
        "-C", directory,
        "log", "--reverse", "--no-merges",
        "--since=@" + std::to_string(startSeconds),
        "--until=@" + std::to_string(endSeconds),
        "--format=%H%x1f%ct%x1f%s%x1e",
        "--", "."
    });
    if (logResult.exitCode != 0) {
        return {{}, gitError(logResult, "Git could not read the commit history.")};
    }

    std::vector<GitCommit> commits;
    std::size_t recordStart = 0;
    while (recordStart < logResult.output.size()) {
        const auto recordEnd = logResult.output.find('\x1e', recordStart);
        auto record = trim(logResult.output.substr(recordStart, recordEnd - recordStart));
        if (!record.empty()) {
            const auto first = record.find('\x1f');
            const auto second = first == std::string::npos
                ? std::string::npos
                : record.find('\x1f', first + 1);
            if (first == std::string::npos || second == std::string::npos) {
                return {{}, "Git returned an unexpected log format."};
            }

            GitCommit commit;
            commit.hash = record.substr(0, first);
            commit.sourceDirectory = directory;
            try {
                const auto seconds = std::stoll(record.substr(first + 1, second - first - 1));
                commit.committedAt = Timestamp{std::chrono::seconds{seconds}};
            } catch (...) {
                return {{}, "Git returned an invalid commit timestamp."};
            }
            commit.subject = trim(record.substr(second + 1));

            const auto pathsResult = runGit({
                "-C", directory,
                "diff-tree", "--no-commit-id", "--name-only", "-r", "--root",
                commit.hash, "--", "."
            });
            if (pathsResult.exitCode == 0) {
                commit.changedPaths = lines(pathsResult.output);
            }
            commits.push_back(std::move(commit));
        }

        if (recordEnd == std::string::npos) {
            break;
        }
        recordStart = recordEnd + 1;
    }

    return {std::move(commits), {}};
}

GitResult GitTracker::commitsBetween(const std::vector<std::string>& directories,
                                     const Timestamp start,
                                     const Timestamp end) {
    if (directories.empty()) {
        return {{}, "Select at least one Git directory first."};
    }

    std::vector<GitCommit> commits;
    for (const auto& directory : directories) {
        auto result = commitsBetween(directory, start, end);
        if (!result.succeeded()) {
            return {{}, directory + ": " + result.error};
        }
        commits.insert(commits.end(),
                       std::make_move_iterator(result.commits.begin()),
                       std::make_move_iterator(result.commits.end()));
    }
    std::stable_sort(commits.begin(), commits.end(), [](const GitCommit& left,
                                                         const GitCommit& right) {
        return left.committedAt < right.committedAt;
    });
    return {std::move(commits), {}};
}

} // namespace timelogger
