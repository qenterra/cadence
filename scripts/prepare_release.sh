#!/usr/bin/env bash

set -euo pipefail

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [release-notes.md]" >&2
    exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
release_notes_path="${1:-$project_root/release/release-notes-0.2.0-beta.1.md}"
release_mode="${CADENCE_RELEASE_MODE:-}"

if [[ "$release_mode" != "local" && "$release_mode" != "public" ]]; then
    echo "Set CADENCE_RELEASE_MODE to local or public." >&2
    exit 64
fi

if [[ ! -f "$release_notes_path" ]]; then
    echo "Release notes were not found: $release_notes_path" >&2
    exit 66
fi

python3 "$project_root/scripts/release_contract.py" check
if [[ "$release_mode" == "public" ]]; then
    python3 "$project_root/scripts/release_contract.py" public-preflight
fi
eval "$(python3 "$project_root/scripts/release_contract.py" env)"

derived_data="$project_root/.build/ReleaseDerivedData"
archive_path="$project_root/.build/Release/$release_mode/Cadence.xcarchive"
output_dir="$project_root/.build/releases/$release_mode/$PUBLIC_VERSION"
zip_file="$output_dir/$ZIP_NAME"
dmg_file="$output_dir/$DMG_NAME"
checksums_file="$output_dir/$CHECKSUMS_NAME"
sparkle_tools="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin"
staging_dir="$(mktemp -d /private/tmp/cadence-release.XXXXXX)"
appcast_staging="$staging_dir/appcast"

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

if [[ "${CADENCE_REUSE_ARCHIVE:-0}" != "1" ]]; then
    DEVELOPER_DIR="$developer_dir" xcodebuild \
        -resolvePackageDependencies \
        -project Cadence.xcodeproj \
        -scheme Cadence \
        -derivedDataPath "$derived_data"

    signing_arguments=(
        CODE_SIGNING_REQUIRED=YES
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
    )
    if [[ "$release_mode" == "public" ]]; then
        signing_arguments+=(
            CODE_SIGN_STYLE=Manual
            "CODE_SIGN_IDENTITY=$CADENCE_DEVELOPER_ID_APPLICATION"
            "DEVELOPMENT_TEAM=$CADENCE_DEVELOPMENT_TEAM"
            ENABLE_HARDENED_RUNTIME=YES
        )
    else
        signing_arguments+=(CODE_SIGN_IDENTITY=-)
    fi

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
        "${signing_arguments[@]}"
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
if [[ "$release_mode" == "public" ]]; then
    signature_details="$(codesign --display --verbose=4 "$app_bundle" 2>&1)"
    if [[ "$signature_details" == *"Signature=adhoc"* ]]; then
        echo "Public archive is still ad-hoc signed." >&2
        exit 70
    fi
    if [[ "$signature_details" != *"TeamIdentifier=$CADENCE_DEVELOPMENT_TEAM"* ]]; then
        echo "Public archive TeamIdentifier does not match CADENCE_DEVELOPMENT_TEAM." >&2
        exit 70
    fi
fi

mkdir -p "$output_dir" "$appcast_staging"
if [[ "$release_mode" == "local" ]]; then
    "$project_root/scripts/create_dmg.sh" "$app_bundle" "$dmg_file" "$HUMAN_RELEASE_NAME"
    echo "Prepared local validation artifact: $dmg_file"
    echo "This artifact is ad-hoc signed and must not be published."
    exit 0
fi

# The public path is deliberately fail-closed: the app and disk image both
# need an accepted notarization submission and a locally validated ticket.
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$zip_file"
DEVELOPER_DIR="$developer_dir" xcrun notarytool submit \
    "$zip_file" \
    --keychain-profile "$CADENCE_NOTARY_KEYCHAIN_PROFILE" \
    --wait
DEVELOPER_DIR="$developer_dir" xcrun stapler staple "$app_bundle"
DEVELOPER_DIR="$developer_dir" xcrun stapler validate "$app_bundle"
spctl --assess --type execute --verbose=4 "$app_bundle"

# Recreate the update archive after stapling the app so offline Gatekeeper
# verification does not depend on network ticket lookup.
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$zip_file"
"$project_root/scripts/create_dmg.sh" "$app_bundle" "$dmg_file" "$HUMAN_RELEASE_NAME"
DEVELOPER_DIR="$developer_dir" xcrun notarytool submit \
    "$dmg_file" \
    --keychain-profile "$CADENCE_NOTARY_KEYCHAIN_PROFILE" \
    --wait
DEVELOPER_DIR="$developer_dir" xcrun stapler staple "$dmg_file"
DEVELOPER_DIR="$developer_dir" xcrun stapler validate "$dmg_file"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_file"

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

(
    cd "$output_dir"
    shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > "$CHECKSUMS_NAME"
)

codesign --verify --deep --strict --verbose=2 "$app_bundle"
unzip -t "$zip_file"

echo "Prepared $HUMAN_RELEASE_NAME."
echo "Git tag: $TAG"
echo "GitHub prerelease assets:"
echo "  $dmg_file"
echo "  $zip_file"
echo "  $checksums_file"
echo "Commit and publish appcast.xml before announcing the release."
