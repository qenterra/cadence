#!/usr/bin/env bash

set -euo pipefail

git_lfs="${GIT_LFS_EXECUTABLE:-}"
if [[ -z "$git_lfs" ]]; then
    git_lfs="$(command -v git-lfs || true)"
fi

if [[ -z "$git_lfs" || "$git_lfs" != /* || ! -x "$git_lfs" ]]; then
    echo "Git LFS is required. Run 'brew bundle' before configuring Xcode." >&2
    exit 69
fi

"$git_lfs" version >/dev/null

# GUI applications do not inherit Homebrew's shell PATH. Store the absolute
# executable in Git's user-level LFS filters so Xcode package checkouts invoke
# the installed binary directly instead of failing with command not found.
/usr/bin/git config --global filter.lfs.clean "$git_lfs clean -- %f"
/usr/bin/git config --global filter.lfs.smudge "$git_lfs smudge -- %f"
/usr/bin/git config --global filter.lfs.process "$git_lfs filter-process"
/usr/bin/git config --global filter.lfs.required true

echo "Configured Git LFS for Xcode: $git_lfs"
