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

if [[ ! -d "$app_bundle" ]]; then
    echo "App bundle was not found: $app_bundle" >&2
    exit 66
fi
if [[ ! -f "$background" || ! -f "$retina_background" ]]; then
    echo "DMG 1x/2x background pair is incomplete." >&2
    exit 66
fi
if [[ ! -f "$settings" || ! -f "$requirements" ]]; then
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
"$tools_dir/bin/python" -m dmgbuild \
    -s "$settings" \
    -D "app=$app_bundle" \
    -D "background=$background" \
    "$volume_name" \
    "$dmg_file"

hdiutil verify "$dmg_file"
verification_mount="$(mktemp -d /private/tmp/cadence-dmg-verify.XXXXXX)"
cleanup_verification_mount() {
    if mount | grep -Fq "on $verification_mount "; then
        hdiutil detach "$verification_mount" >/dev/null
    fi
    rmdir "$verification_mount" 2>/dev/null || true
}
trap cleanup_verification_mount EXIT

hdiutil attach -readonly -nobrowse -mountpoint "$verification_mount" "$dmg_file" >/dev/null
[[ -d "$verification_mount/Cadence.app" ]]
[[ -L "$verification_mount/Applications" ]]
[[ "$(readlink "$verification_mount/Applications")" == "/Applications" ]]
[[ -f "$verification_mount/.background.tiff" ]]
background_info="$(tiffutil -info "$verification_mount/.background.tiff")"
[[ "$(printf '%s\n' "$background_info" | grep -c '^Directory at ')" -eq 2 ]]
[[ "$background_info" == *"Resolution: 72, 72"* ]]
[[ "$background_info" == *"Resolution: 144, 144"* ]]
codesign --verify --deep --strict "$verification_mount/Cadence.app"
[[ "$(shasum -a 256 "$app_bundle/Contents/MacOS/Cadence" | awk '{print $1}')" == \
    "$(shasum -a 256 "$verification_mount/Cadence.app/Contents/MacOS/Cadence" | awk '{print $1}')" ]]
cleanup_verification_mount
trap - EXIT
echo "Created $dmg_file"
