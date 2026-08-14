#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <derived-data-path>" >&2
    exit 2
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
catalog="$project_root/Sources/Cadence/Resources/Localizable.xcstrings"
derived_data="$1"

metadata_files=()
while IFS= read -r -d '' metadata_file; do
    metadata_files+=("$metadata_file")
done < <(
    find "$derived_data/Build/Intermediates.noindex/Cadence.build" \
        -path '*Cadence.build/Objects-normal/*/*.stringsdata' \
        -print0
)

if [[ ${#metadata_files[@]} -eq 0 ]]; then
    echo "No Cadence localization metadata found under $derived_data." >&2
    exit 1
fi

python3 "$project_root/scripts/verify_localization.py" \
    "$catalog" \
    "${metadata_files[@]}"
