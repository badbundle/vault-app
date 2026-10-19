#!/usr/bin/env bash
#
# Captures raw marketing screenshots of the app, on throwaway simulators for
# iPhone and iPad and on this Mac for the Mac app.
#
#   Screenshots/capture.sh [iphone] [ipad] [mac]      (default: all three)
#
# Builds VaultApp for the simulator, then for each device class creates a
# fresh simulator, launches the app straight into every screenshot scene (see
# Sources/VaultiOS/Mocks/ScreenshotMode.swift) in light and dark appearance,
# and writes
#
#   .build/screenshots/raw/<class>/<NN>-<scene>.png
#   .build/screenshots/raw/<class>/<NN>-<scene>-dark.png
#
# at the device's native pixel size, which is what the framer configs in this
# directory expect. The simulators are deleted afterwards unless
# SCREENSHOT_KEEP_SIMULATORS=1.
#
# For mac, it builds the Mac app (VaultMacApp) and launches it once per scene
# and appearance (see Sources/VaultMac/Mocks/VaultMacScreenshotMode.swift). The
# app opens the scene on its demo vault in a window of a fixed size, comes to
# the front, captures that window itself, at 2x, and writes it to a file
# descriptor this script opens, then quits. Every Vault window is kept out of
# screen captures, and the script asks for no permission to capture the
# screen. It needs the window on a Retina display, and the Mac unlocked, and
# takes the front from whatever app is in use for about 5 seconds each time.
#
# Environment overrides:
#   SCREENSHOT_RUNTIME         simulator runtime (default: iOS 27.0)
#   SCREENSHOT_IPHONE_DEVICE   device type (default: iPhone 18 Pro Max, 1320x2868)
#   SCREENSHOT_IPAD_DEVICE     device type (default: iPad Pro 13-inch (M5), 2064x2752)
#   SCREENSHOT_SETTLE_SECONDS  wait after launch before capturing (default: 5).
#                              Scenes behind the App Lock Password wait 4
#                              seconds longer, for the lock to open. The Mac
#                              app waits by itself.

set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$PACKAGE_DIR/.." && pwd)"
BUILD_DIR="$PACKAGE_DIR/.build/screenshots"
RAW_DIR="$BUILD_DIR/raw"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/VaultApp.app"
MAC_APP_PATH="$DERIVED_DATA/Build/Products/Debug/Vault.app"
BUNDLE_ID="com.badbundle.vault"

RUNTIME="${SCREENSHOT_RUNTIME:-iOS 27.0}"
IPHONE_DEVICE="${SCREENSHOT_IPHONE_DEVICE:-iPhone 18 Pro Max}"
IPAD_DEVICE="${SCREENSHOT_IPAD_DEVICE:-iPad Pro 13-inch (M5)}"
SETTLE_SECONDS="${SCREENSHOT_SETTLE_SECONDS:-5}"

# Order here is the order of the numbered output files. Names must match
# ScreenshotMode.Scene's raw values.
SCENES=(feed detail search editor lock app-lock-password backups settings)
# Scenes that start behind the lock and enter the App Lock Password, which
# takes Face ID, the password and the door opening before they show.
UNLOCKING_SCENES=(app-lock-password settings)

# The Mac app's scenes, likewise matching VaultMacScreenshotMode.Scene.
MAC_SCENES=(feed detail editor lock backups settings)
# How long one Mac capture may take, from launch to quitting.
MAC_CAPTURE_TIMEOUT_SECONDS=40

CLASSES=("$@")
if [[ ${#CLASSES[@]} -eq 0 ]]; then
    CLASSES=(iphone ipad mac)
fi

CREATED_SIMULATORS=()

log() {
    printf '\033[1m==> %s\033[0m\n' "$*"
}

cleanup() {
    if [[ "${SCREENSHOT_KEEP_SIMULATORS:-0}" == "1" ]]; then
        log "Keeping simulators: ${CREATED_SIMULATORS[*]:-none}"
        return
    fi
    for udid in "${CREATED_SIMULATORS[@]:-}"; do
        [[ -n "$udid" ]] || continue
        xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
        xcrun simctl delete "$udid" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

device_type_for() {
    case "$1" in
        iphone) printf '%s' "$IPHONE_DEVICE" ;;
        ipad) printf '%s' "$IPAD_DEVICE" ;;
        *)
            echo "Unknown device class '$1' (expected iphone, ipad or mac)" >&2
            exit 2
            ;;
    esac
}

# For this Mac's architecture only, which its simulators run: built for every
# simulator architecture, the widget extension's x86_64 slice can't find the
# package's module, which is only built for this one.
build_app() {
    log "Building VaultApp for the simulator"
    xcodebuild build \
        -workspace "$REPO_DIR/Vault.xcworkspace" \
        -scheme VaultApp \
        -configuration Debug \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$DERIVED_DATA" \
        -skipPackagePluginValidation \
        -skipMacroValidation \
        -quiet \
        ARCHS="$(uname -m)"
    [[ -d "$APP_PATH" ]] || { echo "Build did not produce $APP_PATH" >&2; exit 1; }
}

build_mac_app() {
    log "Building the Mac app"
    xcodebuild build \
        -workspace "$REPO_DIR/Vault.xcworkspace" \
        -scheme VaultMacApp \
        -configuration Debug \
        -destination "platform=macOS" \
        -derivedDataPath "$DERIVED_DATA" \
        -skipPackagePluginValidation \
        -skipMacroValidation \
        -quiet
    [[ -d "$MAC_APP_PATH" ]] || { echo "Build did not produce $MAC_APP_PATH" >&2; exit 1; }
}

# Launches the Mac app into a scene, which writes its window to file
# descriptor 3 and quits. Saved window state is ignored, as a launch from
# outside Xcode or the Finder otherwise opens no window at all once the app
# has been stopped. Scroll bars only show while scrolling, as with a trackpad.
capture_mac_scene() {
    local scene="$1" appearance="$2" output="$3"
    local log status=0 waited=0 pid
    log="$(mktemp)"
    "$MAC_APP_PATH/Contents/MacOS/Vault" \
        -screenshot-scene "$scene" \
        -screenshot-appearance "$appearance" \
        -screenshot-fd 3 \
        -ApplePersistenceIgnoreState YES \
        -AppleShowScrollBars WhenScrolling \
        3>"$output" >/dev/null 2>"$log" &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if ((waited >= MAC_CAPTURE_TIMEOUT_SECONDS)); then
            kill "$pid" 2>/dev/null || true
            echo "The Mac app took over $MAC_CAPTURE_TIMEOUT_SECONDS seconds on the $scene scene" >&2
            status=1
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
    wait "$pid" 2>/dev/null || status=1
    if ((status != 0)) || ! file -b "$output" | grep -q '^PNG image'; then
        grep 'screenshot mode' "$log" >&2 || cat "$log" >&2
        rm -f "$log"
        echo "Couldn't capture the Mac app's $scene scene ($appearance)" >&2
        return 1
    fi
    rm -f "$log"
    echo "    $output"
}

capture_mac() {
    local out_dir="$RAW_DIR/mac"
    rm -rf "$out_dir"
    mkdir -p "$out_dir"

    log "Capturing mac (Vault's windows on this Mac)"
    local appearance
    for appearance in light dark; do
        local suffix=""
        [[ "$appearance" == "dark" ]] && suffix="-dark"
        local index=1
        local scene
        for scene in "${MAC_SCENES[@]}"; do
            capture_mac_scene "$scene" "$appearance" "$out_dir/$(printf '%02d' "$index")-$scene$suffix.png"
            index=$((index + 1))
        done
    done
}

# Creates, boots and prepares a simulator, leaving its UDID in SIMULATOR_UDID.
# (Not a command substitution: the trap needs CREATED_SIMULATORS updated in
# this shell.)
make_simulator() {
    local class="$1"
    local device_type
    device_type="$(device_type_for "$class")"
    SIMULATOR_UDID="$(xcrun simctl create "vault-screenshots-$class" "$device_type" "$RUNTIME")"
    CREATED_SIMULATORS+=("$SIMULATOR_UDID")
    xcrun simctl boot "$SIMULATOR_UDID"
    xcrun simctl bootstatus "$SIMULATOR_UDID" -b >/dev/null
    # The status bar Apple shows in its own marketing.
    xcrun simctl status_bar "$SIMULATOR_UDID" override \
        --time "9:41" \
        --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 \
        --batteryState charged --batteryLevel 100
    xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
}

settle_seconds_for() {
    local scene="$1" unlocking
    for unlocking in "${UNLOCKING_SCENES[@]}"; do
        if [[ "$scene" == "$unlocking" ]]; then
            printf '%s' "$((SETTLE_SECONDS + 4))"
            return
        fi
    done
    printf '%s' "$SETTLE_SECONDS"
}

capture_scene() {
    local udid="$1" scene="$2" output="$3"
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" \
        -screenshot-scene "$scene" >/dev/null
    sleep "$(settle_seconds_for "$scene")"
    # simctl chatters on stderr for every capture; only show it on failure.
    local result
    if ! result="$(xcrun simctl io "$udid" screenshot --type=png "$output" 2>&1)"; then
        echo "$result" >&2
        return 1
    fi
    echo "    $output"
}

capture_class() {
    local class="$1"
    local out_dir="$RAW_DIR/$class"
    rm -rf "$out_dir"
    mkdir -p "$out_dir"

    log "Capturing $class ($(device_type_for "$class"), $RUNTIME)"
    make_simulator "$class"
    local udid="$SIMULATOR_UDID"

    local appearance
    for appearance in light dark; do
        xcrun simctl ui "$udid" appearance "$appearance"
        local suffix=""
        [[ "$appearance" == "dark" ]] && suffix="-dark"
        local index=1
        local scene
        for scene in "${SCENES[@]}"; do
            capture_scene "$udid" "$scene" "$out_dir/$(printf '%02d' "$index")-$scene$suffix.png"
            index=$((index + 1))
        done
    done

    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

for class in "${CLASSES[@]}"; do
    if [[ "$class" != mac ]]; then
        device_type_for "$class" >/dev/null
    fi
done
for class in "${CLASSES[@]}"; do
    if [[ "$class" == mac ]]; then
        [[ -n "${BUILT_MAC_APP:-}" ]] || { build_mac_app; BUILT_MAC_APP=1; }
        capture_mac
    else
        [[ -n "${BUILT_APP:-}" ]] || { build_app; BUILT_APP=1; }
        capture_class "$class"
    fi
done
log "Raw screenshots in $RAW_DIR"
