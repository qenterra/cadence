#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
baseline="${CADENCE_PERIPHERY_BASELINE:-$project_root/.periphery-baseline.json}"
index_store="${CADENCE_PERIPHERY_INDEX_STORE_PATH:-$project_root/.build/DerivedData/Index.noindex/DataStore}"

if ! command -v periphery >/dev/null 2>&1; then
    echo "Periphery is required. Run: brew bundle" >&2
    exit 1
fi

if [[ ! -f "$baseline" ]]; then
    echo "Periphery baseline is missing: $baseline" >&2
    exit 1
fi

if [[ ! -d "$index_store" ]]; then
    echo "Xcode index store is missing: $index_store" >&2
    echo "Run the Cadence test build before the dead-code gate." >&2
    exit 1
fi

cd "$project_root"

DEVELOPER_DIR="${DEVELOPER_DIR:-}" periphery scan \
    --project Cadence.xcodeproj \
    --schemes Cadence \
    --targets Cadence CadenceTests \
    --index-store-path "$index_store" \
    --skip-build \
    --skip-schemes-validation \
    --retain-swift-ui-previews \
    --retain-codable-properties \
    --retain-objc-accessible \
    --retain-assign-only-properties \
    --baseline "$baseline" \
    --strict \
    --disable-update-check
