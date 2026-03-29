#!/usr/bin/env bash
# =============================================================================
# step1-patch.sh
#
# Configures the Firefox Focus iOS project to build the "Focus (Enterprise)"
# scheme under your own Apple Developer team with Xcode auto-managed signing.
#
# IMPORTANT: Run this after a fresh clone of the firefox-ios repo, or any time
# you need to re-apply the patches (e.g. after a upstream pull).
# This script modifies source files — do NOT commit the changes into the
# firefox-ios repo itself.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration — edit these defaults or override via environment variables
# -----------------------------------------------------------------------------

# Your 10-character Apple Developer Team ID (found in developer.apple.com)
TEAM_ID="${TEAM_ID:-VRZ2JHMMCJ}"

# Base bundle identifier for the app.
# Sub-targets (ShareExtension, ContentBlocker, etc.) will append their suffix.
BUNDLE_ID="${BUNDLE_ID:-co.techbeast.ios.Klar}"

# App display name shown on the home screen and in Xcode's PRODUCT_NAME /
# DISPLAY_NAME build settings. Replaces "Firefox Focus" and "Firefox Klar".
APP_NAME="${APP_NAME:-Sealion}"

# Export so child processes can read them via ProcessInfo/ENV.
export TEAM_ID APP_NAME

# URL shown as the tappable "Terms of Use" link on the onboarding TOS screen.
TERMS_URL="${TERMS_URL:-https://google.com/}"

# URL shown as the tappable "Privacy Notice" link on the onboarding TOS screen.
PRIVACY_URL="${PRIVACY_URL:-https://bing.com/}"

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

echo "==> Step 1: Applying Focus Enterprise patches"
echo "    Team ID    : ${TEAM_ID}"
echo "    Bundle ID  : ${BUNDLE_ID}"
echo "    App Name   : ${APP_NAME}"
echo "    Terms URL  : ${TERMS_URL}"
echo "    Privacy URL: ${PRIVACY_URL}"
echo "    Project    : ${FOCUS_DIR}"
echo ""

cd "${FOCUS_DIR}"

# -----------------------------------------------------------------------------
# Step 0 — Remove non-English localizations to speed up build and patching
# -----------------------------------------------------------------------------
# echo "--> [0/7] Removing non-English localizations..."
# find . -type d -name "*.lproj" ! -name "en.lproj" ! -name "Base.lproj" -exec rm -rf {} +

# -----------------------------------------------------------------------------
# Step 1 — Replace Mozilla's bundle identifiers with your own base bundle ID
# -----------------------------------------------------------------------------
echo "--> [1/6] Replacing bundle identifiers..."
grep -rl "org\.mozilla\.ios\.Klar\|org\.mozilla\.ios\.Focus" . | xargs sed -i '' \
      -e "s/org\.mozilla\.ios\.Klar/${BUNDLE_ID}/g" \
      -e "s/org\.mozilla\.ios\.Focus/${BUNDLE_ID}/g" || true

# -----------------------------------------------------------------------------
# Step 2 — Strip the .enterprise suffix from bundle identifiers
# -----------------------------------------------------------------------------
echo "--> [2/6] Stripping .enterprise suffix from bundle IDs..."
BUNDLE_ID_ESC="${BUNDLE_ID//./\\.}"
grep -rl "${BUNDLE_ID_ESC}\.enterprise" . \
  | xargs sed -i '' "s/${BUNDLE_ID_ESC}\.enterprise/${BUNDLE_ID}/g" || true

# -----------------------------------------------------------------------------
# Step 3 — Replace the old Mozilla team ID in non-project files
# -----------------------------------------------------------------------------
echo "--> [3/6] Replacing old Mozilla team ID across all source files..."
grep -rl "43AQ936H96" . \
  | xargs sed -i '' "s/43AQ936H96/${TEAM_ID}/g" || true

# -----------------------------------------------------------------------------
# Step 4 — Disable all telemetry and reporting (logic + UI)
# -----------------------------------------------------------------------------
echo "--> [4/6] Disabling all telemetry and reporting..."

SETTINGS_VC="${FOCUS_DIR}/Blockzilla/Settings/Controller/SettingsViewController.swift"
APP_DELEGATE="${FOCUS_DIR}/Blockzilla/AppDelegate.swift"

# 4a — Remove telemetry setup calls from AppDelegate
sed -i '' \
  -e '/^[[:space:]]*setupCrashReporting()/d' \
  -e '/^[[:space:]]*setupTelemetry()/d' \
  -e '/^[[:space:]]*setupExperimentation()/d' \
  "${APP_DELEGATE}"

# 4c — Remove telemetry rows from the Settings sections list
sed -i '' \
  -e '/^[[:space:]]*\.rollouts,[[:space:]]*$/d' \
  -e '/^[[:space:]]*\.dailyUsagePing,[[:space:]]*$/d' \
  -e '/^[[:space:]]*\.crashReports,[[:space:]]*$/d' \
  "${SETTINGS_VC}"

# -----------------------------------------------------------------------------
# Step 5 — Remove default browser onboarding page, Set as Default Browser
# -----------------------------------------------------------------------------
echo "--> [5/6] Removing default browser prompts and Siri shortcuts..."

ONBOARDING_DIR="${FOCUS_DIR}/BlockzillaPackage/Sources/Onboarding/SwiftUI Onboarding"
ONBOARDING_VIEW="${ONBOARDING_DIR}/OnboardingView.swift"
ONBOARDING_VM="${ONBOARDING_DIR}/OnboardingViewModel.swift"

# 5a — Drop the DefaultBrowserOnboardingView tab from the TabView
# python3 - "${ONBOARDING_VIEW}" <<'PYEOF'
# import sys, re
# path = sys.argv[1]
# src = open(path).read()
# sentinel = 'DefaultBrowserOnboardingView(viewModel: viewModel)'
# if sentinel not in src:
#   print(f'WARN: 5a — DefaultBrowserOnboardingView not found in {path}', file=sys.stderr)
# else:
#   new_src = re.sub(
#     r'\s+DefaultBrowserOnboardingView\(viewModel: viewModel\)\s+\.tag\(Screen\.default\)',
#     '',
#     src
#   )
#   if new_src == src:
#     print(f'WARN: 5a — regex did not match in {path}', file=sys.stderr)
#   else:
#     open(path, 'w').write(new_src)
# PYEOF

# 5b — Make TOS "Agree and Continue" dismiss onboarding
# python3 - "${ONBOARDING_VM}" <<'PYEOF'
# import sys
# path = sys.argv[1]
# src = open(path).read()
# old = 'case .onAcceptAndContinueTapped:\n            activeScreen = .default'
# if old not in src:
#   print(f'WARN: 5b — onAcceptAndContinueTapped pattern not found in {path}', file=sys.stderr)
# else:
#   new_src = src.replace(old, 'case .onAcceptAndContinueTapped:\n            dismissAction()', 1)
#   open(path, 'w').write(new_src)
# PYEOF

# 5c — Remove .defaultBrowser and .siri sections from the Settings screen
sed -i '' \
  -e '/^[[:space:]]*\.defaultBrowser,[[:space:]]*$/d' \
  -e '/^[[:space:]]*\.siri,[[:space:]]*$/d' \
  "${SETTINGS_VC}"

# 5d — Rebrand "Firefox" mentions in the onboarding TOS text strings
ONBOARDING_FACTORY="${FOCUS_DIR}/Blockzilla/Onboarding/OnboardingFactory.swift"
sed -i '' \
  -e "s/value: \"Firefox Terms of Use\"/value: \"${APP_NAME} Terms of Use\"/" \
  -e "s/value: \"Firefox cares about your privacy\. Read more in %@\.\"/value: \"${APP_NAME} cares about your privacy. Read more in %@.\"/" \
  "${ONBOARDING_FACTORY}"

# 5e — Swap the hardcoded Mozilla legal URLs
TERMS_URL_ESC="${TERMS_URL//|/\\|}"
PRIVACY_URL_ESC="${PRIVACY_URL//|/\\|}"
sed -i '' \
  -e "s|https://www\.mozilla\.org/about/legal/terms/firefox-focus/|${TERMS_URL_ESC}|" \
  -e "s|https://www\.mozilla\.org/privacy/firefox-focus/|${PRIVACY_URL_ESC}|" \
  "${ONBOARDING_FACTORY}"

# -----------------------------------------------------------------------------
# Step 6 — Remove Safari Integration section, rename Mozilla section header
# -----------------------------------------------------------------------------
echo "--> [6/6] Cleaning up Safari, Mozilla branding, and About page..."

APP_NAME_UPPER="$(echo "${APP_NAME}" | tr '[:lower:]' '[:upper:]')"

# 6a — Remove Safari Integration row from Settings
sed -i '' -e '/^[[:space:]]*integration,[[:space:]]*$/d' "${SETTINGS_VC}"

# 6b — Rename "MOZILLA" section header to uppercased APP_NAME
find "${FOCUS_DIR}/Blockzilla" -type d \( -name "en.lproj" -o -name "Base.lproj" \) -exec \
  grep -rl '"Settings\.sectionMozilla"' {} + \
  | xargs sed -i '' "s/\(\"Settings\.sectionMozilla\" = \"\)[^\"]*\"/\1${APP_NAME_UPPER}\"/g"

# 6c — Rename PRODUCT_NAME and DISPLAY_NAME in Xcode project
sed -i '' \
  -e "s/PRODUCT_NAME = \"Firefox Focus\"/PRODUCT_NAME = \"${APP_NAME}\"/g" \
  -e "s/PRODUCT_NAME = \"Firefox Klar\"/PRODUCT_NAME = \"${APP_NAME}\"/g" \
  -e "s/DISPLAY_NAME = \"Firefox Focus\"/DISPLAY_NAME = \"${APP_NAME}\"/g" \
  -e "s/DISPLAY_NAME = \"Firefox Klar\"/DISPLAY_NAME = \"${APP_NAME}\"/g" \
  "${PBXPROJ}" || true

echo "==> Step 1 completed successfully."

# -----------------------------------------------------------------------------
# Step 7 — Clear provisioning profile specifiers to allow Xcode auto-signing
# -----------------------------------------------------------------------------
echo "--> [7/6] Clearing provisioning profile entries in ${PBXPROJ} to enable automatic signing..."
# Remove explicit provisioning profile keys (both UUID and specifier variants)
sed -i '' \
  -e '/PROVISIONING_PROFILE =/d' \
  -e '/PROVISIONING_PROFILE_SPECIFIER/d' \
  "${PBXPROJ}" || true

# Ensure the DEVELOPMENT_TEAM is set to the provided TEAM_ID
sed -i '' -E "s/(DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*).*/\1${TEAM_ID};/g" "${PBXPROJ}" || true

# Force CODE_SIGN_STYLE to Automatic where it may be set to Manual
sed -i '' -E "s/(CODE_SIGN_STYLE[[:space:]]*=[[:space:]]*)Manual;/\1Automatic;/g" "${PBXPROJ}" || true

echo "--> Provisioning profile entries cleared. Run step2-inject.sh to finalize Xcode project modifications."
