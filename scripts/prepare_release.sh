#!/usr/bin/env bash

set -euo pipefail

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [release-notes.md]" >&2
    exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
release_contract=(python3 -I -B "$project_root/scripts/release_contract.py")

if [[ "${CADENCE_RELEASE_SUPERVISOR_PID:-}" != "$PPID" ]]; then
    supervisor_arguments=(
        supervise-prepare
        --root "$project_root"
    )
    if [[ $# -eq 1 ]]; then
        supervisor_arguments+=(--release-notes "$1")
    fi
    exec "${release_contract[@]}" "${supervisor_arguments[@]}"
fi
supervisor_operation_token="${CADENCE_RELEASE_OPERATION_TOKEN:-}"
unset CADENCE_RELEASE_SUPERVISOR_PID
unset CADENCE_RELEASE_OPERATION_TOKEN
if [[ -z "$supervisor_operation_token" ]]; then
    echo "Release preparation supervisor did not provide an operation token." >&2
    exit 70
fi

release_mode="${CADENCE_RELEASE_MODE:-}"

if [[ "$release_mode" != "local" && "$release_mode" != "public" ]]; then
    echo "Set CADENCE_RELEASE_MODE to local or public." >&2
    exit 64
fi

"${release_contract[@]}" check
contract_environment="$("${release_contract[@]}" env)"
eval "$contract_environment"
release_notes_input="${1:-$project_root/release/release-notes-$PUBLIC_VERSION.md}"
preflight_environment="$(
    "${release_contract[@]}" \
        release-preflight \
        --release-mode "$release_mode" \
        --release-notes "$release_notes_input" \
        --root "$project_root"
)"
eval "$preflight_environment"
release_notes_path="$RELEASE_NOTES_PATH"
if [[ "$release_mode" == "public" ]]; then
    "${release_contract[@]}" public-preflight
fi

staging_dir=""
release_operation_active=0

check_release_operation() {
    "${release_contract[@]}" \
        release-operation-check \
        --release-mode "$release_mode" \
        --operation-token "$RELEASE_OPERATION_TOKEN" \
        --operation-owner-pid "$$" \
        --root "$project_root" >/dev/null
}

finish_release_operation() {
    release_operation_active=0
}

cleanup() {
    cleanup_status=$?
    trap - EXIT HUP INT TERM
    if [[ -n "$staging_dir" && "$staging_dir" == /private/tmp/cadence-release.* && -d "$staging_dir" ]]; then
        rm -rf -- "$staging_dir" || true
    fi
    if [[ "$release_operation_active" == "1" ]]; then
        echo "Release operation did not complete; authenticated lock retained for safe recovery." >&2
        if [[ "$cleanup_status" == "0" ]]; then
            cleanup_status=1
        fi
    fi
    exit "$cleanup_status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

operation_environment="$(
    "${release_contract[@]}" \
        release-operation-begin \
        --expect-sha "$SOURCE_SHA" \
        --release-mode "$release_mode" \
        --operation-token "$supervisor_operation_token" \
        --operation-owner-pid "$$" \
        --root "$project_root"
)"
eval "$operation_environment"
unset supervisor_operation_token
release_operation_active=1

derived_data="$project_root/.build/ReleaseDerivedData"
archive_path="$RELEASE_ARCHIVE_PATH"
output_dir="$RELEASE_OUTPUT_DIR"
zip_file="$RELEASE_ZIP_PATH"
dmg_file="$RELEASE_DMG_PATH"
checksums_file="$RELEASE_CHECKSUMS_PATH"
sparkle_tools="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin"

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

if [[ "${CADENCE_REUSE_ARCHIVE:-0}" != "1" ]]; then
    xcodegen generate --spec project.yml
    preflight_environment="$(
        "${release_contract[@]}" \
            release-preflight \
            --expect-sha "$SOURCE_SHA" \
            --release-mode "$release_mode" \
            --root "$project_root"
    )"
    eval "$preflight_environment"

    DEVELOPER_DIR="$developer_dir" xcodebuild \
        -resolvePackageDependencies \
        -project Cadence.xcodeproj \
        -scheme Cadence \
        -derivedDataPath "$derived_data"

    preflight_environment="$(
        "${release_contract[@]}" \
            release-preflight \
            --expect-sha "$SOURCE_SHA" \
            --release-mode "$release_mode" \
            --root "$project_root"
    )"
    eval "$preflight_environment"
    check_release_operation

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

    check_release_operation
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
        CADENCE_SOURCE_GIT_SHA="$SOURCE_SHA" \
        CADENCE_RELEASE_TAG="$TAG" \
        CADENCE_FULL_GATE_ATTESTATION_SHA256="$RELEASE_ATTESTATION_SHA256" \
        "${signing_arguments[@]}"
    check_release_operation
else
    echo "Reusing the existing archive only after validating exact source provenance."
fi

preflight_environment="$(
    "${release_contract[@]}" \
        release-preflight \
        --expect-sha "$SOURCE_SHA" \
        --release-mode "$release_mode" \
        --root "$project_root"
)"
eval "$preflight_environment"
check_release_operation
if [[ "${CADENCE_REUSE_ARCHIVE:-0}" != "1" ]]; then
    "${release_contract[@]}" \
        archive-stamp \
        --archive "$archive_path" \
        --source-sha "$SOURCE_SHA" \
        --root "$project_root"
    check_release_operation
fi
"${release_contract[@]}" \
    archive-check \
    --archive "$archive_path" \
    --source-sha "$SOURCE_SHA" \
    --root "$project_root"
check_release_operation

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
check_release_operation
codesign --verify --deep --strict --verbose=2 "$app_bundle"
check_release_operation
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

staging_dir="$(mktemp -d /private/tmp/cadence-release.XXXXXX)"
appcast_staging="$staging_dir/appcast"
mkdir -p "$appcast_staging"
if [[ "$release_mode" == "local" ]]; then
    check_release_operation
    "$project_root/scripts/create_dmg.sh" "$app_bundle" "$dmg_file" "$HUMAN_RELEASE_NAME"
    check_release_operation
    echo "Prepared local validation artifact: $dmg_file"
    echo "This artifact is ad-hoc signed and must not be published."
    finish_release_operation
    exit 0
fi

# The public path is deliberately fail-closed: the app and disk image both
# need an accepted notarization submission and a locally validated ticket.
check_release_operation
rm -f -- "$zip_file"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$zip_file"
check_release_operation
DEVELOPER_DIR="$developer_dir" xcrun notarytool submit \
    "$zip_file" \
    --keychain-profile "$CADENCE_NOTARY_KEYCHAIN_PROFILE" \
    --wait
check_release_operation
DEVELOPER_DIR="$developer_dir" xcrun stapler staple "$app_bundle"
DEVELOPER_DIR="$developer_dir" xcrun stapler validate "$app_bundle"
spctl --assess --type execute --verbose=4 "$app_bundle"

# Recreate the update archive after stapling the app so offline Gatekeeper
# verification does not depend on network ticket lookup.
check_release_operation
rm -f -- "$zip_file"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$zip_file"
check_release_operation
"$project_root/scripts/create_dmg.sh" "$app_bundle" "$dmg_file" "$HUMAN_RELEASE_NAME"
check_release_operation
DEVELOPER_DIR="$developer_dir" xcrun notarytool submit \
    "$dmg_file" \
    --keychain-profile "$CADENCE_NOTARY_KEYCHAIN_PROFILE" \
    --wait
check_release_operation
DEVELOPER_DIR="$developer_dir" xcrun stapler staple "$dmg_file"
DEVELOPER_DIR="$developer_dir" xcrun stapler validate "$dmg_file"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_file"

check_release_operation
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

check_release_operation
rm -f -- "$zip_file"
mv "$appcast_staging/$ZIP_NAME" "$zip_file"
check_release_operation

check_release_operation
"${release_contract[@]}" \
    release-checksums-write \
    --release-mode "$release_mode" \
    --operation-token "$RELEASE_OPERATION_TOKEN" \
    --operation-owner-pid "$$" \
    --root "$project_root"
check_release_operation

codesign --verify --deep --strict --verbose=2 "$app_bundle"
unzip -t "$zip_file"
check_release_operation

# Keep the tracked source clean through the final provenance checkpoint. The
# intentional appcast mutation is the last operation before shell-only output.
cp "$appcast_staging/appcast.xml" "$project_root/appcast.xml"

echo "Prepared $HUMAN_RELEASE_NAME."
echo "Git tag: $TAG"
echo "GitHub prerelease assets:"
echo "  $dmg_file"
echo "  $zip_file"
echo "  $checksums_file"
echo "Commit and publish appcast.xml before announcing the release."
finish_release_operation
