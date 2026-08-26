#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
tool_environment="$project_root/.build/python-tools"
bootstrap_python="${CADENCE_BOOTSTRAP_PYTHON:-python3.14}"

if ! command -v "$bootstrap_python" >/dev/null 2>&1; then
    echo "Python 3.14 is required for release image tools. Run 'brew bundle' or set CADENCE_BOOTSTRAP_PYTHON." >&2
    exit 69
fi

"$bootstrap_python" -m venv "$tool_environment"
"$tool_environment/bin/python" -m pip install \
    --disable-pip-version-check \
    --requirement "$project_root/requirements-dev.txt"
"$tool_environment/bin/python" -c 'import PIL'

echo "Prepared release image tools: $tool_environment/bin/python"
