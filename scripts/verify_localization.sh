#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <derived-data-path>" >&2
    exit 2
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
catalog="$project_root/Sources/Cadence/Resources/Localizable.xcstrings"
derived_data="$1"
temporary_directory="$(mktemp -d /private/tmp/cadence-localizable.XXXXXX)"
temporary_catalog="$temporary_directory/Localizable.xcstrings"
trap 'rm -f "$temporary_catalog"; rmdir "$temporary_directory"' EXIT

cp "$catalog" "$temporary_catalog"

metadata_arguments=()
while IFS= read -r -d '' metadata_file; do
    metadata_arguments+=(--stringsdata "$metadata_file")
done < <(
    find "$derived_data/Build/Intermediates.noindex/Cadence.build" \
        -path '*Cadence.build/Objects-normal/*/*.stringsdata' \
        -print0
)

if [[ ${#metadata_arguments[@]} -eq 0 ]]; then
    echo "No Cadence localization metadata found under $derived_data." >&2
    exit 1
fi

xcrun xcstringstool sync "$temporary_catalog" "${metadata_arguments[@]}"

if ! cmp -s "$catalog" "$temporary_catalog"; then
    echo "Localizable.xcstrings is stale. Rebuild and sync compiler metadata." >&2
    diff -u "$catalog" "$temporary_catalog" || true
    exit 1
fi

key_count="$(xcrun xcstringstool print "$catalog" | awk 'NF' | wc -l | tr -d ' ')"
echo "Localization catalog is synchronized ($key_count keys)."
