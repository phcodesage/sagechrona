# SageChrona

SageChrona is a lightweight native macOS timekeeper for developers and
freelancers. It records work sessions and turns the Git commits made during
each session into a numbered, copy-ready activity report.

Created by [PHCodeSage](https://github.com/phcodesage).

## Features

- Start a session now or select the time you actually began working.
- End the session and copy a chronological Git activity report.
- Track an entire repository or scope the report to one subdirectory.
- Choose from the full macOS IANA timezone database with autocomplete.
- Remember the selected repository and timezone between launches.
- Normalize conventional commits such as `fix(web): ...` into
  `fixed: ... (web)`.
- Infer `web`, `mobile`, and `web+mobile` scopes from changed paths.
- Split sessions longer than 8.2 hours into consecutive 8-hour-12-minute
  report blocks.
- Run as a small Apple silicon binary with no third-party runtime dependencies.

## Install

Download `SageChrona-2.0.0-macOS-arm64.dmg` from the latest GitHub release,
open it, and drag **SageChrona** into **Applications**.

The current build uses a local ad hoc signature rather than an Apple Developer
ID. macOS may require the first launch to be approved in
**System Settings → Privacy & Security**.

## How reports work

1. Choose a Git repository or a directory inside one.
2. Choose the timezone used for displayed and manually selected times.
3. Select **START NOW** or **STARTED EARLIER…**.
4. Work and commit normally.
5. Select **END WORK**, followed by **COPY GIT REPORT**.

Example:

```text
1.fixed: preserve queued message order (web)
2.added: background notification support (mobile)
3.fixed: keep unread totals consistent (web+mobile)
```

SageChrona reads non-merge commits reachable from the current branch whose
commit timestamps fall inside the session. Selecting a subdirectory adds a Git
path filter, so unrelated changes are excluded.

## Build and test

Requires macOS 13 or newer, Xcode Command Line Tools, and CMake 3.24 or newer.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure
cmake --install build --prefix dist
open dist/SageChrona.app
```

The core is separated by responsibility:

- `Sources/TimeLog.*` stores UI-independent session state.
- `Sources/GitTracker.*` reads scoped commit history without invoking a shell.
- `Sources/ReportFormatter.*` formats and splits clipboard reports.
- `Sources/main.mm` provides the native AppKit interface and macOS adapters.
- `Tests/TimeLogTests.cpp` covers state, formatting, splitting, and real Git
  integration.

## Create the installer

```sh
./packaging/build_installer.sh
```

This performs a release build, runs the test suite, verifies the app signature,
and writes the DMG to `release/`.

## Contributing

Issues and pull requests are welcome. Please use focused commits with clear
subjects; conventional commit scopes produce especially readable SageChrona
reports.
