# Tapjack PoC

An Android app for checking, at runtime, whether a target app's tapjacking mitigations are actually in place, without reverse-engineering or statically analysing the target.

It draws a configurable overlay over any app. It can add decoy labels and buttons at exact screen coordinates. It also logs, through an accessibility service, which clicks actually reach the target while the overlay covers it.

> For authorized security assessments only.

---

## Table of contents

1. [Background](#background)
2. [What counts as a finding](#what-counts-as-a-finding)
3. [Features](#features)
4. [Requirements](#requirements)
5. [Build](#build)
6. [Install and setup](#install-and-setup)
7. [Usage: in-app UI](#usage-in-app-ui)
8. [Usage: adb](#usage-adb)
9. [Intent extras reference](#intent-extras-reference)
10. [Decoy elements](#decoy-elements)
11. [Tap logger](#tap-logger)
12. [Testing methodology](#testing-methodology)
13. [Interpreting results](#interpreting-results)
14. [Reporting notes](#reporting-notes)
15. [Troubleshooting](#troubleshooting)
16. [Limitations](#limitations)
17. [Project structure](#project-structure)

---

## Background

Any app granted `SYSTEM_ALERT_WINDOW` ("Display over other apps") can draw a `TYPE_APPLICATION_OVERLAY` window over any other app. If that window has `FLAG_NOT_TOUCHABLE`, touches go through it to the app underneath. The user sees the overlay's content while actually interacting with the hidden UI.

When Android delivers a touch that passed through a window owned by a different UID, it marks the `MotionEvent`:

| Flag | Set when | API |
|---|---|---|
| `FLAG_WINDOW_IS_OBSCURED` | The touch point lies inside a visible window owned by another UID | 9+ |
| `FLAG_WINDOW_IS_PARTIALLY_OBSCURED` | Part of the receiving window is obscured, but not at the touch point | 29+ |

Apps defend themselves by inspecting these flags:

| Mitigation | Covers |
|---|---|
| `android:filterTouchesWhenObscured="true"` / `View.setFilterTouchesWhenObscured(true)` | `IS_OBSCURED` only |
| Overriding `View.onFilterTouchEventForSecurity()` | Whatever the override checks (it can also reject `IS_PARTIALLY_OBSCURED`) |
| Manual flag check in `onTouchEvent` / `dispatchTouchEvent` / Compose `pointerInteropFilter` | Whatever is checked |
| `Window.setHideOverlayWindows(true)` + `HIDE_OVERLAY_WINDOWS` permission | Hides all non-system app overlays while the window is shown (API 31+) |

Android 12 (API 31) also added OS-level **untrusted touch blocking**: touches through windows from other UIDs are dropped, except for `TYPE_APPLICATION_OVERLAY` windows whose combined obscuring opacity is **≤ 0.8**. A translucent overlay at alpha ≤ 0.8 is therefore still allowed through on every Android version, and the app has to protect itself.

## What counts as a finding

**An overlay that renders over the target is not a vulnerability.** Any app with the permission can do that, and the target can't prevent it (except with `setHideOverlayWindows`).

**The finding:** while the overlay (alpha ≤ 0.8) covers a sensitive control, a tap on it is still delivered and the action executes. That means the target ignores `FLAG_WINDOW_IS_OBSCURED` / `FLAG_WINDOW_IS_PARTIALLY_OBSCURED` for that control.

## Features

| Feature | Description |
|---|---|
| Full overlay | Full-screen translucent window, touches pass through |
| Partial overlay | Centered window of arbitrary size, for testing `IS_PARTIALLY_OBSCURED` handling |
| Exact window placement | Window placed at `[l,t][r,b]` screen bounds (e.g. copied from the tap log) |
| Opacity / background control | Window alpha (to test the Android 12+ 0.8 threshold) and background color, including `transparent` |
| Decoy elements | Fake labels/buttons at screen coordinates, set via JSON from the in-app editor or adb |
| Tap logger | Accessibility service that logs clicks delivered to other apps and tags each one with its relation to the overlay |
| Permission popup | Guides the user to the app's own App Info page to grant "Display over other apps"; notifies instead of crashing when the permission is missing |

## Requirements

**Build host**
- Linux/macOS with `bash`, `python3`, `curl`, `unzip`
- **JDK 17 or 21.** JDK 22+ is detected as "≥ 21" but Gradle 8.9 can't run on it (`Unsupported class file major version`). Point `JAVA_HOME` at a 17/21 JDK.
- Android SDK with `ANDROID_HOME` (or `ANDROID_SDK_ROOT`) set. Platform 34 and build-tools are needed; AGP downloads missing components if the SDK licenses are accepted.
- Internet access on first build (Gradle distribution and Maven dependencies)

**Device**
- Android 8.0+ (minSdk 26, targetSdk 34)
- `adb` access recommended. Root is **not** required.

## Build

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk   # adjust to your JDK 17/21
export PATH="$JAVA_HOME/bin:$PATH"
bash setup.sh
```

`setup.sh`:
1. Checks the dependencies and the Java version, and picks a compatible Gradle/AGP/Kotlin toolchain.
2. **Deletes and regenerates** `./TapjackPoC/`. Don't keep manual changes there; edit `setup.sh` instead.
3. Writes the Gradle files, manifest, resources and Kotlin sources (all embedded in the script).
4. Bootstraps a Gradle wrapper (system `gradle` if present, otherwise downloads it) and runs `assembleDebug`.

Output: `TapjackPoC/app/build/outputs/apk/debug/app-debug.apk`

## Install and setup

```bash
adb install -r TapjackPoC/app/build/outputs/apk/debug/app-debug.apk
```

### 1. Grant "Display over other apps"

- **UI:** open the app. If the permission is missing, a dialog appears.
  - **Open App Info** opens the app's own App Info page, where you toggle *Display over other apps*. On some OEM ROMs it's under *Advanced* or *Other permissions*.
  - **Overlay list** opens the system list of all apps. On Android 11+, `ACTION_MANAGE_OVERLAY_PERMISSION` ignores the `package:` URI, so this always shows the full list.
  - An app can't grant this permission to itself; App Info is the most direct route available.
- **adb:**
  ```bash
  adb shell appops set com.audit.tapjackpoc SYSTEM_ALERT_WINDOW allow
  ```

### 2. Enable the tap logger (accessibility service)

- **UI:** *Enable Tap Logger* → Settings → Accessibility → *Tapjack PoC Tap Logger* → on.
- **adb:**
  ```bash
  adb shell settings put secure enabled_accessibility_services com.audit.tapjackpoc/.TapLoggerService
  adb shell settings put secure accessibility_enabled 1
  ```
  ⚠️ This **replaces** the list of enabled accessibility services. To keep others, read the current value first and append ours with `:`:
  ```bash
  adb shell settings get secure enabled_accessibility_services
  ```
- On Android 13+, apps sideloaded from a browser or file manager have "restricted settings", so the accessibility toggle is greyed out. Unlock it via App Info → ⋮ → *Allow restricted settings*. Installs done with `adb install` are normally not affected.

### 3. Notifications (Android 13+)

The app requests `POST_NOTIFICATIONS` at first launch. Without it the overlay still works, but the foreground-service notification and the "permission missing" alert stay hidden.

## Usage: in-app UI

The main screen shows:

- **Status:** overlay permission, tap logger state, current overlay rect/alpha, and the log file path
- **Buttons:**

| Button | Action |
|---|---|
| Grant Overlay Permission | Shows the permission dialog |
| Enable Tap Logger | Opens Accessibility settings |
| Start Full Overlay | Full-screen overlay, alpha 0.4, saved decoys applied |
| Start Partial (300x300) | Centered 300×300 px overlay, saved decoys applied |
| Stop Overlay | Removes the overlay |
| Clear Log | Clears the in-memory log and `taps.log` |
| Add From Recent Click | Picks one of the last 15 logged clicks and appends a decoy button at its bounds |
| Insert Sample | Fills the editor with a sample config |
| Save & Apply | Validates and saves the JSON; if an overlay is running, restarts it with the same window settings |
| Clear Elements | Empties and saves the config (no decoys) |

- **Decoy editor:** JSON text box (see [Decoy elements](#decoy-elements))
- **Live log:** newest first, last 80 lines, refreshed every second

The app's own UI stays usable while the overlay is up, since touches pass through.

## Usage: adb

```bash
# Full-screen overlay (alpha 0.4, red)
adb shell am start-foreground-service -n com.audit.tapjackpoc/.OverlayService

# Partial overlay, 300x300 px, centered
adb shell am start-foreground-service -n com.audit.tapjackpoc/.OverlayService --ei width 300 --ei height 300

# Overlay at exact screen bounds (e.g. copied from the tap log)
adb shell am start-foreground-service -n com.audit.tapjackpoc/.OverlayService --es bounds "[120,1400][960,1560]"

# Opacity above the Android 12+ threshold (should be blocked by the OS)
adb shell am start-foreground-service -n com.audit.tapjackpoc/.OverlayService --ef alpha 0.9

# Decoys from a pushed JSON file, transparent background
adb push decoy.json /sdcard/Android/data/com.audit.tapjackpoc/files/decoy.json
adb shell am start-foreground-service -n com.audit.tapjackpoc/.OverlayService \
    --es elements_file decoy.json --es background transparent --ef alpha 0.8

# Decoys inline (quoting through adb shell is fragile; prefer the file)
adb shell "am start-foreground-service -n com.audit.tapjackpoc/.OverlayService --es elements '[{\"type\":\"button\",\"text\":\"OK\",\"bounds\":\"[100,1050][980,1200]\"}]'"

# Stop and remove
adb shell am stopservice -n com.audit.tapjackpoc/.OverlayService

# Logs
adb logcat -s TapjackPoC
adb shell cat /sdcard/Android/data/com.audit.tapjackpoc/files/taps.log
```

Each new start replaces the current overlay. You don't need to stop it in between.

## Intent extras reference

`OverlayService` accepts:

| Extra | Type | Default | Description |
|---|---|---|---|
| `width` | int (`--ei`) | `MATCH_PARENT` | Window width in px (centered). Ignored if `bounds` is set |
| `height` | int (`--ei`) | `MATCH_PARENT` | Window height in px (centered). Ignored if `bounds` is set |
| `bounds` | string (`--es`) | — | `"[l,t][r,b]"` or `"l,t,r,b"`, screen coordinates. Places the window top-left at `(l,t)` with size `(r-l)×(b-t)` |
| `alpha` | float (`--ef`) | `0.4` | Window alpha. Applies to the whole surface, decoys included |
| `background` | string (`--es`) | red | `#RRGGBB`, `#AARRGGBB`, a color name (`red`, `black`, …) or `transparent` |
| `elements` | string (`--es`) | — | Inline decoy JSON |
| `elements_file` | string (`--es`) | — | Decoy JSON file, relative to `/sdcard/Android/data/com.audit.tapjackpoc/files/` or an absolute path readable by the app |

Window flags: `FLAG_NOT_FOCUSABLE | FLAG_NOT_TOUCHABLE | FLAG_LAYOUT_IN_SCREEN | FLAG_LAYOUT_NO_LIMITS`, with display cutout mode `ALWAYS` (API 30+) or `SHORT_EDGES` (API 28–29), so window coordinates match screen coordinates as closely as the system allows. The actual window rect is logged after layout, with a warning if it differs from the requested `bounds`.

Invalid `bounds`/`background` values are logged and ignored (the window falls back to width/height and red).

## Decoy elements

Decoys are fake UI drawn **inside** the overlay window to trick the user into tapping a real control underneath. They're visual only: the window remains `FLAG_NOT_TOUCHABLE`, so the tap reaches the target.

### Schema

Either an array of elements, or an object with an `elements` array:

```json
{
  "elements": [
    {"type": "label",  "text": "Tap below to continue", "bounds": "[100,900][980,1000]"},
    {"type": "button", "text": "Claim reward", "bounds": "[100,1050][980,1200]",
     "textSize": 16, "textColor": "#FFFFFF", "bgColor": "#1E88E5", "gravity": "center"}
  ]
}
```

| Field | Required | Values |
|---|---|---|
| `type` | no (default `button`) | `button` (Material `Button`) or `label` (`TextView`, black text) |
| `text` | no | Any string |
| `bounds` | **yes** | `"[l,t][r,b]"` (same format as the tap log) or `"l,t,r,b"`, screen px, non-empty |
| `textSize` | no | Size in sp |
| `textColor` | no | `#RRGGBB`, `#AARRGGBB`, color name, `transparent` |
| `bgColor` | no | Same as `textColor`. Replaces the button's default Material background |
| `gravity` | no | `center` (default), `start`/`left`, `end`/`right` |

### Behaviour

- **Source precedence:** `elements` extra > `elements_file` extra > config saved in the in-app editor. *Save & Apply* drops the inline/file extras when restarting, so the saved config takes effect.
- **Coordinates are screen coordinates.** They're converted to window-local positions using the window's real on-screen origin, so status-bar, cutout and gravity offsets are corrected automatically.
- **Clipping:** decoys only render inside the overlay window. Elements partly or fully outside are logged as `(partially clipped by window)` or `(outside window - not visible)`. Use a full-screen window (or larger `bounds`) when decoys sit away from the obscured area.
- **Validation:** malformed JSON aborts the whole config (in the editor, a toast shows the error). Individual invalid elements (bad type or bounds) are skipped with a warning; invalid colors are ignored.
- **Opacity:** window `alpha` multiplies everything, decoys included. On Android 12+, untrusted-touch blocking uses this window alpha, not the rendered pixels, so `background transparent` does **not** lower the effective opacity. Keep `alpha ≤ 0.8` for pass-through.

## Tap logger

`TapLoggerService` is an `AccessibilityService` subscribed to `TYPE_VIEW_CLICKED`, `TYPE_VIEW_LONG_CLICKED` and `TYPE_WINDOW_STATE_CHANGED`. It ignores events from its own package. The overlay itself is left unchanged and still passes touches through.

### Outputs

| Destination | Format |
|---|---|
| logcat | Tag `TapjackPoC`, level INFO, no timestamp |
| File | `/sdcard/Android/data/com.audit.tapjackpoc/files/taps.log` (falls back to internal `files/`), `HH:mm:ss.SSS` prefix |
| UI | Last 300 lines in memory, last 80 shown |

### Log lines

```
[a11y] tap logger connected
[window] foreground=com.target.app cls=com.target.app.ConfirmActivity
[overlay] 2 decoy element(s) from saved
[overlay] shown rect=[0,0][1080,2400] alpha=0.4
[overlay] element #1 button "Claim reward" at [100,1050][980,1200]
[CLICK] overlay=COVERED pkg=com.target.app cls=android.widget.Button id=com.target.app:id/confirm text="Confirm" desc="" bounds=[100,1050][980,1200]
[LONG_CLICK] overlay=OUTSIDE pkg=... 
[overlay] removed
[warn] tap logger not enabled - taps under the overlay will not be logged
```

### `overlay=` tag

Compares the clicked view's screen bounds with the overlay window's actual rect:

| Value | Meaning |
|---|---|
| `COVERED` | View fully inside the overlay. **The touch went through an obscuring window.** |
| `PARTIAL` | View intersects the overlay. Partially obscured scenario (whether the touch point itself was under the overlay is not known) |
| `OUTSIDE` | No intersection |
| `OFF` | No overlay active |
| `UNKNOWN` | Overlay active, but the view's bounds couldn't be read: `event.source` was null (view detached/navigated away, `importantForAccessibility="no"`, some WebView/Compose/custom views) or the bounds were empty. The click **was** delivered. With a full-screen overlay, treat it as covered |

### Key points

- **An event only exists if the target received and handled the touch.** Taps the target drops, or the OS blocks, produce no event.
- Clicks are also stored in a 15-entry history used by *Add From Recent Click*.
- The `bounds` printed in the log can be pasted directly into `--es bounds` or a decoy's `bounds`.

## Testing methodology

1. **Map the targets.** With the tap logger on and **no overlay**, go through the target's sensitive screens and tap the relevant controls (confirm payment, grant consent, delete, change security settings…). Each tap logs its `bounds` (`overlay=OFF`).
2. **Check for overlay hiding.** Start a full overlay and open the target. If the overlay disappears while the target is in the foreground, the app uses `setHideOverlayWindows(true)`: mitigated for that window.
3. **Obscured test (`IS_OBSCURED`).** Full overlay, default alpha 0.4. Tap each sensitive control.
   - `CLICK overlay=COVERED` plus the action executing → **vulnerable**.
   - No event and no effect → filtered.
4. **Partially obscured test (`IS_PARTIALLY_OBSCURED`).** Place a small overlay over another part of the same screen, **not** over the control:
   ```bash
   adb shell am start-foreground-service -n com.audit.tapjackpoc/.OverlayService --es bounds "[0,0][300,300]"
   ```
   Tap the control. If it goes through, the app doesn't reject partially obscured touches. `filterTouchesWhenObscured` alone doesn't cover this case.
5. **OS threshold control (Android 12+).** `--ef alpha 0.9`. Touches should be blocked by the OS whatever the app does. This only confirms the platform rule is active; it says nothing about the app.
6. **Build the PoC.** Use *Add From Recent Click* (or a JSON file) to put a convincing decoy over the real control, e.g. `background transparent`, alpha 0.8, a "Continue" button over "Confirm transfer". Record a screen capture showing the decoy, the tap, and the resulting action, with the matching log line.
7. **Clean up.** Stop the overlay and disable the accessibility service (Settings, or restore the previous `enabled_accessibility_services` value).

## Interpreting results

| Observation | Conclusion |
|---|---|
| Overlay visible over the target | Expected; not a finding |
| Overlay disappears when the target is in the foreground | `setHideOverlayWindows` in use: mitigated |
| Alpha 0.4, control fully covered, tap logged `COVERED` + action executes | No `IS_OBSCURED` filtering: **vulnerable** |
| Alpha 0.4, control fully covered, no event, no effect | `IS_OBSCURED` filtered |
| Overlay elsewhere on screen, tap on control executes | No `IS_PARTIALLY_OBSCURED` filtering |
| Alpha 0.9 on Android 12+, tap blocked | OS untrusted-touch blocking working; not app-specific |
| Alpha 0.9 on Android ≤ 11, tap executes | Same as the 0.4 result: depends on app filtering only |
| No event but the action executed | View handles touches without `performClick()`; trust the visible effect |
| `overlay=UNKNOWN` | Touch delivered, bounds unavailable; check visually |

## Reporting notes

- **Scope to sensitive screens.** Missing filtering on a screen with no meaningful action is a weak finding. Name the specific screens/controls tested and the result for each, since mitigations are applied per view or per window.
- **Preconditions:** a malicious app installed on the device, and the user granting it "Display over other apps" (a manual step in Settings since Android 6). This typically puts severity at low/medium unless the affected actions are high-impact (payments, authorization, security settings).
- **Remediation:**
  - `android:filterTouchesWhenObscured="true"` on sensitive views (or the root view of sensitive screens).
  - Override `onFilterTouchEventForSecurity()` to also reject `MotionEvent.FLAG_WINDOW_IS_PARTIALLY_OBSCURED`.
  - Compose: check `MotionEvent.flags` for both flags via `pointerInteropFilter` on sensitive components.
  - API 31+: `window.setHideOverlayWindows(true)` with `<uses-permission android:name="android.permission.HIDE_OVERLAY_WINDOWS"/>` on sensitive screens.
- **Accessibility note:** some apps change behaviour when an accessibility service is enabled (detection, blocked screens). If results look inconsistent, disable the tap logger and repeat the test, judging only by the visible effect.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Unsupported class file major version 7x` during build | JDK too new for Gradle 8.9. Use JDK 17/21 via `JAVA_HOME` |
| `ANDROID_HOME is not set` | Export `ANDROID_HOME` pointing at your SDK |
| Permission dialog shows the list of all apps | That's the *Overlay list* button (Android 11+ behaviour). Use *Open App Info* |
| Overlay doesn't appear, log says `SYSTEM_ALERT_WINDOW not granted` | Grant the permission (UI or `appops`) |
| Accessibility toggle greyed out | Android 13+ restricted settings: App Info → ⋮ → *Allow restricted settings*, or install via `adb install` |
| No `[CLICK]` lines at all, even with no overlay | Tap logger not enabled (check the status line); the target may use views without click events |
| Decoys not visible | Check the log for `outside window` / `skipped` warnings and `element config error`; make sure the window is large enough (full overlay) |
| `WARNING: requested bounds ... but system placed window at ...` | The system constrained the window (insets, cutout, OEM policy). Adjust the coordinates by the reported offset |
| `taps.log` not readable via `adb shell cat` | Some devices restrict `Android/data`. Use `adb logcat -s TapjackPoC` instead |
| Inline `elements` JSON garbled | Shell quoting through `adb shell`. Push a file and use `elements_file` |
| No notifications | Grant notifications (Android 13+); the overlay works regardless |

## Limitations

- **Click events, not raw touches.** The logger sees `performClick()` / long-click events. Views that consume touches directly (some custom, Compose, game or WebView content) emit nothing even when the touch went through. A missing event isn't proof of mitigation; confirm by the visible effect.
- `PARTIAL` uses the clicked view's bounds, not the touch coordinates. It can't tell `IS_OBSCURED` from `IS_PARTIALLY_OBSCURED` precisely.
- Decoys are clipped to the overlay window, and window alpha applies to them.
- The window can't exceed the 0.8 opacity limit and still pass touches on Android 12+. This is a platform constraint, not a tool limitation.
- Coordinates are absolute pixels. Rotation or a different device needs new bounds.
- System dialogs (permission prompts, etc.) are protected by the platform and aren't meaningful targets.

## Project structure

```
.
├── setup.sh        # Generates the whole Android project and builds the APK
├── README.md
└── TapjackPoC/     # Generated by setup.sh (deleted and recreated on every run)
    └── app/src/main/
        ├── AndroidManifest.xml
        ├── res/values/strings.xml          # Accessibility service description
        ├── res/xml/tap_logger_config.xml   # Accessibility service config
        └── java/com/audit/tapjackpoc/
            ├── MainActivity.kt       # UI, permission dialog, decoy editor, live log
            ├── OverlayService.kt     # Foreground service drawing the overlay + decoys
            ├── OverlayConfig.kt      # Decoy JSON parsing, bounds/color parsing, config sources
            ├── OverlayState.kt       # Current overlay rect/alpha, overlay= relation logic
            ├── TapLoggerService.kt   # Accessibility service logging delivered clicks
            ├── ClickHistory.kt       # Recent clicks for "Add From Recent Click"
            └── TapLog.kt             # logcat + file + in-memory logging
```

Package: `com.audit.tapjackpoc`. Permissions: `SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_NOTIFICATIONS`. The accessibility service is bound with `BIND_ACCESSIBILITY_SERVICE`.
