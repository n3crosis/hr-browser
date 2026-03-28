#!/usr/bin/env bash
# =============================================================================
# apply-focus-enterprise.sh
#
# Configures the Firefox Focus iOS project to build the "Focus (Enterprise)"
# scheme under your own Apple Developer team with Xcode auto-managed signing.
#
# IMPORTANT: Run this after a fresh clone of the firefox-ios repo, or any time
# you need to re-apply the patches (e.g. after a upstream pull).
# This script modifies source files — do NOT commit the changes into the
# firefox-ios repo itself.
#
# Usage:
#   ./apply-focus-enterprise.sh
#
# Or supply values inline:
#   TEAM_ID=ABC123XYZ BUNDLE_ID=com.yourcompany.focus APP_NAME=sealion ./apply-focus-enterprise.sh
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

# URL shown as the tappable "Terms of Use" link on the onboarding TOS screen.
TERMS_URL="${TERMS_URL:-https://www.mozilla.org/about/legal/terms/firefox-focus/}"

# URL shown as the tappable "Privacy Notice" link on the onboarding TOS screen.
PRIVACY_URL="${PRIVACY_URL:-https://www.mozilla.org/privacy/firefox-focus/}"

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

echo "==> Applying Focus Enterprise patches"
echo "    Team ID    : ${TEAM_ID}"
echo "    Bundle ID  : ${BUNDLE_ID}"
echo "    App Name   : ${APP_NAME}"
echo "    Terms URL  : ${TERMS_URL}"
echo "    Privacy URL: ${PRIVACY_URL}"
echo "    Project    : ${FOCUS_DIR}"
echo ""

cd "${FOCUS_DIR}"

# -----------------------------------------------------------------------------
# Step 1 — Replace Mozilla's bundle identifiers with your own base bundle ID
#
# The project uses two base prefixes:
#   org.mozilla.ios.Focus  (Focus app and its extensions)
#   org.mozilla.ios.Klar   (Klar/German variant, shares the same Xcode targets)
# Both are replaced with ${BUNDLE_ID} so all configurations stay consistent.
# Suffixes like .ShareExtension, .ContentBlocker, etc. are preserved.
# -----------------------------------------------------------------------------
echo "--> [1/9] Replacing bundle identifiers..."
grep -rl "org\.mozilla\.ios\.Klar\|org\.mozilla\.ios\.Focus" . \
  | xargs sed -i '' \
      -e "s/org\.mozilla\.ios\.Klar/${BUNDLE_ID}/g" \
      -e "s/org\.mozilla\.ios\.Focus/${BUNDLE_ID}/g"

# -----------------------------------------------------------------------------
# Step 2 — Strip the .enterprise suffix from bundle identifiers
#
# The FocusEnterprise build configuration appends ".enterprise" to bundle IDs
# (e.g. org.mozilla.ios.Focus.enterprise → ${BUNDLE_ID}.enterprise).
# After Step 1 those become ${BUNDLE_ID}.enterprise[.SubTarget].
# We collapse them back to ${BUNDLE_ID}[.SubTarget] so Apple signing doesn't
# need a separate provisioning profile for the enterprise variant.
# -----------------------------------------------------------------------------
echo "--> [2/9] Stripping .enterprise suffix from bundle IDs..."
# Escape dots in BUNDLE_ID so they are treated as literal dots in the regex
BUNDLE_ID_ESC="${BUNDLE_ID//./\\.}"
grep -rl "${BUNDLE_ID_ESC}\.enterprise" . \
  | xargs sed -i '' "s/${BUNDLE_ID_ESC}\.enterprise/${BUNDLE_ID}/g"

# -----------------------------------------------------------------------------
# Step 3 — Inject your Development Team ID
#
# The project hard-codes Mozilla's team (43AQ936H96) in most build configs.
# The FocusEnterprise config has DEVELOPMENT_TEAM = "" (left intentionally
# blank for enterprise distribution — we fill it with your team instead).
# -----------------------------------------------------------------------------
echo "--> [3/9] Injecting development team ID (${TEAM_ID})..."

# 3a. Replace Mozilla's production team ID wherever it appears, and ensure
#     CODE_SIGN_STYLE = Automatic follows it (matches fix.sh behaviour).
grep -rl "43AQ936H96;" . \
  | xargs sed -i '' "s/43AQ936H96;/${TEAM_ID};\n\t\t\t\tCODE_SIGN_STYLE = Automatic;/g"

# 3b. Fill in blank DEVELOPMENT_TEAM entries used by the FocusEnterprise config.
sed -i '' "s/DEVELOPMENT_TEAM = \"\";/DEVELOPMENT_TEAM = ${TEAM_ID};/g" "${PBXPROJ}"

# 3c. Remove all platform-scoped DEVELOPMENT_TEAM overrides entirely.
# These were artifacts of manual signing ("DEVELOPMENT_TEAM[sdk=iphoneos*]" = X;)
# and are not needed — the top-level DEVELOPMENT_TEAM value covers auto signing.
sed -i '' '/"DEVELOPMENT_TEAM\[sdk=iphoneos\*\]"/d' "${PBXPROJ}"

# -----------------------------------------------------------------------------
# Step 4 — Remove all named provisioning profile specifiers
#
# Any named specifier ("bitrise ...", "BT ...", etc.) overrides
# CODE_SIGN_STYLE = Automatic and forces Xcode to look for a specific profile
# that doesn't exist in your environment. We also delete:
#   - Platform-scoped PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*] lines
#   - Platform-scoped CODE_SIGN_IDENTITY[sdk=iphoneos*] overrides ("iPhone
#     Distribution" etc.) which conflict with Automatic identity resolution
#   - Static PROVISIONING_PROFILE UUID lines left from CI
# -----------------------------------------------------------------------------
echo "--> [4/9] Removing all named provisioning profile specifiers..."
# Remove platform-scoped specifier lines
sed -i '' '/"PROVISIONING_PROFILE_SPECIFIER\[sdk=iphoneos\*\]"/d' "${PBXPROJ}"
# Remove top-level specifiers that have a non-empty value (e.g. "BT ...", "bitrise ...")
sed -i '' '/PROVISIONING_PROFILE_SPECIFIER = "[^"]/d' "${PBXPROJ}"
# Remove platform-scoped CODE_SIGN_IDENTITY overrides — not needed for auto signing
sed -i '' '/"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]"/d' "${PBXPROJ}"
# Remove static PROVISIONING_PROFILE UUID lines left from CI
sed -i '' '/PROVISIONING_PROFILE = "[0-9a-f-]*";/d' "${PBXPROJ}"

# -----------------------------------------------------------------------------
# Step 5 — Switch all targets to Xcode Automatic code signing
#
# Some configurations (especially the "BT" variants) are set to Manual.
# Automatic lets Xcode manage certificates and provisioning profiles for you.
# -----------------------------------------------------------------------------
echo "--> [5/9] Enabling automatic code signing everywhere..."
sed -i '' 's/CODE_SIGN_STYLE = Manual;/CODE_SIGN_STYLE = Automatic;/g' "${PBXPROJ}"

# -----------------------------------------------------------------------------
# Step 6 — Rename the app (DISPLAY_NAME and PRODUCT_NAME)
#
# The project ships with "Firefox Focus" and "Firefox Klar" as the visible
# app name in DISPLAY_NAME (shown on the home screen) and PRODUCT_NAME (used
# by Xcode for the built product). Both are replaced with APP_NAME so the
# installed app appears under your chosen name.
# -----------------------------------------------------------------------------
echo "--> [6/9] Renaming app to '${APP_NAME}'..."
sed -i '' \
  -e "s/DISPLAY_NAME = \"Firefox Focus\";/DISPLAY_NAME = ${APP_NAME};/g" \
  -e "s/DISPLAY_NAME = \"Firefox Klar\";/DISPLAY_NAME = ${APP_NAME};/g" \
  -e "s/PRODUCT_NAME = \"Firefox Focus\";/PRODUCT_NAME = ${APP_NAME};/g" \
  -e "s/PRODUCT_NAME = \"Firefox Klar\";/PRODUCT_NAME = ${APP_NAME};/g" \
  "${PBXPROJ}"

# -----------------------------------------------------------------------------
# Step 7 — Disable all telemetry and reporting (logic + UI)
#
# a) Settings.swift — hardcode toggle defaults to false so the features are
#    off even on a fresh install, regardless of user prefs stored on-device.
# b) TelemetryManager.swift — make isNewTosEnabled always return false so the
#    Glean daily-usage-reporting service never starts.
# c) SettingsViewController.swift — remove the rollouts, dailyUsagePing and
#    crashReports rows from getSections() so they never appear in the UI.
#    (usageData and studies are already hidden behind isTelemetryFeatureEnabled
#    which is already false upstream.)
# -----------------------------------------------------------------------------
echo "--> [7/9] Disabling all telemetry and reporting..."

SETTINGS_FILE="${FOCUS_DIR}/Shared/Settings.swift"
TELEMETRY_MANAGER="${FOCUS_DIR}/Blockzilla/Utilities/TelemetryManager.swift"
SETTINGS_VC="${FOCUS_DIR}/Blockzilla/Settings/Controller/SettingsViewController.swift"

# 7a — Hardcode telemetry toggle defaults to false
sed -i '' \
  -e 's/case \.sendAnonymousUsageData: return AppInfo\.isKlar ? false : true/case .sendAnonymousUsageData: return false/' \
  -e 's/case \.studies: return AppInfo\.isKlar ? false : true/case .studies: return false/' \
  -e 's/case \.rollouts: return AppInfo\.isKlar ? false : true/case .rollouts: return false/' \
  -e 's/case \.crashToggle: return true/case .crashToggle: return false/' \
  -e 's/case \.dailyUsagePing: return true/case .dailyUsagePing: return false/' \
  "${SETTINGS_FILE}"

# 7b — Make isNewTosEnabled always return false (multiline rewrite via Python)
python3 - "${TELEMETRY_MANAGER}" <<'PYEOF'
import sys, re
path = sys.argv[1]
src = open(path).read()
sentinel = 'if let dailyUsagePing = Settings.getToggleIfAvailable(.dailyUsagePing)'
if sentinel not in src:
    print(f'ERROR: 7b — expected block not found in {path}', file=sys.stderr)
    sys.exit(1)
new_src = re.sub(
    r'var isNewTosEnabled: Bool \{.*?\n    \}',
    'var isNewTosEnabled: Bool {\n        return false\n    }',
    src, flags=re.DOTALL
)
if new_src == src:
    print(f'ERROR: 7b — regex did not match in {path}', file=sys.stderr)
    sys.exit(1)
open(path, 'w').write(new_src)
PYEOF

# 7c — Remove telemetry rows from the Settings sections list
sed -i '' \
  -e '/^[[:space:]]*\.rollouts,[[:space:]]*$/d' \
  -e '/^[[:space:]]*\.dailyUsagePing,[[:space:]]*$/d' \
  -e '/^[[:space:]]*\.crashReports,[[:space:]]*$/d' \
  "${SETTINGS_VC}"

# -----------------------------------------------------------------------------
# Step 8 — Remove default browser onboarding page, Set as Default Browser
#          row in Settings, and Siri shortcuts row in Settings
#
# a) OnboardingView.swift — delete the DefaultBrowserOnboardingView tab so
#    the TabView only ever shows the TOS (or Get Started) page.
# b) OnboardingViewModel.swift — make "Agree and Continue" on the TOS page
#    call dismissAction() instead of navigating to the default-browser tab.
# c) SettingsViewController.swift — remove .defaultBrowser and .siri from
#    getSections() so those rows are never rendered.
# -----------------------------------------------------------------------------
echo "--> [8/9] Removing default browser prompts and Siri shortcuts..."

ONBOARDING_DIR="${FOCUS_DIR}/BlockzillaPackage/Sources/Onboarding/SwiftUI Onboarding"
ONBOARDING_VIEW="${ONBOARDING_DIR}/OnboardingView.swift"
ONBOARDING_VM="${ONBOARDING_DIR}/OnboardingViewModel.swift"

# 8a — Drop the DefaultBrowserOnboardingView tab from the TabView
python3 - "${ONBOARDING_VIEW}" <<'PYEOF'
import sys, re
path = sys.argv[1]
src = open(path).read()
sentinel = 'DefaultBrowserOnboardingView(viewModel: viewModel)'
if sentinel not in src:
    print(f'ERROR: 8a — DefaultBrowserOnboardingView not found in {path}', file=sys.stderr)
    sys.exit(1)
new_src = re.sub(
    r'\s+DefaultBrowserOnboardingView\(viewModel: viewModel\)\s+\.tag\(Screen\.default\)',
    '',
    src
)
if new_src == src:
    print(f'ERROR: 8a — regex did not match in {path}', file=sys.stderr)
    sys.exit(1)
open(path, 'w').write(new_src)
PYEOF

# 8b — Make TOS "Agree and Continue" dismiss onboarding rather than open the
#      default-browser tab
python3 - "${ONBOARDING_VM}" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
old = 'case .onAcceptAndContinueTapped:\n            activeScreen = .default'
if old not in src:
    print(f'ERROR: 8b — onAcceptAndContinueTapped pattern not found in {path}', file=sys.stderr)
    sys.exit(1)
new_src = src.replace(old, 'case .onAcceptAndContinueTapped:\n            dismissAction()', 1)
open(path, 'w').write(new_src)
PYEOF

# 8c — Remove .defaultBrowser and .siri sections from the Settings screen
sed -i '' \
  -e '/^[[:space:]]*\.defaultBrowser,[[:space:]]*$/d' \
  -e '/^[[:space:]]*\.siri,[[:space:]]*$/d' \
  "${SETTINGS_VC}"

# 8d — Rebrand "Firefox" mentions in the onboarding TOS text strings
#      so link labels and the privacy sentence don't reference Firefox.
ONBOARDING_FACTORY="${FOCUS_DIR}/Blockzilla/Onboarding/OnboardingFactory.swift"
sed -i '' \
  -e "s/value: \"Firefox Terms of Use\"/value: \"${APP_NAME} Terms of Use\"/" \
  -e "s/value: \"Firefox cares about your privacy\. Read more in %@\.\"/value: \"${APP_NAME} cares about your privacy. Read more in %@.\"/" \
  "${ONBOARDING_FACTORY}"

# 8e — Swap the hardcoded Mozilla legal URLs for the configurable ones.
# Use | as sed delimiter so / inside URLs doesn't need escaping.
# Also escape any | that might appear in the URL values themselves.
TERMS_URL_ESC="${TERMS_URL//|/\\|}"
PRIVACY_URL_ESC="${PRIVACY_URL//|/\\|}"
sed -i '' \
  -e "s|https://www\.mozilla\.org/about/legal/terms/firefox-focus/|${TERMS_URL_ESC}|" \
  -e "s|https://www\.mozilla\.org/privacy/firefox-focus/|${PRIVACY_URL_ESC}|" \
  "${ONBOARDING_FACTORY}"

# -----------------------------------------------------------------------------
# Step 9 — Remove Safari Integration section, rename Mozilla section header,
#           remove Help row from the About page, remove aboutTopLabel text,
#           and patch the Terms/Privacy URLs inside AboutViewController.
#
# a) SettingsViewController.swift — delete the `integration` (Safari) entry
#    from getSections() so the Safari toggle never appears.
# b) UIConstants.swift — replace the hardcoded string "MOZILLA" with the
#    uppercased APP_NAME so the settings section header reads e.g. "SEALION".
# c) AboutViewController.swift (Python, with sentinels) —
#    - Remove the Help row (row 0) from configureCell and categoryUrl
#    - Shift Terms → row 0 / Privacy → row 1; inject TERMS_URL / PRIVACY_URL
#    - Reduce numberOfRows for .aboutCategories from 3 to 2
#    - Remove the aboutTopLabel paragraph line from AboutHeaderView
# -----------------------------------------------------------------------------
echo "--> [9/9] Cleaning up Safari, Mozilla branding, and About page..."

UI_CONSTANTS="${FOCUS_DIR}/Blockzilla/UIComponents/UIConstants.swift"
ABOUT_VC="${FOCUS_DIR}/Blockzilla/Settings/Controller/AboutViewController.swift"

# 9a — Remove Safari Integration row from Settings
sed -i '' -e '/^[[:space:]]*integration,[[:space:]]*$/d' "${SETTINGS_VC}"

# 9b — Rename "MOZILLA" section header to uppercased APP_NAME
APP_NAME_UPPER=$(echo "${APP_NAME}" | tr '[:lower:]' '[:upper:]')
sed -i '' "s/value: \"MOZILLA\"/value: \"${APP_NAME_UPPER}\"/" "${UI_CONSTANTS}"

# 9c — Rewrite AboutViewController
python3 - "${ABOUT_VC}" "${TERMS_URL}" "${PRIVACY_URL}" <<'PYEOF'
import sys, re

path, terms_url, privacy_url = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()

# --- 9c-i: numberOfRows 3 → 2 for .aboutCategories ---
pat_rows = r'(case \.aboutCategories:\s+return )3'
if not re.search(pat_rows, src):
    print(f'ERROR: 9c-i — numberOfRows pattern not found in {path}', file=sys.stderr)
    sys.exit(1)
new_src = re.sub(pat_rows, r'\g<1>2', src, count=1)
if new_src == src:
    print(f'ERROR: 9c-i — numberOfRows substitution had no effect', file=sys.stderr)
    sys.exit(1)
src = new_src

# --- 9c-ii: configureCell — remove Help (case 0), shift Terms/Privacy ---
pat_cells = (
    r'(case 0: cell\.textLabel\?\.text = UIConstants\.strings\.aboutRowHelp\n'
    r')(\s+)(case 1: cell\.textLabel\?\.text = UIConstants\.strings\.aboutRowTerms\n'
    r'\3case 2: cell\.textLabel\?\.text = UIConstants\.strings\.aboutRowPrivacy)'
)
m = re.search(pat_cells, src)
if not m:
    print(f'ERROR: 9c-ii — configureCell rows not found in {path}', file=sys.stderr)
    sys.exit(1)
indent = m.group(3)  # leading whitespace of case 1 / case 2 lines
new_cells = (
    f'case 0: cell.textLabel?.text = UIConstants.strings.aboutRowTerms\n'
    f'{indent}case 1: cell.textLabel?.text = UIConstants.strings.aboutRowPrivacy'
)
src = src[:m.start()] + new_cells + src[m.end():]

# --- 9c-iii: categoryUrl — remove Help case, update Terms/Privacy URLs ---
# Remove the Help (support.mozilla.org) case block entirely
pat_help = r'\s+case 0:\s+return URL\(string: "https://support\.mozilla\.org[^"]+",\s+invalidCharacters: false\)'
m_help = re.search(pat_help, src, re.DOTALL)
if not m_help:
    print(f'ERROR: 9c-iii — Help URL case not found in {path}', file=sys.stderr)
    sys.exit(1)
src = src[:m_help.start()] + src[m_help.end():]

# Shift old case 1 (Terms) → case 0, inject TERMS_URL
pat_terms = r'case 1:(\s+return URL\(string: )"https://www\.mozilla\.org/about/legal/terms/firefox-focus/"'
m_terms = re.search(pat_terms, src)
if not m_terms:
    print(f'ERROR: 9c-iii — Terms URL case not found in {path}', file=sys.stderr)
    sys.exit(1)
src = src[:m_terms.start()] + f'case 0:{m_terms.group(1)}"{terms_url}"' + src[m_terms.end():]

# Shift old case 2 (Privacy) → case 1, inject PRIVACY_URL
# Note: upstream URL has no trailing slash, match loosely
pat_privacy = r'case 2:(\s+return URL\(string: )"https://www\.mozilla\.org/privacy/firefox-focus[/]?"'
m_privacy = re.search(pat_privacy, src)
if not m_privacy:
    print(f'ERROR: 9c-iii — Privacy URL case not found in {path}', file=sys.stderr)
    sys.exit(1)
src = src[:m_privacy.start()] + f'case 1:{m_privacy.group(1)}"{privacy_url}"' + src[m_privacy.end():]

# --- 9c-iv: remove aboutTopLabel line from AboutHeaderView ---
pat_top = r'\n\s+NSAttributedString\(string: String\(format: UIConstants\.strings\.aboutTopLabel, AppInfo\.productName\) \+ "\\n\\n"\),'
m_top = re.search(pat_top, src)
if not m_top:
    print(f'ERROR: 9c-iv — aboutTopLabel line not found in {path}', file=sys.stderr)
    sys.exit(1)
src = src[:m_top.start()] + src[m_top.end():]

open(path, 'w').write(src)
print(f'OK: AboutViewController patched successfully.')
PYEOF

echo ""
echo "==> All done!"
echo "    Open Blockzilla.xcodeproj in Xcode and select:"
echo "      Scheme : Focus (Enterprise)"
echo "    Xcode will auto-manage signing under your team (${TEAM_ID})."
