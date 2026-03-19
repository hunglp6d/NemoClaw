#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[install]${NC} $1"; }
warn()  { echo -e "${YELLOW}[install]${NC} $1"; }
fail()  { echo -e "${RED}[install]${NC} $1"; exit 1; }

pick_shell_profile() {
  if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
    printf '%s\n' "$HOME/.zshrc"
  elif [ -f "$HOME/.bashrc" ] || [ "$(basename "${SHELL:-}")" = "bash" ]; then
    printf '%s\n' "$HOME/.bashrc"
  else
    printf '%s\n' "$HOME/.profile"
  fi
}

path_contains_dir() {
  local target_dir="$1"
  case ":${PATH:-}:" in
    *":$target_dir:"*) return 0 ;;
    *) return 1 ;;
  esac
}

find_preferred_user_bin_dir() {
  local npm_bin=""
  if command -v npm > /dev/null 2>&1; then
    npm_bin="$(npm config get prefix 2>/dev/null)/bin" || true
    if [ -n "$npm_bin" ] && [ -d "$npm_bin" ] && [ -w "$npm_bin" ] && path_contains_dir "$npm_bin"; then
      printf '%s\n' "$npm_bin"
      return 0
    fi
  fi

  local dir
  OLD_IFS="$IFS"
  IFS=':'
  for dir in ${PATH:-}; do
    [ -n "$dir" ] || continue
    [ -d "$dir" ] || continue
    [ -w "$dir" ] || continue
    case "$dir" in
      "$HOME"/*)
        printf '%s\n' "$dir"
        IFS="$OLD_IFS"
        return 0
        ;;
    esac
  done
  IFS="$OLD_IFS"

  return 1
}

ensure_path_entry() {
  local target_dir="$1"
  local profile
  profile="$(pick_shell_profile)"
  local export_line="export PATH=\"$target_dir:\$PATH\""

  if [ -n "${PATH:-}" ]; then
    case ":$PATH:" in
      *":$target_dir:"*) return 0 ;;
    esac
  fi

  mkdir -p "$(dirname "$profile")"
  touch "$profile"

  if grep -Fqs "$export_line" "$profile"; then
    warn "$target_dir is not on PATH in the current shell."
    warn "Run: source $profile"
    return 0
  fi

  {
    echo ""
    echo "# Added by NemoClaw installer for openshell"
    echo "$export_line"
  } >> "$profile"

  warn "Added $target_dir to PATH in $profile"
  warn "Run: source $profile"
}

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin) OS_LABEL="macOS" ;;
  Linux)  OS_LABEL="Linux" ;;
  *)      fail "Unsupported OS: $OS" ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH_LABEL="x86_64" ;;
  aarch64|arm64) ARCH_LABEL="aarch64" ;;
  *)             fail "Unsupported architecture: $ARCH" ;;
esac

info "Detected $OS_LABEL ($ARCH_LABEL)"

if command -v openshell > /dev/null 2>&1; then
  info "openshell already installed: $(openshell --version 2>&1 || echo 'unknown')"
  exit 0
fi

info "Installing openshell CLI..."

case "$OS" in
  Darwin)
    case "$ARCH_LABEL" in
      x86_64)  ASSET="openshell-x86_64-apple-darwin.tar.gz" ;;
      aarch64) ASSET="openshell-aarch64-apple-darwin.tar.gz" ;;
    esac
    ;;
  Linux)
    case "$ARCH_LABEL" in
      x86_64)  ASSET="openshell-x86_64-unknown-linux-musl.tar.gz" ;;
      aarch64) ASSET="openshell-aarch64-unknown-linux-musl.tar.gz" ;;
    esac
    ;;
esac

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

if command -v gh > /dev/null 2>&1; then
  GH_TOKEN="${GITHUB_TOKEN:-}" gh release download --repo NVIDIA/OpenShell \
    --pattern "$ASSET" --dir "$tmpdir"
else
  curl -fsSL "https://github.com/NVIDIA/OpenShell/releases/latest/download/$ASSET" \
    -o "$tmpdir/$ASSET"
fi

tar xzf "$tmpdir/$ASSET" -C "$tmpdir"

target_dir="/usr/local/bin"

if [ -w "$target_dir" ]; then
  install -m 755 "$tmpdir/openshell" "$target_dir/openshell"
elif target_dir="$(find_preferred_user_bin_dir)"; then
  install -m 755 "$tmpdir/openshell" "$target_dir/openshell"
  warn "Installed openshell to $target_dir/openshell (existing PATH directory)"
elif [ "${NEMOCLAW_NON_INTERACTIVE:-}" = "1" ] || [ ! -t 0 ]; then
  target_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
  mkdir -p "$target_dir"
  install -m 755 "$tmpdir/openshell" "$target_dir/openshell"
  warn "Installed openshell to $target_dir/openshell (user-local path)"
  ensure_path_entry "$target_dir"
else
  sudo install -m 755 "$tmpdir/openshell" "$target_dir/openshell"
fi

info "$("$target_dir/openshell" --version 2>&1 || echo openshell) installed"
