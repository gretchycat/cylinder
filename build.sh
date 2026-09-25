#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

GODOT_BIN="${GODOT_BIN:-$(which godot || echo "$HOME/.local/bin/godot")}"
BUILD_DIR="$PROJECT_DIR/build"
mkdir -p "$BUILD_DIR"

# Ensure Android SDK paths
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"

usage() {
    echo "=========================================================="
    echo " O'Neill Cylinder Game Engine Build & Run Utility"
    echo "=========================================================="
    echo "Usage: ./build.sh [command]"
    echo ""
    echo "Commands:"
    echo "  run             Run the game on desktop"
    echo "  test            Run headless verification test suite"
    echo "  android         Export Android APK (build/cylinder.apk)"
    echo "  linux           Export Linux binary (build/cylinder.x86_64)"
    echo "  install         Install exported APK to connected Android device (via adb)"
    echo "  maps            Generate vertically tileable elevation & terrain PNG maps"
    echo "  templates       Check status of Godot export templates"
    echo "  help            Show this help message"
    echo "=========================================================="
}

check_godot() {
    if [ ! -x "$GODOT_BIN" ]; then
        echo "[ERROR] Godot executable not found at '$GODOT_BIN'."
        exit 1
    fi
}

cmd_run() {
    check_godot
    echo "[RUN] Launching game on desktop..."
    "$GODOT_BIN" scenes/main.tscn
}

cmd_test() {
    check_godot
    echo "[TEST] Running automated test suite in headless mode..."
    if command -v timeout >/dev/null 2>&1; then
        timeout 25s "$GODOT_BIN" --headless -s scripts/test_simulation.gd
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "[ERROR] Test suite timed out after 25 seconds!"
            exit 124
        fi
        return $exit_code
    else
        "$GODOT_BIN" --headless -s scripts/test_simulation.gd
    fi
}

cmd_android() {
    check_godot
    echo "[BUILD] Exporting Android APK..."
    "$GODOT_BIN" --headless --export-debug "Android" "$BUILD_DIR/cylinder.apk"
    echo "[SUCCESS] Exported Android APK to: $BUILD_DIR/cylinder.apk"
}

cmd_linux() {
    check_godot
    echo "[BUILD] Exporting Linux binary..."
    "$GODOT_BIN" --headless --export-release "Linux" "$BUILD_DIR/cylinder.x86_64"
    echo "[SUCCESS] Exported Linux binary to: $BUILD_DIR/cylinder.x86_64"
}

cmd_install() {
    ADB_BIN="$(which adb || echo "$ANDROID_HOME/platform-tools/adb")"
    if [ ! -x "$ADB_BIN" ]; then
        echo "[ERROR] adb tool not found. Check Android SDK installation."
        exit 1
    fi
    APK_FILE="$BUILD_DIR/cylinder.apk"
    if [ ! -f "$APK_FILE" ]; then
        echo "[INFO] APK not found. Building Android APK first..."
        cmd_android
    fi
    echo "[ADB] Installing $APK_FILE to connected device..."
    "$ADB_BIN" install -r "$APK_FILE"
    echo "[SUCCESS] Installed APK on device!"
}

cmd_templates() {
    check_godot
    GODOT_VERSION="$("$GODOT_BIN" --version | cut -d'.' -f1-3)"
    TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
    echo "[TEMPLATES] Target template directory: $TEMPLATE_DIR"
    if [ -d "$TEMPLATE_DIR" ] && [ "$(ls -A "$TEMPLATE_DIR" 2>/dev/null)" ]; then
        echo "[STATUS] Export templates are installed."
        ls -lh "$TEMPLATE_DIR"
    else
        echo "[STATUS] Export templates not found in $TEMPLATE_DIR."
        echo ""
        echo "To install templates for Godot $GODOT_VERSION:"
        echo "  1. Open Godot: $GODOT_BIN"
        echo "  2. Go to: Editor -> Manage Export Templates -> Download and Install"
        echo "     (or download Godot_v${GODOT_VERSION}-stable_export_templates.tpz and install from file)"
    fi
}

cmd_maps() {
    echo "[MAPS] Generating vertically tileable elevation & terrain maps..."
    shift || true
    python3 scripts/generate_tileable_maps.py "$@"
}

case "${1:-run}" in
    run)
        cmd_run
        ;;
    test)
        cmd_test
        ;;
    maps)
        cmd_maps "$@"
        ;;
    android)
        cmd_android
        ;;
    linux)
        cmd_linux
        ;;
    install)
        cmd_install
        ;;
    templates)
        cmd_templates
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
