#!/usr/bin/env bash
# Fetch the pinned upstream commit into ./upstream (gitignored) for review / seed SQL.
# The Docker build clones the same SHA itself; this checkout is optional.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
repo="$(lock_value UPSTREAM_REPO)"
sha="$(lock_value UPSTREAM_SHA)"
dest="${ROOT_DIR}/upstream"
if [ ! -d "${dest}/.git" ]; then
  git init -q "${dest}"
  git -C "${dest}" remote add origin "${repo}"
fi
git -C "${dest}" fetch -q --depth 1 origin "${sha}"
git -C "${dest}" checkout -q --detach FETCH_HEAD
actual="$(git -C "${dest}" rev-parse HEAD)"
if [ "${actual}" != "${sha}" ]; then
  echo "SHA mismatch: expected ${sha}, got ${actual}" >&2
  exit 1
fi
echo "upstream checked out at ${actual} in ${dest}"
