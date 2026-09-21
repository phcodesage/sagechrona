# Time Logger Native

A lightweight native macOS recreation of the original Python/Tkinter Time Logger.
The app uses a C++20 domain core and a thin Objective-C++ AppKit interface, so it
starts quickly and has no third-party runtime dependencies.

## Install

Download `TimeLogger-1.8.0-macOS-arm64.dmg` from the GitHub release, open it,
and drag **Time Logger** into the **Applications** folder.

The current release is built for Apple silicon. Because it uses a local ad hoc
signature rather than an Apple Developer ID, macOS may require the first launch
to be approved in **System Settings → Privacy & Security**.

## Current behavior

- `START WORK` records the current time in the `America/Puerto_Rico` time zone.
- `STARTED EARLIER…` opens a Puerto Rico date-and-time picker when work began
  before the app was opened.
- `END WORK` records the current time in the same format.
- Each recorded value is displayed as `yyyy-MM-dd HH:mm:ss` and copied to the
  macOS clipboard automatically.
- Repeated clicks replace the corresponding value, matching version 1.6 of the
  original app.
- A remembered directory picker scopes Git tracking to a repository or one of
  its subdirectories.
- `COPY REPORT` collects non-merge commits made during the session, numbers
  them, normalizes conventional commit types such as `fix` and `feat`, and
  infers `web`, `mobile`, or `web+mobile` from changed paths.
- Sessions longer than 8.2 hours are split into consecutive 8-hour-12-minute
  reports with numbering restarted in each report.

## Build and test

Requires macOS 13 or newer, Xcode Command Line Tools, and CMake 3.24 or newer.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure
cmake --install build --prefix dist
open dist/TimeLogger.app
```

The build applies a local ad hoc signature to the app bundle. Distribution to
other Macs will require an Apple Developer ID signature and notarization.

The main pieces are deliberately separated:

- `Sources/TimeLog.*` contains UI-independent session state.
- `Sources/GitTracker.*` reads scoped commit history without invoking a shell.
- `Sources/ReportFormatter.*` formats and splits clipboard reports.
- `Sources/main.mm` contains the native AppKit window and platform adapters.
- `Tests/TimeLogTests.cpp` verifies the core behavior.

Future features such as multiple sessions, project names, local persistence,
totals, exports, and reports can be added to the C++ layer without rebuilding
the UI architecture.

## Create the installer

```sh
./packaging/build_installer.sh
```

This performs a clean release build, runs the test suite, verifies the app
signature, and writes the disk image to `release/`.
