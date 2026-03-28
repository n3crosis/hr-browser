# hr-browser

A patching harness for building a custom-branded Firefox Focus iOS app under your
own Apple Developer account — without forking the upstream repository.

All modifications are applied at run-time by `apply-focus-enterprise.sh` against a
fresh (or re-pulled) clone of `firefox-ios`. The upstream folder is never committed.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| macOS with Xcode 15+ | Install from the App Store |
| Apple Developer account | Free account works for device testing; paid required for distribution |
| Xcode Command Line Tools | `xcode-select --install` |
| Homebrew | https://brew.sh |
| Python 3 | Ships with macOS; also `brew install python` |

You do **not** need to install Rust, Node, or any Focus-specific toolchain to apply
the patches — those are only needed when building the project itself.

---

## Repository layout

```
apply-focus-enterprise.sh   ← the patch script (tracked here)
README.md                   ← this file
firefox-ios/                ← upstream clone (gitignored, managed manually)
  focus-ios/                ← Focus source root targeted by the script
```

---

## First-time setup

### 1. Clone this repo

```bash
git clone git@github.com:n3crosis/hr-browser.git
cd hr-browser
```

### 2. Clone the upstream Firefox iOS repo alongside the script

The script expects `firefox-ios/` to live **next to** `apply-focus-enterprise.sh`.

```bash
git clone https://github.com/mozilla-mobile/firefox-ios.git firefox-ios
```

> Tip: the upstream repo is large (~2 GB). A shallow clone speeds things up but may
> miss tags needed by the build system:
> ```bash
> git clone --depth 1 https://github.com/mozilla-mobile/firefox-ios.git firefox-ios
> ```

### 3. Bootstrap the upstream project dependencies

```bash
cd firefox-ios/focus-ios
sh bootstrap.sh
cd ../..
```

This installs Ruby gems (Fastlane, etc.) and fetches Swift Package dependencies.
It only needs to be run once per upstream clone.

---

## Applying the patches

```bash
./apply-focus-enterprise.sh
```

Or supply overrides inline:

```bash
TEAM_ID=ABC123XYZ \
BUNDLE_ID=com.yourcompany.focus \
APP_NAME=Sealion \
TERMS_URL=https://example.com/terms \
PRIVACY_URL=https://example.com/privacy \
./apply-focus-enterprise.sh
```

### Configuration variables

| Variable | Default | Description |
|---|---|---|
| `TEAM_ID` | `VRZ2JHMMCJ` | Your 10-character Apple Developer Team ID (find it at [developer.apple.com](https://developer.apple.com/account)) |
| `BUNDLE_ID` | `co.techbeast.ios.Klar` | Base bundle identifier — extensions append their own suffix automatically |
| `APP_NAME` | `Sealion` | Display name shown on the home screen and in Xcode build settings |
| `TERMS_URL` | Mozilla Terms URL | URL opened when the user taps "Terms of Use" in onboarding |
| `PRIVACY_URL` | Mozilla Privacy URL | URL opened when the user taps "Privacy Notice" in onboarding |

---

## What the script does

| Step | Action |
|---|---|
| 1 | Replaces `org.mozilla.ios.Focus` / `org.mozilla.ios.Klar` bundle IDs with `BUNDLE_ID` across the entire project |
| 2 | Strips the `.enterprise` suffix from any bundle IDs that carry it |
| 3 | Injects `TEAM_ID` into every `DEVELOPMENT_TEAM` build setting |
| 4 | Removes all named provisioning profile specifiers (lets Xcode manage them) |
| 5 | Switches every target to `CODE_SIGN_STYLE = Automatic` |
| 6 | Renames `PRODUCT_NAME` / `DISPLAY_NAME` from "Firefox Focus" / "Firefox Klar" to `APP_NAME` |
| 7 | Disables telemetry: turns off daily usage ping, rollouts, and crash reports both in code and UI |
| 8 | Removes default browser and Siri onboarding; rebrands Terms/Privacy links and URLs |
| 9 | Removes Safari Integration settings section; renames the "MOZILLA" settings header to `APP_NAME`; removes the Help row and top label from the About page; patches Terms/Privacy URLs in About |

The script is **idempotent** — you can re-run it after pulling upstream changes to
re-apply all patches.

---

## Building in Xcode

1. Open `firefox-ios/focus-ios/Blockzilla.xcodeproj`
2. Select the **Focus (Enterprise)** scheme
3. Choose your device or simulator
4. Press **Run** — Xcode will automatically manage signing with your team

If Xcode shows a signing error on first open, go to each target's **Signing &
Capabilities** tab and confirm your team is selected.

---

## Re-applying after an upstream pull

```bash
cd firefox-ios
git pull
cd ..
./apply-focus-enterprise.sh
```

Because the script patches from scratch each time, you may need to re-run
`bootstrap.sh` inside `focus-ios/` if the upstream introduced new dependencies.

---

## Troubleshooting

**`ERROR: Cannot find project file`**  
The `firefox-ios/` directory is missing or not cloned at the right path. See step 2 above.

**Script exits with `ERROR: ... pattern not found`**  
An upstream change moved or renamed code the script targets. Open the referenced file
and update the corresponding sed/Python pattern in `apply-focus-enterprise.sh`.

**Xcode can't resolve Swift packages**  
Run `bootstrap.sh` from inside `firefox-ios/focus-ios/` and let it complete fully
before opening the project.
