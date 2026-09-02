#!/bin/bash
# docs/ale/download.sh - Refresh the ALE (AzerothCore Lua Engine) docs
#
# The ALE documentation lives upstream at azerothcore/eluna#main — the
# documentation branch of mod-ale, originally forked from eluna. We don't
# track its content in this repo because it's a regenerable build artifact
# of someone else's source of truth. This script clones upstream into a
# tempdir and rsyncs the result into the surrounding docs/ale/ directory,
# preserving only this script and the local .gitignore. Run it any time
# you want fresh upstream docs.

DIR="${DIR:-/mnt/mtwo/games/azeroth-core/wow-chat-2026/docs/ale}"

set -e

UPSTREAM="https://github.com/azerothcore/eluna.git"
BRANCH="main"

TEMP=$(mktemp -d)
trap "rm -rf ${TEMP}" EXIT

echo "Cloning ${UPSTREAM} (${BRANCH}) into temp..."
git clone --quiet --depth=1 --branch="${BRANCH}" "${UPSTREAM}" "${TEMP}/clone"

echo "Syncing into ${DIR}..."
rsync -a --delete \
    --exclude='.git' \
    --exclude='download.sh' \
    --exclude='.gitignore' \
    "${TEMP}/clone/" "${DIR}/"

echo ""
echo "ALE docs refreshed."
echo "  Location: ${DIR}"
echo "  Upstream commit: $(git -C "${TEMP}/clone" rev-parse --short HEAD)"
