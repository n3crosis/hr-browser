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

SETTINGS_FILE="${FOCUS_DIR}/Shared/Settings.swift"
TELEMETRY_MANAGER="${FOCUS_DIR}/Blockzilla/Utilities/TelemetryManager.swift"
SETTINGS_VC="${FOCUS_DIR}/Blockzilla/Settings/Controller/SettingsViewController.swift"

# 4a — Hardcode telemetry toggle defaults to false
sed -i '' \
  -e 's/case \.sendAnonymousUsageData: return AppInfo\.isKlar ? false : true/case .sendAnonymousUsageData: return false/' \
  -e 's/case \.studies: return AppInfo\.isKlar ? false : true/case .studies: return false/' \
  -e 's/case \.rollouts: return AppInfo\.isKlar ? false : true/case .rollouts: return false/' \
  -e 's/case \.crashToggle: return true/case .crashToggle: return false/' \
  -e 's/case \.dailyUsagePing: return true/case .dailyUsagePing: return false/' \
  "${SETTINGS_FILE}"

# 4b — Make isNewTosEnabled always return false (multiline rewrite via Python)
python3 - "${TELEMETRY_MANAGER}" <<'PYEOF'
import sys, re
path = sys.argv[1]
src = open(path).read()
sentinel = 'if let dailyUsagePing = Settings.getToggleIfAvailable(.dailyUsagePing)'
if sentinel not in src:
    print(f'ERROR: 4b — expected block not found in {path}', file=sys.stderr)
    sys.exit(1)
new_src = re.sub(
    r'var isNewTosEnabled: Bool \{.*?\n    \}',
    'var isNewTosEnabled: Bool {\n        return false\n    }',
    src, flags=re.DOTALL
)
if new_src == src:
    print(f'ERROR: 4b — regex did not match in {path}', file=sys.stderr)
    sys.exit(1)
open(path, 'w').write(new_src)
PYEOF

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
python3 - "${ONBOARDING_VIEW}" <<'PYEOF'
import sys, re
path = sys.argv[1]
src = open(path).read()
sentinel = 'DefaultBrowserOnboardingView(viewModel: viewModel)'
if sentinel not in src:
    print(f'ERROR: 5a — DefaultBrowserOnboardingView not found in {path}', file=sys.stderr)
    sys.exit(1)
new_src = re.sub(
    r'\s+DefaultBrowserOnboardingView\(viewModel: viewModel\)\s+\.tag\(Screen\.default\)',
    '',
    src
)
if new_src == src:
    print(f'ERROR: 5a — regex did not match in {path}', file=sys.stderr)
    sys.exit(1)
open(path, 'w').write(new_src)
PYEOF

# 5b — Make TOS "Agree and Continue" dismiss onboarding
python3 - "${ONBOARDING_VM}" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
old = 'case .onAcceptAndContinueTapped:\n            activeScreen = .default'
if old not in src:
    print(f'ERROR: 5b — onAcceptAndContinueTapped pattern not found in {path}', file=sys.stderr)
    sys.exit(1)
new_src = src.replace(old, 'case .onAcceptAndContinueTapped:\n            dismissAction()', 1)
open(path, 'w').write(new_src)
PYEOF

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

UI_CONSTANTS="${FOCUS_DIR}/Blockzilla/UIComponents/UIConstants.swift"
ABOUT_VC="${FOCUS_DIR}/Blockzilla/Settings/Controller/AboutViewController.swift"

# 6a — Remove Safari Integration row from Settings
sed -i '' -e '/^[[:space:]]*integration,[[:space:]]*$/d' "${SETTINGS_VC}"

# 6b — Rename "MOZILLA" section header to uppercased APP_NAME
APP_NAME_UPPER=$(echo "${APP_NAME}" | tr '[:lower:]' '[:upper:]')
sed -i '' "s/value: \"MOZILLA\"/value: \"${APP_NAME_UPPER}\"/" "${UI_CONSTANTS}"

find "${FOCUS_DIR}/Blockzilla" -type d \( -name "en.lproj" -o -name "Base.lproj" \) -exec \
  grep -rl '"Settings\.sectionMozilla"' {} + \
  | xargs sed -i '' "s/\(\"Settings\.sectionMozilla\" = \"\)[^\"]*\"/\1${APP_NAME_UPPER}\"/g"

# 6c — Rewrite AboutViewController
python3 - "${ABOUT_VC}" "${TERMS_URL}" "${PRIVACY_URL}" <<'PYEOF'
import sys, re

path, terms_url, privacy_url = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()

# --- 6c-i: numberOfRows 3 → 2 for .aboutCategories ---
pat_rows = r'(case \.aboutCategories:\s+return )3'
if not re.search(pat_rows, src):
    print(f'ERROR: 6c-i — numberOfRows pattern not found in {path}', file=sys.stderr)
    sys.exit(1)
new_src = re.sub(pat_rows, r'\g<1>2', src, count=1)
if new_src == src:
    print(f'ERROR: 6c-i — numberOfRows substitution had no effect', file=sys.stderr)
    sys.exit(1)
src = new_src

# --- 6c-ii: configureCell — remove Help (case 0), shift Terms/Privacy ---
pat_cells = (
    r'(case 0: cell\.textLabel\?\.text = UIConstants\.strings\.aboutRowHelp\n'
    r')(\s+)(case 1: cell\.textLabel\?\.text = UIConstants\.strings\.aboutRowTerms\n'
    r'\s+case 2: cell\.textLabel\?\.text = UIConstants\.strings\.aboutRowPrivacy)'
)
m = re.search(pat_cells, src)
if not m:
    print(f'ERROR: 6c-ii — configureCell rows not found in {path}', file=sys.stderr)
    sys.exit(1)
indent = m.group(2)
new_cells = (
    f'case 0: cell.textLabel?.text = UIConstants.strings.aboutRowTerms\n'
    f'{indent}case 1: cell.textLabel?.text = UIConstants.strings.aboutRowPrivacy'
)
src = src[:m.start()] + new_cells + src[m.end():]

# --- 6c-iii: categoryUrl — remove Help case, update Terms/Privacy URLs ---
pat_help = r'\s+case 0:\s+return URL\(string: "https://support\.mozilla\.org[^"]+",\s+invalidCharacters: false\)'
m_help = re.search(pat_help, src, re.DOTALL)
if not m_help:
    print(f'ERROR: 6c-iii — Help URL case not found in {path}', file=sys.stderr)
    sys.exit(1)
src = src[:m_help.start()] + src[m_help.end():]

pat_terms = r'case 1:(\s+return URL\(string: )"https://www\.mozilla\.org/about/legal/terms/firefox-focus/"'
m_terms = re.search(pat_terms, src)
if not m_terms:
    print(f'ERROR: 6c-iii — Terms URL case not found in {path}', file=sys.stderr)
    sys.exit(1)
src = src[:m_terms.start()] + f'case 0:{m_terms.group(1)}"{terms_url}"' + src[m_terms.end():]

pat_privacy = r'case 2:(\s+return URL\(string: )"https://www\.mozilla\.org/privacy/firefox-focus[/]?"'
m_privacy = re.search(pat_privacy, src)
if not m_privacy:
    print(f'ERROR: 6c-iii — Privacy URL case not found in {path}', file=sys.stderr)
    sys.exit(1)
src = src[:m_privacy.start()] + f'case 1:{m_privacy.group(1)}"{privacy_url}"' + src[m_privacy.end():]

# --- 6c-iv: remove aboutTopLabel line from AboutHeaderView ---
pat_top = r'\n\s+NSAttributedString\(string: String\(format: UIConstants\.strings\.aboutTopLabel, AppInfo\.productName\) \+ "\\n\\n"\),'
m_top = re.search(pat_top, src)
if not m_top:
    print(f'ERROR: 6c-iv — aboutTopLabel line not found in {path}', file=sys.stderr)
    sys.exit(1)
src = src[:m_top.start()] + src[m_top.end():]

open(path, 'w').write(src)
print(f'OK: AboutViewController patched successfully.')
PYEOF

echo "==> Step 1 completed successfully."
