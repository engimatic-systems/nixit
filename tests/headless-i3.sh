#!/usr/bin/env bash
set -euo pipefail
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
: "${NIXPKGS_PATH:?Set NIXPKGS_PATH explicitly to a Nixpkgs directory or channel source}"
test_root=$(mktemp -d -t nixit-headless-i3.XXXXXX)
trap 'chmod -R u+w "$test_root"; rm -rf -- "$test_root"' EXIT
cp -a "$repo/examples/headless-i3" "$test_root/example"

for example in "$repo/examples/headless-i3" "$test_root/example"; do
  for sidecar in gui-vm-session.sh gui-shell-attach.sh; do
    bash -n "$example/$sidecar"
  done
  NIX_PATH='' nix-instantiate "$repo/tests/headless-i3-contract.nix" \
    --arg nixpkgsPath '<nixpkgs>' --arg examplePath "\"$example\"" \
    -I "nixpkgs=$NIXPKGS_PATH" -A system >/dev/null
  NIX_PATH='' nix-build "$repo/tests/headless-i3-contract.nix" \
    --arg nixpkgsPath '<nixpkgs>' --arg examplePath "\"$example\"" \
    -I "nixpkgs=$NIXPKGS_PATH" -A sessionCheck --no-out-link >/dev/null
  printf 'PASS: evaluated configuration and built session from %s\n' "$example"
done
