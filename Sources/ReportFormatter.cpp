#include "ReportFormatter.hpp"

#include <algorithm>
#include <cctype>
#include <sstream>
#include <string_view>

namespace timelogger {
namespace {

std::string trim(std::string value) {
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return {};
    }
    const auto last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

std::string lowercase(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](const unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

bool containsComponent(const std::string& path, const std::string_view component) {
    std::size_t start = 0;
    while (start <= path.size()) {
        const auto end = path.find('/', start);
        if (path.substr(start, end - start) == component) {
            return true;
        }
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return false;
}

bool hasExtension(const std::string& path, const std::vector<std::string_view>& extensions) {
    const auto dot = path.find_last_of('.');
    if (dot == std::string::npos) {
        return false;
    }
    const auto extension = std::string_view(path).substr(dot);
    return std::find(extensions.begin(), extensions.end(), extension) != extensions.end();
}

std::string inferScope(const std::vector<std::string>& paths) {
    bool web = false;
    bool mobile = false;
    for (const auto& originalPath : paths) {
        const auto path = lowercase(originalPath);
        web = web || containsComponent(path, "web") ||
              containsComponent(path, "frontend") || containsComponent(path, "templates") ||
              containsComponent(path, "static") ||
              hasExtension(path, {".html", ".css", ".js", ".jsx", ".ts", ".tsx"});
        mobile = mobile || containsComponent(path, "mobile") ||
                 containsComponent(path, "android") || containsComponent(path, "ios") ||
                 containsComponent(path, "flutter") ||
                 hasExtension(path, {".kt", ".dart"});
    }
    if (web && mobile) {
        return "web+mobile";
    }
    if (web) {
        return "web";
    }
    if (mobile) {
        return "mobile";
    }
    return {};
}

std::string mappedType(const std::string& type) {
    if (type == "fix" || type == "bugfix" || type == "fixed") {
        return "fixed";
    }
    if (type == "feat" || type == "feature" || type == "add" || type == "added") {
        return "added";
    }
    if (type == "remove" || type == "removed" || type == "delete") {
        return "removed";
    }
    return type;
}

bool alreadyHasScope(const std::string& subject) {
    if (subject.empty() || subject.back() != ')') {
        return false;
    }
    const auto open = subject.find_last_of('(');
    return open != std::string::npos && open + 1 < subject.size() - 1;
}

} // namespace

std::vector<ReportSection> splitReport(const std::vector<GitCommit>& commits,
                                       const Timestamp start,
                                       const Timestamp end) {
    if (end < start) {
        return {};
    }

    std::vector<ReportSection> sections;
    auto sectionStart = start;
    do {
        const auto sectionEnd = std::min(sectionStart + kMaximumReportDuration, end);
        sections.push_back({sectionStart, sectionEnd, {}});
        if (sectionEnd == end) {
            break;
        }
        sectionStart = sectionEnd;
    } while (sectionStart < end);

    for (const auto& commit : commits) {
        if (commit.committedAt < start || commit.committedAt > end) {
            continue;
        }
        auto index = static_cast<std::size_t>(
            (commit.committedAt - start) / kMaximumReportDuration);
        if (index >= sections.size()) {
            index = sections.size() - 1;
        }
        sections[index].commits.push_back(commit);
    }
    return sections;
}

std::string formatCommit(const GitCommit& commit) {
    auto subject = trim(commit.subject);
    std::string explicitScope;

    const auto colon = subject.find(':');
    if (colon != std::string::npos) {
        auto prefix = lowercase(trim(subject.substr(0, colon)));
        const auto open = prefix.find('(');
        if (open != std::string::npos && prefix.back() == ')') {
            explicitScope = trim(prefix.substr(open + 1, prefix.size() - open - 2));
            prefix = trim(prefix.substr(0, open));
        }
        const auto mapped = mappedType(prefix);
        if (mapped != prefix || prefix == "fixed" || prefix == "added" || prefix == "removed") {
            subject = mapped + ": " + trim(subject.substr(colon + 1));
        }
    }

    const auto scope = explicitScope.empty() ? inferScope(commit.changedPaths) : explicitScope;
    if (!scope.empty() && !alreadyHasScope(subject)) {
        subject += " (" + scope + ")";
    }
    return subject;
}

std::string formatReport(const std::vector<GitCommit>& commits,
                         const Timestamp start,
                         const Timestamp end) {
    const auto sections = splitReport(commits, start, end);
    if (sections.empty()) {
        return {};
    }

    std::ostringstream report;
    for (std::size_t sectionIndex = 0; sectionIndex < sections.size(); ++sectionIndex) {
        if (sectionIndex > 0) {
            report << "\n\n";
        }
        if (sections.size() > 1) {
            report << "Report " << (sectionIndex + 1) << '/' << sections.size() << '\n';
        }

        const auto& section = sections[sectionIndex];
        if (section.commits.empty()) {
            report << "No Git commits were recorded in this period.";
            continue;
        }
        for (std::size_t commitIndex = 0; commitIndex < section.commits.size(); ++commitIndex) {
            if (commitIndex > 0) {
                report << '\n';
            }
            report << (commitIndex + 1) << '.' << formatCommit(section.commits[commitIndex]);
        }
    }
    return report.str();
}

} // namespace timelogger
