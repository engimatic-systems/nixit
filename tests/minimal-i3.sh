#!/usr/bin/env bash
set -euo pipefail

repo_parent=$(dirname -- "$0")/..
repo=$(CDPATH='' cd -- "$repo_parent" && pwd -P)
contract="$repo/tests/minimal-i3-contract.nix"
source_config="$repo/examples/minimal-i3"
scratch=

cleanup() {
  if [[ -n "$scratch" ]]; then
    rm -rf -- "$scratch"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

if [[ -z "${NIXPKGS_PATH:-}" ]]; then
  fail 'NIXPKGS_PATH must select the Nixpkgs source explicitly'
fi

case "$NIXPKGS_PATH" in
  /*) ;;
  *) fail 'NIXPKGS_PATH must be an absolute filesystem path' ;;
esac

if [[ ! -d "$NIXPKGS_PATH/nixos" ]]; then
  fail "NIXPKGS_PATH does not contain nixos/: $NIXPKGS_PATH"
fi

evaluate() {
  local label=$1
  local config_dir=$2
  local result

  result=$(
    NIX_PATH='' nix-instantiate \
      --eval \
      --strict \
      --json \
      "$contract" \
      --argstr configurationPath "$config_dir/configuration.nix" \
      --argstr nixpkgsPath "$NIXPKGS_PATH"
  )

  if [[ "$result" != '"minimal-i3 contract passed"' ]]; then
    fail "$label evaluation returned an unexpected result: $result"
  fi

  printf 'PASS: %s\n' "$label"
}

evaluate 'in-repo minimal-i3 evaluation' "$source_config"

scratch=$(mktemp -d)
mkdir -p "$scratch/minimal-i3"
cp -a -- "$source_config/." "$scratch/minimal-i3/"

evaluate 'isolated copied-tree evaluation' "$scratch/minimal-i3"

printf 'minimal-i3 contract tests passed\n'
