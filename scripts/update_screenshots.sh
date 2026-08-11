#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    developer_dir="$DEVELOPER_DIR"
else
    developer_dir=""
    for candidate in \
        "$(xcode-select -p 2>/dev/null || true)" \
        "/Applications/Xcode.app/Contents/Developer" \
        "/Applications/Developing & Coding/Xcode.app/Contents/Developer"; do
        if [[ -d "$candidate" && "$candidate" != "/Library/Developer/CommandLineTools" ]]; then
            developer_dir="$candidate"
            break
        fi
    done
fi

if [[ -z "$developer_dir" || ! -d "$developer_dir" ]]; then
    echo "Full Xcode was not found. Set DEVELOPER_DIR to Xcode.app/Contents/Developer." >&2
    exit 1
fi

cd "$project_root"
xcodegen generate --spec project.yml

marker="$project_root/.build/update-screenshots"
cadence_mode_marker="$project_root/.build/update-cadence-mode-screenshots"
mkdir -p "$project_root/.build"
touch "$marker"
touch "$cadence_mode_marker"

cleanup_markers() {
    unlink "$marker" 2>/dev/null || true
    unlink "$cadence_mode_marker" 2>/dev/null || true
}

trap cleanup_markers EXIT

is_supported_minimum_height() {
    [[ "$1" == "1752" || "$1" == "1768" ]]
}

DEVELOPER_DIR="$developer_dir" xcodebuild \
    -project Cadence.xcodeproj \
    -scheme Cadence \
    -configuration Debug \
    -derivedDataPath "$project_root/.build/ScreenshotDerivedData" \
    -destination 'platform=macOS' \
    -only-testing:CadenceTests/DocumentationScreenshotTests \
    -only-testing:CadenceTests/CadenceModeScreenshotTests \
    -parallel-testing-enabled NO \
    CODE_SIGN_ENTITLEMENTS= \
    test | xcbeautify

for image in "$project_root"/docs/images/cadence-{library,now-playing,tags,settings}.png; do
    [[ -f "$image" ]]
    [[ "$(sips -g pixelWidth "$image" | tail -n 1 | awk '{print $2}')" == "2160" ]]
    is_supported_minimum_height "$(sips -g pixelHeight "$image" | tail -n 1 | awk '{print $2}')"
done

for image in "$project_root"/docs/images/qa-{library,now-playing,album,import-review}-min-*.png; do
    [[ -f "$image" ]]
    [[ "$(sips -g pixelWidth "$image" | tail -n 1 | awk '{print $2}')" == "2160" ]]
    is_supported_minimum_height "$(sips -g pixelHeight "$image" | tail -n 1 | awk '{print $2}')"
done

for image in "$project_root"/docs/images/qa-{library,now-playing,album,import-review}-wide-*.png; do
    [[ -f "$image" ]]
    [[ "$(sips -g pixelWidth "$image" | tail -n 1 | awk '{print $2}')" == "2880" ]]
    [[ "$(sips -g pixelHeight "$image" | tail -n 1 | awk '{print $2}')" == "1800" ]]
done

for image in "$project_root"/docs/images/qa-cadence-mode-*min-*.png; do
    [[ -f "$image" ]]
    [[ "$(sips -g pixelWidth "$image" | tail -n 1 | awk '{print $2}')" == "2160" ]]
    is_supported_minimum_height "$(sips -g pixelHeight "$image" | tail -n 1 | awk '{print $2}')"
done

for image in "$project_root"/docs/images/qa-cadence-mode-wide-*.png; do
    [[ -f "$image" ]]
    [[ "$(sips -g pixelWidth "$image" | tail -n 1 | awk '{print $2}')" == "2880" ]]
    [[ "$(sips -g pixelHeight "$image" | tail -n 1 | awk '{print $2}')" == "1800" ]]
done
