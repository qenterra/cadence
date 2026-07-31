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

xcodegen generate --spec project.yml
swiftformat Sources Tests --lint
swiftlint lint \
    --config .swiftlint.yml \
    --cache-path "$project_root/.build/swiftlint-cache"

if [[ "${CADENCE_SKIP_XCODEBUILD:-0}" == "1" ]]; then
    echo "Skipping xcodebuild because CADENCE_SKIP_XCODEBUILD=1."
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

app_bundle="$project_root/.build/DerivedData/Build/Products/Debug/Cadence.app"
info_plist="$app_bundle/Contents/Info.plist"
icon_file="$app_bundle/Contents/Resources/Cadence.icns"
asset_catalog="$app_bundle/Contents/Resources/Assets.car"

[[ -f "$info_plist" ]]
[[ -f "$icon_file" ]]
[[ -f "$asset_catalog" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$info_plist")" == "Cadence" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$info_plist")" == "Cadence" ]]

asset_catalog_info="$(DEVELOPER_DIR="$developer_dir" xcrun assetutil --info "$asset_catalog")"
[[ "$asset_catalog_info" == *'"Appearance" : "NSAppearanceNameAqua"'* ]]
[[ "$asset_catalog_info" == *'"Appearance" : "NSAppearanceNameDarkAqua"'* ]]
[[ "$asset_catalog_info" == *'"Name" : "Cadence_Assets\/system-light"'* ]]
[[ "$asset_catalog_info" == *'"Name" : "Cadence_Assets\/system-dark"'* ]]
