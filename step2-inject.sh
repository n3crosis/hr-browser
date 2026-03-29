#!/usr/bin/env bash
# =============================================================================
# step2-inject.sh
#
# Configures the Xcode project to auto-manage signing under your Apple
# Developer team and injects the floating widget source files.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration — edit these defaults or override via environment variables
# -----------------------------------------------------------------------------

# Your 10-character Apple Developer Team ID (found in developer.apple.com)
TEAM_ID="${TEAM_ID:-VRZ2JHMMCJ}"

# App display name shown on the home screen and in Xcode's PRODUCT_NAME /
# DISPLAY_NAME build settings. Replaces "Firefox Focus" and "Firefox Klar".
APP_NAME="${APP_NAME:-Sealion}"

# Export so child processes can read them via ProcessInfo/ENV.
export TEAM_ID APP_NAME

# -----------------------------------------------------------------------------
# Resolve paths relative to this script so it works from any working directory
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOCUS_DIR="${SCRIPT_DIR}/firefox-ios/focus-ios"
PBXPROJ="${FOCUS_DIR}/Blockzilla.xcodeproj/project.pbxproj"

if [[ ! -f "${PBXPROJ}" ]]; then
  echo "ERROR: Cannot find project file at ${PBXPROJ}" >&2
  echo "       Make sure the firefox-ios repo is cloned next to this script." >&2
  exit 1
fi

echo "==> Step 2: Patching Xcode project & injecting code"
echo "    Team ID    : ${TEAM_ID}"
echo "    App Name   : ${APP_NAME}"
echo "    Project    : ${FOCUS_DIR}"
echo ""

cd "${FOCUS_DIR}"

WIDGET_DIR="${FOCUS_DIR}/Blockzilla/FloatingWidget"
mkdir -p "${WIDGET_DIR}"

# ---------- 2a — Copy widget source files ----------
SOURCES_WIDGET="${SCRIPT_DIR}/sources/FloatingWidget"
if [[ ! -d "${SOURCES_WIDGET}" ]]; then
  echo "ERROR: Widget source files not found at ${SOURCES_WIDGET}" >&2
  exit 1
fi
cp -r "${SOURCES_WIDGET}/" "${WIDGET_DIR}/"

# ---------- 2b — Add HealthKit descriptions to Info.plist ----------
INFO_PLIST="${FOCUS_DIR}/Blockzilla/Info.plist"
echo "    Adding HealthKit usage descriptions to Info.plist..."
/usr/libexec/PlistBuddy -c "Delete :NSHealthShareUsageDescription" "${INFO_PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :NSHealthUpdateUsageDescription" "${INFO_PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSHealthShareUsageDescription string 'This lets the app display your heart rate on the widget.'" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Add :NSHealthUpdateUsageDescription string 'This lets the app display your heart rate on the widget.'" "${INFO_PLIST}"

# ---------- 2c — Create HealthKit entitlements file ----------
ENTITLEMENTS_FILE="${FOCUS_DIR}/Blockzilla/Focus.entitlements"
echo "    Creating HealthKit entitlements file..."
cat > "${ENTITLEMENTS_FILE}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
	<key>com.apple.developer.healthkit.access</key>
	<array>
		<string>health-records</string>
	</array>
</dict>
</plist>
EOF

# ---------- 2d — Run the Ruby patcher ----------
PATCH_SCRIPT="${SCRIPT_DIR}/scripts/patch_xcodeproj.rb"
if [[ ! -f "${PATCH_SCRIPT}" ]]; then
  echo "ERROR: Ruby patch script not found at ${PATCH_SCRIPT}" >&2
  exit 1
fi

ruby "${PATCH_SCRIPT}" "${FOCUS_DIR}"

echo ""
echo "==> All done!"
echo "    Open Blockzilla.xcodeproj in Xcode and select:"
echo "      Scheme : Focus (Enterprise)"
echo "    Xcode will auto-manage signing under your team (${TEAM_ID})."
