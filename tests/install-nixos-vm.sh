#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

repo_parent=$(dirname -- "$0")/..
repo=$(CDPATH='' cd -- "$repo_parent" && pwd -P)
script="$repo/hosts/live-installer/install-nixos-vm"
tmp_root=

cleanup() {
  if [[ -n "$tmp_root" ]]; then
    rm -rf -- "$tmp_root"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file=$1
  local expected=$2

  if ! grep -Fq -- "$expected" "$file"; then
    printf 'Expected to find: %s\n' "$expected" >&2
    printf 'Actual output:\n' >&2
    sed -n '1,160p' "$file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file=$1
  local unexpected=$2

  if grep -Fq -- "$unexpected" "$file"; then
    printf 'Expected not to find: %s\n' "$unexpected" >&2
    printf 'Actual output:\n' >&2
    sed -n '1,160p' "$file" >&2
    exit 1
  fi
}

new_case() {
  tmp_root=$(mktemp -d)
  mkdir -p "$tmp_root/bin" "$tmp_root/dev" "$tmp_root/config" "$tmp_root/mnt"
  : > "$tmp_root/log"
}

write_fake() {
  local name=$1
  local body=$2
  local path="$tmp_root/bin/$name"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n'
    printf '%s\n' "$body"
  } > "$path"
  chmod +x "$path"
}

write_common_fakes() {
  write_fake lsblk 'printf "FAKE_LSBLK\n"'
  write_fake wipefs 'printf "wipefs %s\n" "$*" >> "$FAKE_LOG"'
  write_fake parted 'printf "parted %s\n" "$*" >> "$FAKE_LOG"'
  write_fake partprobe 'printf "partprobe %s\n" "$*" >> "$FAKE_LOG"; touch "${1}1" "${1}2"'
  write_fake udevadm 'printf "udevadm %s\n" "$*" >> "$FAKE_LOG"'
  write_fake mkfs.ext4 'printf "mkfs.ext4 %s\n" "$*" >> "$FAKE_LOG"'
  write_fake mount 'printf "mount %s\n" "$*" >> "$FAKE_LOG"; mkdir -p "$2"'
  write_fake nixos-generate-config '
root=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      root=$2
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf "nixos-generate-config --root %s\n" "$root" >> "$FAKE_LOG"
mkdir -p "$root/etc/nixos"
printf "# generated\n" > "$root/etc/nixos/hardware-configuration.nix"
'
  write_fake nixos-install 'printf "nixos-install %s\n" "$*" >> "$FAKE_LOG"'
}

run_helper_expect_failure() {
  local output=$1
  shift

  set +e
  env PATH="$tmp_root/bin:$PATH" FAKE_LOG="$tmp_root/log" "$@" "$script" > "$output" 2>&1
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    sed -n '1,160p' "$output" >&2
    fail "helper unexpectedly succeeded"
  fi
}

run_helper() {
  env \
    PATH="$tmp_root/bin:$PATH" \
    FAKE_LOG="$tmp_root/log" \
    NIXBOXES_INSTALL_ROOT="$tmp_root/mnt" \
    "$@" \
    "$script" > "$tmp_root/output" 2>&1
}

test_missing_disk_fails_before_mutation() {
  new_case
  write_common_fakes
  printf '{ ... }: {}\n' > "$tmp_root/config/configuration.nix"

  run_helper_expect_failure "$tmp_root/output" \
    CONFIGURATION_NIX="$tmp_root/config/configuration.nix"

  assert_contains "$tmp_root/output" 'DISK is required.'
  assert_contains "$tmp_root/output" 'Available block devices:'
  assert_contains "$tmp_root/output" 'FAKE_LSBLK'

  if [[ -s "$tmp_root/log" ]]; then
    sed -n '1,160p' "$tmp_root/log" >&2
    fail "mutation command ran with missing DISK"
  fi

  cleanup
  tmp_root=
}

test_missing_configuration_fails_before_mutation() {
  new_case
  write_common_fakes

  run_helper_expect_failure "$tmp_root/output" \
    DISK="$tmp_root/dev/vda"

  assert_contains "$tmp_root/output" 'CONFIGURATION_NIX is required.'
  assert_contains "$tmp_root/output" 'Available block devices:'
  assert_contains "$tmp_root/output" 'FAKE_LSBLK'

  if [[ -s "$tmp_root/log" ]]; then
    sed -n '1,160p' "$tmp_root/log" >&2
    fail "mutation command ran with missing CONFIGURATION_NIX"
  fi

  cleanup
  tmp_root=
}

test_preserves_supplied_hardware_configuration() {
  new_case
  write_common_fakes
  printf '{ ... }: {}\n' > "$tmp_root/config/configuration.nix"
  printf '# supplied hardware\n' > "$tmp_root/config/hardware-configuration.nix"

  run_helper \
    DISK="$tmp_root/dev/vda" \
    CONFIGURATION_NIX="$tmp_root/config/configuration.nix"

  cmp "$tmp_root/config/hardware-configuration.nix" \
    "$tmp_root/mnt/etc/nixos/hardware-configuration.nix"
  assert_contains "$tmp_root/output" \
    "Installing NixOS to $tmp_root/dev/vda. This will destroy data on $tmp_root/dev/vda."
  assert_not_contains "$tmp_root/log" 'nixos-generate-config'
  assert_contains "$tmp_root/log" "nixos-install --root $tmp_root/mnt"

  cleanup
  tmp_root=
}

test_generates_missing_hardware_configuration() {
  new_case
  write_common_fakes
  printf '{ ... }: {}\n' > "$tmp_root/config/configuration.nix"

  run_helper \
    DISK="$tmp_root/dev/vda" \
    CONFIGURATION_NIX="$tmp_root/config/configuration.nix"

  assert_contains "$tmp_root/log" "nixos-generate-config --root $tmp_root/mnt"
  assert_contains "$tmp_root/mnt/etc/nixos/hardware-configuration.nix" '# generated'
  assert_contains "$tmp_root/log" "nixos-install --root $tmp_root/mnt"

  cleanup
  tmp_root=
}

test_missing_disk_fails_before_mutation
test_missing_configuration_fails_before_mutation
test_preserves_supplied_hardware_configuration
test_generates_missing_hardware_configuration

printf 'install-nixos-vm tests passed\n'
