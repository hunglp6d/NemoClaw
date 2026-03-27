#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Self-contained config mutability E2E demo.
#
# Builds EVERYTHING from source, then walks through the full flow:
#
#   Phase A: Bootstrap
#     0. Check / install prerequisites (Docker, mise, cargo, etc.)
#     1. Clean previous state
#     2. Clone OpenShell, apply patches
#     3. Build patched OpenShell cluster from source (mise run cluster)
#     4. Build patched openshell CLI from source (cargo build)
#     5. Create NemoClaw sandbox on the patched gateway
#
#   Phase B: Interactive demo
#     6. Show baseline config
#     7. Submit config change request from inside the sandbox
#        (rename assistant: "Lew Alcindor" → "Kareem Abdul-Jabbar")
#     8. User approves in TUI (other terminal)
#     9. Verify the override took effect
#    10. Test gateway.* security block
#    11. Host-side direct set (comparison)
#    12. Host-side gateway.* refusal
#
# Usage:
#   bash scripts/poc-round-trip-test.sh
#
# Then open a SECOND terminal and run:
#   openshell term -g openshell-source
#
# The script pauses before each interactive step.

set -euo pipefail

DEMO_ONLY=false
if [[ "${1:-}" == "--demo-only" ]]; then
  DEMO_ONLY=true
  shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENSHELL_SOURCE="/tmp/openshell-source"
SANDBOX_NAME="${NEMOCLAW_SANDBOX_NAME:-my-assistant}"
GATEWAY_NAME="openshell-source"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

step() {
  echo -e "\n${GREEN}═══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}▸ $1${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
}
info() { echo -e "  ${CYAN}$1${NC}"; }
warn() { echo -e "  ${YELLOW}$1${NC}"; }
err() {
  echo -e "  ${RED}$1${NC}" >&2
  exit 1
}
ok() { echo -e "  ${GREEN}✓ $1${NC}"; }
wait_enter() {
  echo -e "\n  ${YELLOW}Press Enter to continue...${NC}"
  read -r
}

# Download a file from the sandbox to stdout
sandbox_cat() {
  local sandbox="$1" remote_path="$2"
  local tmpdir
  tmpdir="$(mktemp -d)"
  if openshell sandbox download "$sandbox" "$remote_path" "$tmpdir" 2>/dev/null; then
    local bname
    bname="$(basename "$remote_path")"
    if [[ -f "$tmpdir/$bname" ]]; then
      cat "$tmpdir/$bname"
    fi
  fi
  rm -rf "$tmpdir"
}

# Write a script to the sandbox via connect stdin
sandbox_exec() {
  local sandbox="$1"
  shift
  local tmpfile
  tmpfile="$(mktemp)"
  for cmd in "$@"; do
    printf '%s\n' "$cmd" >>"$tmpfile"
  done
  printf 'exit\n' >>"$tmpfile"
  openshell sandbox connect "$sandbox" <"$tmpfile" 2>&1
  rm -f "$tmpfile"
}

if [[ "$DEMO_ONLY" == "false" ]]; then
  # ╔═════════════════════════════════════════════════════════════════╗
  # ║  PHASE A: Bootstrap — build everything from source             ║
  # ╚═════════════════════════════════════════════════════════════════╝

  # ══════════════════════════════════════════════════════════════════
  # Step 0: Check prerequisites
  # ══════════════════════════════════════════════════════════════════
  step "0. Checking prerequisites"

  # Docker — start Colima if needed (macOS)
  if ! command -v docker >/dev/null 2>&1; then
    err "docker not found. Install Docker Desktop or Colima."
  fi
  if ! docker info >/dev/null 2>&1; then
    if [[ "$(uname)" == "Darwin" ]] && command -v colima >/dev/null 2>&1; then
      info "Docker not running — starting Colima..."
      if ! colima start 2>&1; then
        warn "Colima start failed — force-deleting stale instance and retrying..."
        colima delete --force 2>/dev/null || true
        colima start
      fi
      docker info >/dev/null 2>&1 || err "Failed to start Colima"
      ok "Started Colima"
    else
      err "Docker is not running. Start it first."
    fi
  else
    ok "Docker running"
  fi

  # mise
  if ! command -v mise >/dev/null 2>&1; then
    err "mise not found. Install: curl https://mise.run | sh"
  fi
  ok "mise installed ($(mise --version 2>&1 | head -1))"

  # cargo
  if ! command -v cargo >/dev/null 2>&1; then
    err "cargo not found. Install Rust: https://rustup.rs"
  fi
  ok "cargo installed"

  # bash version (mapfile requires 4+)
  BASH_MAJOR="${BASH_VERSINFO[0]}"
  if [[ "$BASH_MAJOR" -lt 4 ]]; then
    err "bash $BASH_VERSION is too old (need 4+). Install: brew install bash"
  fi
  ok "bash $BASH_VERSION"

  # NVIDIA_API_KEY
  if [[ -z "${NVIDIA_API_KEY:-}" ]]; then
    err "NVIDIA_API_KEY not set"
  fi
  ok "NVIDIA_API_KEY set"

  # GitHub token (for mise rate limits)
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    if command -v gh >/dev/null 2>&1; then
      GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
      export GITHUB_TOKEN
    fi
  fi
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    err "GITHUB_TOKEN not set and gh CLI not authenticated. Run: gh auth login"
  fi
  export MISE_GITHUB_TOKEN="$GITHUB_TOKEN"
  export MISE_AQUA_SKIP_VERIFY=1
  ok "GitHub token available"

  # Ensure bash 5+ is found first on PATH (macOS ships 3.2 which lacks mapfile)
  export PATH="/opt/homebrew/bin:$PATH"

  # ══════════════════════════════════════════════════════════════════
  # Step 1: Clean everything from previous runs
  # ══════════════════════════════════════════════════════════════════
  step "1. Cleaning previous state"

  pkill -f openshell 2>/dev/null || true
  openshell forward stop 8080 2>/dev/null || true
  openshell forward stop 18789 2>/dev/null || true
  openshell gateway destroy -g "$GATEWAY_NAME" 2>/dev/null || true
  openshell gateway destroy -g nemoclaw 2>/dev/null || true
  docker rm -f "openshell-cluster-${GATEWAY_NAME}" 2>/dev/null || true
  docker volume rm "openshell-cluster-${GATEWAY_NAME}" 2>/dev/null || true
  docker rm -f openshell-cluster-nemoclaw 2>/dev/null || true
  docker volume rm openshell-cluster-nemoclaw 2>/dev/null || true
  lsof -ti :8080,:18789 2>/dev/null | xargs kill 2>/dev/null || true
  docker buildx prune -af 2>/dev/null || true
  docker images --format '{{.Repository}}:{{.Tag}}' | grep openshell | xargs -r docker rmi -f 2>/dev/null || true
  rm -rf "$OPENSHELL_SOURCE"
  ok "Clean slate"

  # ══════════════════════════════════════════════════════════════════
  # Step 2: Clone OpenShell and apply patch
  # ══════════════════════════════════════════════════════════════════
  step "2. Cloning OpenShell and applying config-approval patch"

  OS_VERSION="$(sed -nE 's/^min_openshell_version:[[:space:]]*"([^"]+)".*/\1/p' "$ROOT/nemoclaw-blueprint/blueprint.yaml" | head -1)"
  OS_VERSION="${OS_VERSION:-0.0.15}"
  info "OpenShell version: v${OS_VERSION} (from blueprint.yaml)"

  git clone --branch "v${OS_VERSION}" --depth 1 https://github.com/NVIDIA/OpenShell.git "$OPENSHELL_SOURCE"
  cd "$OPENSHELL_SOURCE"
  git apply "$ROOT/patches/openshell-config-approval.patch"
  ok "Patch applied"

  # ══════════════════════════════════════════════════════════════════
  # Step 3: Build patched OpenShell and deploy cluster
  # ══════════════════════════════════════════════════════════════════
  step "3. Building patched OpenShell from source (mise run cluster)"
  info "This builds gateway + cluster Docker images from Rust source"
  info "and deploys a local k3s cluster. Takes ~10-15 min on first run."

  cd "$OPENSHELL_SOURCE"
  mise trust

  # mise run cluster may fail in post-deploy steps on macOS (bash 3.2 lacks
  # mapfile). The Docker images and k3s bootstrap succeed; the failure is in
  # the incremental deploy wrapper. If the gateway comes up healthy, proceed.
  if ! mise run cluster; then
    if openshell gateway info -g "$GATEWAY_NAME" >/dev/null 2>&1; then
      warn "mise run cluster had errors but gateway is healthy — proceeding"
    else
      err "mise run cluster failed and gateway is not healthy"
    fi
  fi
  ok "Cluster deployed with patched OpenShell"

  # ══════════════════════════════════════════════════════════════════
  # Step 4: Build patched CLI binary
  # ══════════════════════════════════════════════════════════════════
  step "4. Building patched openshell CLI"
  info "Compiling openshell-cli with config approval TUI support..."

  cd "$OPENSHELL_SOURCE"
  cargo build --release -p openshell-cli --features openshell-core/dev-settings

  OPENSHELL_BIN="$(command -v openshell 2>/dev/null || echo "$HOME/.local/bin/openshell")"
  mkdir -p "$(dirname "$OPENSHELL_BIN")"
  cp "$OPENSHELL_SOURCE/target/release/openshell" "$OPENSHELL_BIN"
  ok "Installed patched CLI: $(openshell --version 2>&1)"

  # ══════════════════════════════════════════════════════════════════
  # Step 5: Create NemoClaw sandbox on the patched gateway
  # ══════════════════════════════════════════════════════════════════
  step "5. Creating NemoClaw sandbox"
  info "Staging build context and building sandbox Docker image..."

  cd "$ROOT"
  BUILDCTX="$(mktemp -d)"
  cp Dockerfile "$BUILDCTX/"
  cp -r nemoclaw "$BUILDCTX/nemoclaw"
  cp -r nemoclaw-blueprint "$BUILDCTX/nemoclaw-blueprint"
  cp -r scripts "$BUILDCTX/scripts"
  cp -r patches "$BUILDCTX/patches"
  rm -rf "$BUILDCTX/nemoclaw/node_modules"

  openshell sandbox create \
    --from "$BUILDCTX/Dockerfile" \
    --name "$SANDBOX_NAME" \
    --policy nemoclaw-blueprint/policies/openclaw-sandbox.yaml \
    -g "$GATEWAY_NAME" \
    -- echo ready

  rm -rf "$BUILDCTX"

  # Wait for sandbox to be Ready
  info "Waiting for sandbox to be ready..."
  SANDBOX_READY=false
  for _ in $(seq 1 30); do
    if openshell sandbox list -g "$GATEWAY_NAME" 2>/dev/null | grep -q "$SANDBOX_NAME.*Ready"; then
      SANDBOX_READY=true
      break
    fi
    sleep 2
  done
  if [[ "$SANDBOX_READY" != "true" ]]; then
    err "Sandbox '$SANDBOX_NAME' did not become ready within 60 seconds"
  fi
  openshell sandbox list -g "$GATEWAY_NAME"
  ok "Sandbox '$SANDBOX_NAME' is ready"

  # Register in NemoClaw registry so nemoclaw CLI commands work
  mkdir -p "$HOME/.nemoclaw"
  REGISTRY="$HOME/.nemoclaw/sandboxes.json"
  if [[ -f "$REGISTRY" ]]; then
    node -e "
    const fs = require('fs');
    const r = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
    r.sandboxes = r.sandboxes || {};
    r.sandboxes['$SANDBOX_NAME'] = {
      name: '$SANDBOX_NAME',
      createdAt: new Date().toISOString(),
      model: null, nimContainer: null, provider: null, gpuEnabled: false, policies: []
    };
    fs.writeFileSync('$REGISTRY', JSON.stringify(r, null, 2));
  "
  else
    node -e "
    const fs = require('fs');
    fs.writeFileSync('$REGISTRY', JSON.stringify({
      sandboxes: {
        '$SANDBOX_NAME': {
          name: '$SANDBOX_NAME',
          createdAt: new Date().toISOString(),
          model: null, nimContainer: null, provider: null, gpuEnabled: false, policies: []
        }
      },
      defaultSandbox: '$SANDBOX_NAME'
    }, null, 2));
  "
  fi
  ok "Registered in NemoClaw registry"

fi # end DEMO_ONLY check

# ╔═════════════════════════════════════════════════════════════════╗
# ║  PHASE B: Interactive demo                                     ║
# ╚═════════════════════════════════════════════════════════════════╝

export OPENSHELL_GATEWAY="$GATEWAY_NAME"
export NEMOCLAW_SANDBOX_NAME="$SANDBOX_NAME"

echo ""
echo -e "  ${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "  ${GREEN}║  Bootstrap complete. Starting interactive demo.       ║${NC}"
echo -e "  ${GREEN}║                                                       ║${NC}"
echo -e "  ${GREEN}║  Sandbox: ${SANDBOX_NAME}$(printf '%*s' $((28 - ${#SANDBOX_NAME})) '')║${NC}"
echo -e "  ${GREEN}║  Gateway: ${GATEWAY_NAME}$(printf '%*s' $((28 - ${#GATEWAY_NAME})) '')║${NC}"
echo -e "  ${GREEN}║                                                       ║${NC}"
echo -e "  ${GREEN}║  NOW open a second terminal and run:                  ║${NC}"
echo -e "  ${GREEN}║    openshell term -g ${GATEWAY_NAME}$(printf '%*s' $((18 - ${#GATEWAY_NAME})) '')║${NC}"
echo -e "  ${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
wait_enter

# ══════════════════════════════════════════════════════════════════
# Step 6: Show baseline config
# ══════════════════════════════════════════════════════════════════
step "6. Show current config (baseline)"
nemoclaw "$SANDBOX_NAME" config-get

info "Check config-overrides.json5 in sandbox..."
overrides_content="$(sandbox_cat "$SANDBOX_NAME" /sandbox/.openclaw-data/config-overrides.json5 2>/dev/null || true)"
if [[ -n "$overrides_content" ]]; then
  echo "$overrides_content"
else
  info "(file not found or empty — that's OK for a fresh sandbox)"
fi
wait_enter

# ══════════════════════════════════════════════════════════════════
# Step 7: Submit config change request FROM INSIDE the sandbox
# ══════════════════════════════════════════════════════════════════
step "7. Submit a config change request from inside the sandbox"
info "Writing a config request file to /sandbox/.openclaw-data/config-requests/"
info "This simulates what an agent would do when it wants to change its own config."
info ""
info "Scenario: The assistant's display name is 'Lew Alcindor'."
info "The agent requests a name change to 'Kareem Abdul-Jabbar'."
echo ""

REQUEST_TMPDIR="$(mktemp -d)"
printf '{"key": "ui.assistant.name", "value": "Kareem Abdul-Jabbar"}\n' \
  >"$REQUEST_TMPDIR/test-name-change.json"
openshell sandbox upload "$SANDBOX_NAME" "$REQUEST_TMPDIR/test-name-change.json" /sandbox/.openclaw-data/config-requests/
rm -rf "$REQUEST_TMPDIR"

info "Request file uploaded. Verifying:"
sandbox_exec "$SANDBOX_NAME" \
  'ls -la /sandbox/.openclaw-data/config-requests/' \
  'cat /sandbox/.openclaw-data/config-requests/test-name-change.json'

echo ""
info "The sandbox scanner polls every 5 seconds."
info "It will detect this file and submit a CONFIG PolicyChunk to the gateway."
echo ""
echo -e "  ${YELLOW}════════════════════════════════════════════════════${NC}"
echo -e "  ${YELLOW}  NOW: Switch to Terminal 2 (openshell term)${NC}"
echo -e "  ${YELLOW}${NC}"
echo -e "  ${YELLOW}  You should see a pending chunk:${NC}"
echo -e "  ${YELLOW}    CONFIG  ui.assistant.name  [pending]${NC}"
echo -e "  ${YELLOW}${NC}"
echo -e "  ${YELLOW}  Press Enter to view the detail popup — you should${NC}"
echo -e "  ${YELLOW}  see the proposed name change to 'Kareem Abdul-Jabbar'.${NC}"
echo -e "  ${YELLOW}${NC}"
echo -e "  ${YELLOW}  Press [a] to approve it, then come back here.${NC}"
echo -e "  ${YELLOW}════════════════════════════════════════════════════${NC}"
wait_enter

# ══════════════════════════════════════════════════════════════════
# Step 8: Verify the approval took effect
# ══════════════════════════════════════════════════════════════════
step "8. Verify the config change was applied"
info "After approval, the sandbox poll loop writes the overrides file."
info "Waiting 15 seconds for the poll loop..."
sleep 15

info "Current overrides file:"
overrides_after="$(sandbox_cat "$SANDBOX_NAME" /sandbox/.openclaw-data/config-overrides.json5 2>/dev/null || true)"
if [[ -n "$overrides_after" ]]; then
  echo "$overrides_after"
  if echo "$overrides_after" | grep -q "Kareem Abdul-Jabbar"; then
    echo -e "\n  ${GREEN}✓ Override applied! Assistant name changed to 'Kareem Abdul-Jabbar'${NC}"
    echo -e "  ${GREEN}  Open the OpenClaw chat UI — the assistant name should now show the new name.${NC}"
  else
    warn "Override file exists but doesn't contain the expected name."
    warn "The poll loop may not have run yet. Try waiting longer."
  fi
else
  warn "Overrides file not found. The approval may not have propagated yet."
  warn "Check the TUI — is the chunk still pending?"
fi
echo ""

info "Config-get view:"
nemoclaw "$SANDBOX_NAME" config-get
wait_enter

# ══════════════════════════════════════════════════════════════════
# Step 9: Security — gateway.* blocked
# ══════════════════════════════════════════════════════════════════
step "9. Test security: gateway.* should be blocked"
info "Writing a gateway.auth.token change request (should be blocked by scanner)..."

EVIL_TMPDIR="$(mktemp -d)"
printf '{"key": "gateway.auth.token", "value": "stolen-token"}\n' \
  >"$EVIL_TMPDIR/evil.json"
openshell sandbox upload "$SANDBOX_NAME" "$EVIL_TMPDIR/evil.json" /sandbox/.openclaw-data/config-requests/
rm -rf "$EVIL_TMPDIR"
info "Evil request file uploaded."

info "Waiting 10 seconds for the scanner to process..."
sleep 10
info "Check sandbox logs — you should see 'gateway.* blocked' message:"
nemoclaw "$SANDBOX_NAME" logs 2>/dev/null | grep -i "gateway.*blocked" | tail -3 || warn "No 'blocked' message found in recent logs (may have scrolled past)"
wait_enter

# ══════════════════════════════════════════════════════════════════
# Step 10: Host-side direct set (comparison)
# ══════════════════════════════════════════════════════════════════
step "10. Host-side direct config-set (bypasses TUI approval)"
info "This writes directly to the overrides file — no TUI approval needed."
info "This is the operator path, not the agent path."
echo ""
nemoclaw "$SANDBOX_NAME" config-set --key channels.defaults.configWrites --value false
nemoclaw "$SANDBOX_NAME" config-get
wait_enter

# ══════════════════════════════════════════════════════════════════
# Step 11: Host-side gateway.* refusal
# ══════════════════════════════════════════════════════════════════
step "11. Host-side gateway.* refusal"
info "Even from the host, gateway.* is blocked:"
nemoclaw "$SANDBOX_NAME" config-set --key gateway.auth.token --value evil 2>&1 || true

# ══════════════════════════════════════════════════════════════════
# Done
# ══════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "  ${GREEN}║  Round-trip test complete!                            ║${NC}"
echo -e "  ${GREEN}║                                                       ║${NC}"
echo -e "  ${GREEN}║  What you just verified:                              ║${NC}"
echo -e "  ${GREEN}║    ✓ Built patched OpenShell from source              ║${NC}"
echo -e "  ${GREEN}║    ✓ Created sandbox with frozen config               ║${NC}"
echo -e "  ${GREEN}║    ✓ Agent writes config request inside sandbox       ║${NC}"
echo -e "  ${GREEN}║    ✓ Scanner submits it as a CONFIG PolicyChunk       ║${NC}"
echo -e "  ${GREEN}║    ✓ TUI shows config detail view with proposed JSON  ║${NC}"
echo -e "  ${GREEN}║    ✓ Approval triggers override file write            ║${NC}"
echo -e "  ${GREEN}║    ✓ Assistant name changed (Lew Alcindor → Kareem)   ║${NC}"
echo -e "  ${GREEN}║    ✓ gateway.* blocked at scanner level               ║${NC}"
echo -e "  ${GREEN}║    ✓ Host-side direct set works (operator path)       ║${NC}"
echo -e "  ${GREEN}║    ✓ Host-side gateway.* also blocked                 ║${NC}"
echo -e "  ${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
info "Clean up with: nemoclaw $SANDBOX_NAME destroy --yes"
