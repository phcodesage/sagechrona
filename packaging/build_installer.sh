#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
DIST_DIR="${PROJECT_DIR}/dist"
RELEASE_DIR="${PROJECT_DIR}/release"
VERSION="2.1.0"
IMAGE_NAME="SageChrona-${VERSION}-macOS-arm64.dmg"
IMAGE_PATH="${RELEASE_DIR}/${IMAGE_NAME}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/timelogger-installer.XXXXXX")"

cleanup() {
    rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

cmake -S "${PROJECT_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=Release
cmake --build "${BUILD_DIR}" --parallel
ctest --test-dir "${BUILD_DIR}" --output-on-failure
cmake --install "${BUILD_DIR}" --prefix "${DIST_DIR}"
codesign --verify --deep --strict --verbose=2 "${DIST_DIR}/SageChrona.app"

mkdir -p "${RELEASE_DIR}"
ditto "${DIST_DIR}/SageChrona.app" "${STAGING_DIR}/SageChrona.app"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${IMAGE_PATH}"
hdiutil create \
    -volname "SageChrona" \
    -srcfolder "${STAGING_DIR}" \
    -format UDZO \
    -ov \
    "${IMAGE_PATH}"

hdiutil verify "${IMAGE_PATH}"
shasum -a 256 "${IMAGE_PATH}"
