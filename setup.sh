#!/usr/bin/env bash
# =============================================================================
# apply-focus-enterprise.sh
#
# Configures the Firefox Focus iOS project to build the "Focus (Enterprise)"
# scheme under your own Apple Developer team with Xcode auto-managed signing.
#
# This script has been split into two steps:
# 1. step1-patch.sh  - applies text patches across the codebase
# 2. step2-inject.sh - modifies Xcode project using Ruby and injects the widget
#
# You can run them individually or use this wrapper to run both.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Running Step 1: Patching"
bash "${SCRIPT_DIR}/step1-patch.sh"

echo ""
echo "==> Running Step 2: Code Injection & Xcode project modification"
bash "${SCRIPT_DIR}/step2-inject.sh"
