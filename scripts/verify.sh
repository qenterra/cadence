#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
release_contract=(python3 -I -B "$project_root/scripts/release_contract.py")
release_attestation_mode=0
requested_developer_dir="${DEVELOPER_DIR:-}"

# DEVELOPER_DIR changes more than Xcode commands on macOS: Python and plutil
# can delegate through xcrun. Preserve the caller's requested path as data and
# pass it only to the validated Xcode invocations below.
unset DEVELOPER_DIR

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--release-attestation" ) ]]; then
    echo "Usage: $0 [--release-attestation]" >&2
    exit 64
fi
if [[ $# -eq 1 ]]; then
    release_attestation_mode=1
    gate_environment="$(
        "${release_contract[@]}" \
            gate-begin \
            --gate-owner-pid "$$" \
            --root "$project_root"
    )"
    eval "$gate_environment"
    if [[ "${CADENCE_SKIP_XCODEBUILD:-0}" == "1" ]]; then
        echo "A release attestation requires the full local Xcode gate; CADENCE_SKIP_XCODEBUILD=1 is forbidden." >&2
        exit 64
    fi
fi

if [[ -n "$requested_developer_dir" ]]; then
    developer_dir="$requested_developer_dir"
else
    developer_dir=""
    for candidate in \
        "$(xcode-select -p 2>/dev/null || true)" \
        "/Applications/Xcode.app/Contents/Developer" \
        "/Applications/Developing & Coding/Xcode.app/Contents/Developer" \
        "/Applications/Coding/Xcode.app/Contents/Developer"; do
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

icon_source="$project_root/icon/Cadence.icon"
icon_manifest="$icon_source/icon.json"

[[ -d "$icon_source" ]]
[[ -f "$icon_manifest" ]]
[[ "$(plutil -extract 'supported-platforms.squares' raw -o - "$icon_manifest")" == "shared" ]]
[[ "$(plutil -extract 'supported-platforms.circles.0' raw -o - "$icon_manifest")" == "watchOS" ]]
[[ "$(plutil -extract 'groups.0.layers.0.fill-specializations.1.appearance' raw -o - "$icon_manifest")" == "light" ]]
[[ "$(plutil -extract 'groups.0.layers.0.fill-specializations.1.value' raw -o - "$icon_manifest")" == "system-dark" ]]

# XcodeGen only renders the project. Actual Xcode commands below use the
# validated developer_dir explicitly.
xcodegen generate --spec project.yml

"${release_contract[@]}" check
python3 -B -m unittest \
    Tests/ReleaseContractTests/test_release_contract.py \
    Tests/ReleaseContractTests/test_release_provenance.py \
    Tests/ReleaseContractTests/test_swiftlint_debt_gate.py \
    -v
image_python="${CADENCE_IMAGE_PYTHON:-$project_root/.build/python-tools/bin/python}"
if [[ ! -x "$image_python" ]]; then
    echo "Release image tools are unavailable. Run 'bash scripts/prepare_python_tools.sh' or set CADENCE_IMAGE_PYTHON." >&2
    exit 69
fi
if ! "$image_python" -c 'import PIL'; then
    echo "CADENCE_IMAGE_PYTHON cannot import Pillow. Run 'bash scripts/prepare_python_tools.sh' or set CADENCE_IMAGE_PYTHON." >&2
    exit 69
fi
"$image_python" -B -m unittest Tests/ReleaseContractTests/test_dmg_background.py -v

swiftformat Sources Tests --lint
mkdir -p "$project_root/.build"
swiftlint_report="$project_root/.build/swiftlint-report.json"
DEVELOPER_DIR="$developer_dir" swiftlint lint \
    --config .swiftlint.yml \
    --cache-path "$project_root/.build/swiftlint-cache" \
    --reporter json > "$swiftlint_report"
python3 -I -B "$project_root/scripts/swiftlint_debt_gate.py" \
    --baseline "$project_root/scripts/swiftlint-warning-baseline.json" \
    --report "$swiftlint_report"

if [[ "${CADENCE_SKIP_XCODEBUILD:-0}" == "1" ]]; then
    partial_result="PARTIAL HOSTED CHECKS PASSED. Xcode build/tests, localization, Periphery, and built-product checks were NOT RUN. This is not the full release gate; no release attestation was written."
    echo "$partial_result"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        echo "$partial_result" >> "$GITHUB_STEP_SUMMARY"
    fi
    exit 0
fi

DEVELOPER_DIR="$developer_dir" xcodebuild \
    -project Cadence.xcodeproj \
    -scheme Cadence \
    -configuration Debug \
    -derivedDataPath "$project_root/.build/DerivedData" \
    -destination 'platform=macOS' \
    -jobs 2 \
    -parallel-testing-enabled NO \
    test | xcbeautify

DEVELOPER_DIR="$developer_dir" \
    "$project_root/scripts/verify_localization.sh" \
    "$project_root/.build/DerivedData"

DEVELOPER_DIR="$developer_dir" \
    "$project_root/scripts/verify_periphery.sh"

app_bundle="$project_root/.build/DerivedData/Build/Products/Debug/Cadence.app"
info_plist="$app_bundle/Contents/Info.plist"
icon_file="$app_bundle/Contents/Resources/Cadence.icns"
asset_catalog="$app_bundle/Contents/Resources/Assets.car"

[[ -f "$info_plist" ]]
[[ -f "$icon_file" ]]
[[ -f "$asset_catalog" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$info_plist")" == "Cadence" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$info_plist")" == "Cadence" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:0:CFBundleTypeRole' "$info_plist")" == "Viewer" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:0:LSHandlerRank' "$info_plist")" == "Alternate" ]]
expected_audio_extensions=(aac aif aiff flac m4a mp3 wav)
for index in "${!expected_audio_extensions[@]}"; do
    actual_extension="$(
        /usr/libexec/PlistBuddy \
            -c "Print :CFBundleDocumentTypes:0:CFBundleTypeExtensions:$index" \
            "$info_plist"
    )"
    [[ "$actual_extension" == "${expected_audio_extensions[$index]}" ]]
done
if /usr/libexec/PlistBuddy \
    -c "Print :CFBundleDocumentTypes:0:CFBundleTypeExtensions:${#expected_audio_extensions[@]}" \
    "$info_plist" >/dev/null 2>&1; then
    echo "Unexpected extra registered audio extension."
    exit 1
fi

asset_catalog_info="$(DEVELOPER_DIR="$developer_dir" xcrun assetutil --info "$asset_catalog")"
[[ "$asset_catalog_info" == *'"Appearance" : "NSAppearanceNameAqua"'* ]]
[[ "$asset_catalog_info" == *'"Appearance" : "NSAppearanceNameDarkAqua"'* ]]
[[ "$asset_catalog_info" == *'"Name" : "Cadence_Assets\/system-light"'* ]]
[[ "$asset_catalog_info" == *'"Name" : "Cadence_Assets\/system-dark"'* ]]

if [[ "$release_attestation_mode" == "1" ]]; then
    "${release_contract[@]}" \
        gate-complete \
        --source-sha "$SOURCE_SHA" \
        --gate-session "$RELEASE_GATE_SESSION" \
        --gate-owner-pid "$$" \
        --gate-receipt xcode-tests \
        --gate-receipt localization \
        --gate-receipt periphery \
        --gate-receipt built-product \
        --gate-receipt asset-catalog \
        --root "$project_root"
    echo "Full release gate attestation written for $SOURCE_SHA."
fi
