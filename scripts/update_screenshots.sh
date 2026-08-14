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
candidate_dir="$HOME/Library/Containers/com.qenterra.cadence/Data/tmp/CadenceVisualRegression/update"
mkdir -p "$project_root/.build"
mkdir -p "$candidate_dir"
find "$candidate_dir" -maxdepth 1 -type f -name '*.png' -delete
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
    -only-testing:CadenceTests/CollapsedNavigationScreenshotTests \
    -only-testing:CadenceTests/CadenceModeScreenshotTests \
    -parallel-testing-enabled NO \
    CODE_SIGN_ENTITLEMENTS= \
    test | xcbeautify

# Documentation screenshot tests run inside the app sandbox. Promote the
# complete candidate set only after the test process has exited successfully.
candidate_count="$(find "$candidate_dir" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
if [[ "$candidate_count" != "78" ]]; then
    echo "Expected 78 documentation screenshot candidates, found $candidate_count." >&2
    exit 70
fi
cp -f "$candidate_dir"/*.png "$project_root/docs/images/"

for image in "$project_root"/docs/images/cadence-{library,now-playing,tags}.png; do
    [[ -f "$image" ]]
    [[ "$(sips -g pixelWidth "$image" | tail -n 1 | awk '{print $2}')" == "2160" ]]
    is_supported_minimum_height "$(sips -g pixelHeight "$image" | tail -n 1 | awk '{print $2}')"
done

for scene in home library album now-playing import-review; do
    for viewport in min ideal wide; do
        case "$viewport" in
            min) expected_width=2160 ;;
            ideal) expected_width=3024 ;;
            wide) expected_width=2880 ;;
        esac
        for appearance in system light dark; do
            image="$project_root/docs/images/qa-$scene-$viewport-$appearance.png"
            [[ -f "$image" ]]
            [[ "$(sips -g pixelWidth "$image" | tail -n 1 | awk '{print $2}')" == "$expected_width" ]]
        done
    done
done

for image in \
    "$project_root/docs/images/qa-library-collapsed-min-dark.png" \
    "$project_root/docs/images/qa-now-playing-collapsed-min-dark.png"; do
    [[ -f "$image" ]]
    [[ "$(sips -g pixelWidth "$image" | tail -n 1 | awk '{print $2}')" == "2160" ]]
    is_supported_minimum_height "$(sips -g pixelHeight "$image" | tail -n 1 | awk '{print $2}')"
done

for appearance in system light dark; do
    image="$project_root/docs/images/qa-empty-home-min-$appearance.png"
    [[ -f "$image" ]]
    [[ "$(sips -g pixelWidth "$image" | tail -n 1 | awk '{print $2}')" == "2160" ]]
done

long_copy_home_image="$project_root/docs/images/qa-home-min-long-copy-dark.png"
[[ -f "$long_copy_home_image" ]]
[[ "$(sips -g pixelWidth "$long_copy_home_image" | tail -n 1 | awk '{print $2}')" == "2160" ]]

settings_image="$project_root/docs/images/cadence-settings.png"
[[ -f "$settings_image" ]]
[[ "$(sips -g pixelWidth "$settings_image" | tail -n 1 | awk '{print $2}')" == "1520" ]]
for tab in general library sidebar remote shortcuts updates about; do
    for appearance in system light dark; do
        image="$project_root/docs/images/qa-settings-$tab-$appearance.png"
        [[ -f "$image" ]]
        [[ "$(sips -g pixelWidth "$image" | tail -n 1 | awk '{print $2}')" == "1520" ]]
    done
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

large_cadence_image="$project_root/docs/images/qa-cadence-mode-large-dark.png"
[[ -f "$large_cadence_image" ]]
[[ "$(sips -g pixelWidth "$large_cadence_image" | tail -n 1 | awk '{print $2}')" == "4400" ]]
[[ "$(sips -g pixelHeight "$large_cadence_image" | tail -n 1 | awk '{print $2}')" == "2664" ]]
