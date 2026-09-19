#!/usr/bin/env bash
#
# Captures raw marketing screenshots of the app on throwaway simulators.
#
#   Screenshots/capture.sh [iphone] [ipad]      (default: both)
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
# Environment overrides:
#   SCREENSHOT_RUNTIME         simulator runtime (default: iOS 27.0)
#   SCREENSHOT_IPHONE_DEVICE   device type (default: iPhone 18 Pro Max, 1320x2868)
#   SCREENSHOT_IPAD_DEVICE     device type (default: iPad Pro 13-inch (M5), 2064x2752)
#   SCREENSHOT_SETTLE_SECONDS  wait after launch before capturing (default: 5)

set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$PACKAGE_DIR/.." && pwd)"
BUILD_DIR="$PACKAGE_DIR/.build/screenshots"
RAW_DIR="$BUILD_DIR/raw"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/VaultApp.app"
BUNDLE_ID="com.badbundle.vault"

RUNTIME="${SCREENSHOT_RUNTIME:-iOS 27.0}"
IPHONE_DEVICE="${SCREENSHOT_IPHONE_DEVICE:-iPhone 18 Pro Max}"
IPAD_DEVICE="${SCREENSHOT_IPAD_DEVICE:-iPad Pro 13-inch (M5)}"
SETTLE_SECONDS="${SCREENSHOT_SETTLE_SECONDS:-5}"

# Order here is the order of the numbered output files. Names must match
# ScreenshotMode.Scene's raw values.
SCENES=(feed detail tags backups settings)

CLASSES=("$@")
if [[ ${#CLASSES[@]} -eq 0 ]]; then
    CLASSES=(iphone ipad)
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
            echo "Unknown device class '$1' (expected iphone or ipad)" >&2
            exit 2
            ;;
    esac
}

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
        -quiet
    [[ -d "$APP_PATH" ]] || { echo "Build did not produce $APP_PATH" >&2; exit 1; }
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

capture_scene() {
    local udid="$1" scene="$2" output="$3"
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" \
        -screenshot-scene "$scene" >/dev/null
    sleep "$SETTLE_SECONDS"
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

build_app
for class in "${CLASSES[@]}"; do
    capture_class "$class"
done
log "Raw screenshots in $RAW_DIR"
