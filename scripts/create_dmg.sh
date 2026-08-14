#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <Cadence.app> <output.dmg> <volume-name>" >&2
    exit 64
fi

app_bundle="$1"
dmg_file="$2"
volume_name="$3"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
background="$project_root/release/dmg-background.png"
retina_background="$project_root/release/dmg-background@2x.png"
settings="$project_root/release/dmgbuild-settings.py"
requirements="$project_root/release/requirements.txt"
tools_dir="$project_root/.build/release-tools"
layout_writer="$project_root/scripts/write_dmg_layout.py"
macos_major="$(sw_vers -productVersion | cut -d. -f1)"

if [[ ! -d "$app_bundle" ]]; then
    echo "App bundle was not found: $app_bundle" >&2
    exit 66
fi
if [[ ! -f "$background" || ! -f "$retina_background" ]]; then
    echo "DMG 1x/2x background pair is incomplete." >&2
    exit 66
fi
if [[ ! -f "$settings" || ! -f "$requirements" || ! -f "$layout_writer" ]]; then
    echo "DMG build configuration is incomplete." >&2
    exit 69
fi

if [[ ! -x "$tools_dir/bin/python" ]]; then
    if command -v python3.14 >/dev/null 2>&1; then
        release_python="$(command -v python3.14)"
    elif command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; raise SystemExit(sys.version_info < (3, 10))'; then
        release_python="$(command -v python3)"
    else
        echo "Python 3.10 or newer is required. Install the Brewfile before packaging." >&2
        exit 69
    fi
    "$release_python" -m venv "$tools_dir"
    "$tools_dir/bin/python" -m pip install --disable-pip-version-check -r "$requirements"
fi

mkdir -p "$(dirname "$dmg_file")"
rm -f "$dmg_file"
verification_mount="$(mktemp -d /private/tmp/cadence-dmg-verify.XXXXXX)"
build_workspace="$(mktemp -d /private/tmp/cadence-dmg-build.XXXXXX)"
writable_image="$build_workspace/Cadence-writable.dmg"
build_mount="$build_workspace/mount"
mkdir -p "$build_mount"

legacy_hdiutil_verify() {
    hdiutil verify "$dmg_file"
}

legacy_hdiutil_attach() {
    hdiutil attach -readonly -nobrowse -mountpoint "$verification_mount" "$dmg_file" >/dev/null
}

legacy_hdiutil_detach() {
    hdiutil detach "$verification_mount" >/dev/null
}

cleanup_mounts_and_workspace() {
    if mount | grep -Fq "on $verification_mount "; then
        if (( macos_major >= 27 )); then
            /usr/sbin/diskutil eject "$verification_mount" >/dev/null
        else
            legacy_hdiutil_detach
        fi
    fi
    rmdir "$verification_mount" 2>/dev/null || true
    if mount | grep -Fq "on $build_mount "; then
        /usr/sbin/diskutil eject "$build_mount" >/dev/null
    fi
    rm -rf "$build_workspace"
}
trap cleanup_mounts_and_workspace EXIT

if (( macos_major >= 27 )); then
    if [[ ! -x /usr/sbin/diskutil ]]; then
        echo "macOS 27 or later requires /usr/sbin/diskutil image support." >&2
        exit 69
    fi
    # Build the image entirely through DiskImages/StorageKit. dmgbuild 1.6.7
    # still shells out to deprecated hdiutil verbs on macOS 27.
    app_size_kb="$(du -sk "$app_bundle" | awk '{print $1}')"
    image_size_kb="$((app_size_kb + 131072))"
    /usr/sbin/diskutil image create blank \
        --format RAW \
        --size "${image_size_kb}k" \
        --volumeName "$volume_name" \
        -fs APFS \
        "$writable_image" >/dev/null
    /usr/sbin/diskutil image attach \
        --nobrowse \
        --mountPoint "$build_mount" \
        "$writable_image" >/dev/null
    ditto "$app_bundle" "$build_mount/Cadence.app"
    ln -s /Applications "$build_mount/Applications"
    tiffutil -cathidpicheck "$background" "$retina_background" \
        -out "$build_mount/.background.tiff" >/dev/null
    "$tools_dir/bin/python" "$layout_writer" "$build_mount"
    xcrun SetFile -a V "$build_mount/.background.tiff" "$build_mount/.DS_Store"
    /usr/sbin/diskutil eject "$build_mount" >/dev/null
    /usr/sbin/diskutil image resize --size min "$writable_image" >/dev/null
    /usr/sbin/diskutil image create from \
        --format UDZO \
        "$writable_image" \
        "$dmg_file" >/dev/null
    /usr/sbin/diskutil image info "$dmg_file" >/dev/null
else
    # dmgbuild still supports older hosts; keep their legacy boundary explicit.
    "$tools_dir/bin/python" -m dmgbuild \
        -s "$settings" \
        -D "app=$app_bundle" \
        -D "background=$background" \
        "$volume_name" \
        "$dmg_file"
    legacy_hdiutil_verify
fi

if (( macos_major >= 27 )); then
    /usr/sbin/diskutil image attach \
        --readOnly \
        --nobrowse \
        --mountPoint "$verification_mount" \
        "$dmg_file" >/dev/null
else
    legacy_hdiutil_attach
fi
[[ -d "$verification_mount/Cadence.app" ]]
[[ -L "$verification_mount/Applications" ]]
[[ "$(readlink "$verification_mount/Applications")" == "/Applications" ]]
[[ -f "$verification_mount/.background.tiff" ]]
"$tools_dir/bin/python" "$layout_writer" --verify "$verification_mount"
background_info="$(tiffutil -info "$verification_mount/.background.tiff")"
[[ "$(printf '%s\n' "$background_info" | grep -c '^Directory at ')" -eq 2 ]]
[[ "$background_info" == *"Resolution: 72, 72"* ]]
[[ "$background_info" == *"Resolution: 144, 144"* ]]
codesign --verify --deep --strict "$verification_mount/Cadence.app"
[[ "$(shasum -a 256 "$app_bundle/Contents/MacOS/Cadence" | awk '{print $1}')" == \
    "$(shasum -a 256 "$verification_mount/Cadence.app/Contents/MacOS/Cadence" | awk '{print $1}')" ]]
cleanup_mounts_and_workspace
trap - EXIT
echo "Created $dmg_file"
