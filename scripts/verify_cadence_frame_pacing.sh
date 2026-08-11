#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
marker="$project_root/.build/run-cadence-frame-pacing"
derived_data="$project_root/.build/DerivedData-FramePacing"

developer_dir="${DEVELOPER_DIR:-/Applications/Developing & Coding/Xcode.app/Contents/Developer}"
if [[ ! -d "$developer_dir" ]]; then
    echo "Full Xcode was not found. Set DEVELOPER_DIR." >&2
    exit 1
fi

mkdir -p "$project_root/.build"
touch "$marker"
trap 'rm -f "$marker"' EXIT

cd "$project_root"
xcodegen generate --spec project.yml

DEVELOPER_DIR="$developer_dir" xcodebuild \
    -project Cadence.xcodeproj \
    -scheme Cadence \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    -destination 'platform=macOS,arch=arm64' \
    -jobs 2 \
    -parallel-testing-enabled NO \
    ENABLE_TESTABILITY=YES \
    ONLY_ACTIVE_ARCH=YES \
    ARCHS=arm64 \
    -only-testing:CadenceTests/CadenceModeFramePacingTests \
    test | xcbeautify
