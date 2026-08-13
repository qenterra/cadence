#!/usr/bin/env bash

set -euo pipefail

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [release-notes.md]" >&2
    exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
release_notes_path="${1:-$project_root/release/release-notes-0.2.0-beta.1.md}"

if [[ ! -f "$release_notes_path" ]]; then
    echo "Release notes were not found: $release_notes_path" >&2
    exit 66
fi

qds_release_auditor="${QDS_RELEASE_AUDITOR:-$project_root/../design-system/scripts/audit_release_contract.py}"
if [[ ! -f "$qds_release_auditor" ]]; then
    echo "QDS release auditor was not found. Set QDS_RELEASE_AUDITOR." >&2
    exit 69
fi

python3 "$qds_release_auditor" "$project_root"
python3 "$project_root/scripts/release_contract.py" check
eval "$(python3 "$project_root/scripts/release_contract.py" env)"

derived_data="$project_root/.build/ReleaseDerivedData"
archive_path="$project_root/.build/Release/Cadence.xcarchive"
output_dir="$project_root/.build/releases/$PUBLIC_VERSION"
zip_file="$output_dir/$ZIP_NAME"
dmg_file="$output_dir/$DMG_NAME"
checksums_file="$output_dir/$CHECKSUMS_NAME"
sparkle_tools="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin"
staging_dir="$(mktemp -d /private/tmp/cadence-release.XXXXXX)"
dmg_source="$staging_dir/dmg-source"
mount_point="$staging_dir/mount"
read_write_dmg="$staging_dir/Cadence-read-write.dmg"
appcast_staging="$staging_dir/appcast"
mounted=0

cleanup() {
    if [[ "$mounted" == "1" ]]; then
        hdiutil detach "$mount_point" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$staging_dir"
}
trap cleanup EXIT

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    developer_dir="$DEVELOPER_DIR"
else
    developer_dir="/Applications/Developing & Coding/Xcode.app/Contents/Developer"
fi

if [[ ! -d "$developer_dir" ]]; then
    echo "Set DEVELOPER_DIR to a full Xcode installation." >&2
    exit 69
fi

cd "$project_root"
xcodegen generate --spec project.yml

if [[ "${CADENCE_REUSE_ARCHIVE:-0}" != "1" ]]; then
    DEVELOPER_DIR="$developer_dir" xcodebuild \
        -resolvePackageDependencies \
        -project Cadence.xcodeproj \
        -scheme Cadence \
        -derivedDataPath "$derived_data"

    DEVELOPER_DIR="$developer_dir" xcodebuild archive \
        -project Cadence.xcodeproj \
        -scheme Cadence \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$derived_data" \
        -archivePath "$archive_path" \
        MARKETING_VERSION="$MARKETING_VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        ARCHS="$ARCHITECTURE" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY=- \
        CODE_SIGNING_REQUIRED=YES \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
else
    echo "Reusing the existing archive after validating its release surfaces."
fi

app_bundle="$archive_path/Products/Applications/Cadence.app"
info_plist="$app_bundle/Contents/Info.plist"
if [[ ! -d "$app_bundle" || ! -f "$info_plist" ]]; then
    echo "Cadence.app was not produced by the archive." >&2
    exit 70
fi

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")" == "$MARKETING_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")" == "$BUILD_NUMBER" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")" == "$BUNDLE_IDENTIFIER" ]]
[[ "$(lipo -archs "$app_bundle/Contents/MacOS/Cadence")" == "$ARCHITECTURE" ]]
codesign --verify --deep --strict --verbose=2 "$app_bundle"

mkdir -p "$output_dir" "$appcast_staging" "$dmg_source/.background" "$mount_point"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$zip_file"
cp "$project_root/appcast.xml" "$appcast_staging/appcast.xml"
cp "$zip_file" "$appcast_staging/$ZIP_NAME"
cp "$release_notes_path" "$appcast_staging/Cadence-$PUBLIC_VERSION.md"

generate_arguments=(
    --account com.qenterra.cadence
    --download-url-prefix "https://github.com/QenTerra/cadence/releases/download/$TAG/"
    --link "https://github.com/QenTerra/cadence/releases/tag/$TAG"
    --maximum-versions 0
)
if [[ "$CHANNEL" != "stable" ]]; then
    generate_arguments+=(--channel "$CHANNEL")
fi

"$sparkle_tools/generate_appcast" \
    "${generate_arguments[@]}" \
    "$appcast_staging"

cp "$appcast_staging/appcast.xml" "$project_root/appcast.xml"
cp "$appcast_staging/$ZIP_NAME" "$zip_file"

ditto "$app_bundle" "$dmg_source/Cadence.app"
cp "$project_root/release/dmg-background.png" "$dmg_source/.background/dmg-background.png"
ln -s /Applications "$dmg_source/Applications"

hdiutil create \
    -volname "$HUMAN_RELEASE_NAME" \
    -srcfolder "$dmg_source" \
    -ov \
    -format UDRW \
    "$read_write_dmg"

hdiutil attach \
    "$read_write_dmg" \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$mount_point"
mounted=1
osascript "$project_root/release/layout.applescript" "$HUMAN_RELEASE_NAME"
sync
hdiutil detach "$mount_point"
mounted=0

hdiutil convert "$read_write_dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg_file"

(
    cd "$output_dir"
    shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > "$CHECKSUMS_NAME"
)

codesign --verify --deep --strict --verbose=2 "$app_bundle"
hdiutil verify "$dmg_file"
unzip -t "$zip_file"

echo "Prepared $HUMAN_RELEASE_NAME."
echo "Git tag: $TAG"
echo "GitHub prerelease assets:"
echo "  $dmg_file"
echo "  $zip_file"
echo "  $checksums_file"
echo "Commit and publish appcast.xml before announcing the release."
