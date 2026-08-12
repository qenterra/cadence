#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "Usage: $0 <version> <build> <stable|beta> [release-notes.md]" >&2
    exit 64
fi

version="$1"
build_number="$2"
channel="$3"
release_notes_path="${4:-}"

if [[ "$channel" != "stable" && "$channel" != "beta" ]]; then
    echo "Channel must be either stable or beta." >&2
    exit 64
fi

if [[ -n "$release_notes_path" && ! -f "$release_notes_path" ]]; then
    echo "Release notes were not found: $release_notes_path" >&2
    exit 66
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
derived_data="$project_root/.build/ReleaseDerivedData"
archive_path="$project_root/.build/Release/Cadence.xcarchive"
output_dir="$project_root/.build/releases/$version"
archive_name="Cadence-$version.zip"
archive_file="$output_dir/$archive_name"
sparkle_tools="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin"
staging_dir="$(mktemp -d)"

cleanup() {
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
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

app_bundle="$archive_path/Products/Applications/Cadence.app"
if [[ ! -d "$app_bundle" ]]; then
    echo "Cadence.app was not produced by the archive." >&2
    exit 70
fi

mkdir -p "$output_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive_file"

cp "$project_root/appcast.xml" "$staging_dir/appcast.xml"
cp "$archive_file" "$staging_dir/$archive_name"
if [[ -n "$release_notes_path" ]]; then
    cp "$release_notes_path" "$staging_dir/Cadence-$version.md"
fi

generate_arguments=(
    --account com.qenterra.cadence
    --download-url-prefix "https://github.com/QenTerra/cadence/releases/download/v$version/"
    --link "https://github.com/QenTerra/cadence/releases/tag/v$version"
    --maximum-versions 0
)
if [[ "$channel" == "beta" ]]; then
    generate_arguments+=(--channel beta)
fi

"$sparkle_tools/generate_appcast" \
    "${generate_arguments[@]}" \
    "$staging_dir"

cp "$staging_dir/appcast.xml" "$project_root/appcast.xml"
cp "$staging_dir/$archive_name" "$archive_file"

echo "Prepared $channel release $version ($build_number)."
echo "Upload this asset to GitHub release v$version:"
echo "  $archive_file"
echo "Commit and publish the updated appcast.xml before announcing the release."
