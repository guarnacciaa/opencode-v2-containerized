#!/usr/bin/env bash
# Resolves the newest 2.x release of opencode from the npm registry
# (same source as the binaries used in the Dockerfile).
# Usage: ./scripts/resolve-latest-v2.sh        -> prints e.g. 2.0.29
set -euo pipefail

JSON="$(curl -fsSL "https://registry.npmjs.org/@opencode%2fcli-linux-x64")"
LATEST="$(echo "$JSON" | jq -r '.versions | keys[] | select(startswith("2."))' | sort -V | tail -n 1)"
LATEST="${LATEST#v}"

if [[ -z "$LATEST" ]]; then
  echo "Unable to resolve the latest v2 version" >&2
  exit 1
fi

echo "$LATEST"
