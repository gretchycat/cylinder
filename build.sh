#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

GODOT_BIN="${GODOT_BIN:-$(which godot || echo "$HOME/.local/bin/godot")}"
BUILD_DIR="$PROJECT_DIR/build"
mkdir -p "$BUILD_DIR"

# Android SDK defaults differ between desktop Android Studio and Termux.
if [ -z "${ANDROID_HOME:-}" ] && [ -z "${ANDROID_SDK_ROOT:-}" ]; then
    if [ -d "$HOME/android-sdk" ]; then
        ANDROID_HOME="$HOME/android-sdk"
    else
        ANDROID_HOME="$HOME/Android/Sdk"
    fi
fi
export ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"

usage() {
    echo "=========================================================="
    echo " O'Neill Cylinder Game Engine Build & Run Utility"
    echo "=========================================================="
    echo "Usage: ./build.sh [command]"
    echo ""
    echo "Commands:"
    echo "  run             Run the game on desktop"
    echo "  test            Run headless verification test suite"
    echo "  android [abi]   Export Android APK (default ABI: arm64-v8a)"
    echo "                  ABIs: arm64-v8a, armeabi-v7a, x86, x86_64"
    echo "  linux [arch]    Export Linux binary (default: host architecture)"
    echo "                  Architectures: x86_64, x86_32, arm64, arm32, rv64, ppc64, loongarch64"
    echo "  install [abi]   Install APK; build it for this ABI if needed"
    echo "  maps SRC DEST [SEED]  Generate a new map from its descriptor"
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

detect_linux_arch() {
    local host_arch
    host_arch="$(uname -m)"
    case "$host_arch" in
        x86_64|amd64) echo "x86_64" ;;
        i386|i486|i586|i686) echo "x86_32" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7*|armv6*|arm) echo "arm32" ;;
        riscv64) echo "rv64" ;;
        ppc64|ppc64le) echo "ppc64" ;;
        loongarch64) echo "loongarch64" ;;
        *)
            echo "[ERROR] Cannot infer a Godot Linux export architecture from '$host_arch'. Pass one to './build.sh linux <arch>'." >&2
            return 1
            ;;
    esac
}

normalize_android_arch() {
    case "$1" in
        arm64|arm64-v8a) echo "arm64-v8a" ;;
        arm32|armeabi-v7a) echo "armeabi-v7a" ;;
        x86_32|x86) echo "x86" ;;
        x86_64) echo "x86_64" ;;
        *)
            echo "[ERROR] Unsupported Android ABI '$1'. Use arm64-v8a, armeabi-v7a, x86, or x86_64." >&2
            return 1
            ;;
    esac
}

normalize_linux_arch() {
    case "$1" in
        amd64|x86_64) echo "x86_64" ;;
        i386|i486|i586|i686|x86_32) echo "x86_32" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7*|armv6*|arm|arm32) echo "arm32" ;;
        riscv64|rv64) echo "rv64" ;;
        ppc64|ppc64le) echo "ppc64" ;;
        loongarch64) echo "loongarch64" ;;
        *)
            echo "[ERROR] Unsupported Linux architecture '$1'." >&2
            return 1
            ;;
    esac
}

generate_export_presets() {
    local android_arch="$1"
    local linux_arch="$2"
    local android_arm64=false android_arm32=false android_x86=false android_x86_64=false
    case "$android_arch" in
        arm64-v8a) android_arm64=true ;;
        armeabi-v7a) android_arm32=true ;;
        x86) android_x86=true ;;
        x86_64) android_x86_64=true ;;
    esac
    local debug_keystore="${ANDROID_DEBUG_KEYSTORE:-$HOME/.local/share/godot/keystores/debug.keystore}"

    cat > "$PROJECT_DIR/export_presets.cfg" <<EOF
[preset.0]

name="Android"
platform="Android"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.json,*.cylh,assets/maps/*/biomes.png"
exclude_filter=""
export_path="build/cylinder.apk"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
gradle_build/export_format=0
gradle_build/min_sdk=""
gradle_build/target_sdk=""
package/unique_name="org.godotengine.cylinder"
package/name="ONeill Cylinder"
package/signed=true
package/app_category=0
package/retain_data_on_uninstall=false
package/exclude_from_recents=false
package/show_in_app_library=true
version/code=1
version/name="1.0"
architectures/armeabi-v7a=$android_arm32
architectures/arm64-v8a=$android_arm64
architectures/x86=$android_x86
architectures/x86_64=$android_x86_64
launcher_icons/main_192=""
launcher_icons/adaptive_foreground_432=""
launcher_icons/adaptive_background_432=""
graphics/opengl_debug=false
xr/mode=0
screen/orientation=0
screen/support_multi_window=false
screen/immersive_mode=true
keystore/debug="$debug_keystore"
keystore/debug_user="androiddebugkey"
keystore/debug_password="android"
keystore/release=""
keystore/release_user=""
keystore/release_password=""

[preset.1]

name="Linux"
platform="Linux/X11"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.json,*.cylh,assets/maps/*/biomes.png"
exclude_filter=""
export_path="build/cylinder.$linux_arch"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.1.options]

custom_template/debug=""
custom_template/release=""
binary_format/embed_pck=false
texture_format/bptc=true
texture_format/s3tc=true
texture_format/etc=false
texture_format/etc2=false
binary_format/architecture="$linux_arch"
ssh/ssh_path=""
ssh/host=""
ssh/port="22"
ssh/user=""
ssh/password=""
ssh/remote_path=""
EOF
    echo "[PRESET] Android ABI: $android_arch | Linux architecture: $linux_arch"
}

cmd_run() {
    check_godot
    echo "[RUN] Launching game on desktop..."
    "$GODOT_BIN" scenes/main.tscn
}

cmd_test() {
    check_godot
    "$GODOT_BIN" --headless -s scripts/test_map_pipeline.gd
    "$GODOT_BIN" --headless -s scripts/test_map_scene.gd
    "$GODOT_BIN" --headless -s scripts/test_map_imports.gd
    "$GODOT_BIN" --headless -s scripts/test_map_library.gd
    echo "[TEST] Running touch controls, world editing, and save/reload tests..."
    "$GODOT_BIN" --headless -s scripts/test_edit_controls.gd
    echo "[TEST] Running automated test suite in headless mode..."
    if command -v timeout >/dev/null 2>&1; then
        timeout 75s "$GODOT_BIN" --headless -s scripts/test_simulation.gd
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "[ERROR] Test suite timed out after 75 seconds!"
            exit 124
        fi
        return $exit_code
    else
        "$GODOT_BIN" --headless -s scripts/test_simulation.gd
    fi
}

cmd_android() {
    check_godot
    local android_arch
    android_arch="$(normalize_android_arch "${1:-${ANDROID_ARCH:-arm64-v8a}}")"
    generate_export_presets "$android_arch" "x86_64"

    if [ ! -d "$ANDROID_SDK_ROOT/platform-tools" ] || [ ! -d "$ANDROID_SDK_ROOT/build-tools" ]; then
        echo "[ERROR] Android SDK is incomplete at '$ANDROID_SDK_ROOT'."
        echo "        Set ANDROID_SDK_ROOT to a valid SDK containing platform-tools and build-tools."
        exit 1
    fi

    local godot_version template_dir
    godot_version="$("$GODOT_BIN" --version | cut -d'.' -f1-3)"
    template_dir="$HOME/.local/share/godot/export_templates/${godot_version}.stable"
    if [ ! -f "$template_dir/android_debug.apk" ]; then
        echo "[ERROR] Android export templates for Godot $godot_version are missing."
        echo "        Install them with: \"$GODOT_BIN\" --headless --install-android-build-template"
        echo "        or through Editor -> Manage Export Templates."
        exit 1
    fi

    echo "[BUILD] Exporting Android APK..."
    "$GODOT_BIN" --headless --export-debug "Android" "$BUILD_DIR/cylinder.apk"
    echo "[SUCCESS] Exported Android APK to: $BUILD_DIR/cylinder.apk"
}

cmd_linux() {
    check_godot
    local android_arch linux_arch
    android_arch="$(normalize_android_arch "${ANDROID_ARCH:-arm64-v8a}")"
    linux_arch="$(normalize_linux_arch "${1:-${LINUX_ARCH:-$(detect_linux_arch)}}")"
    generate_export_presets "$android_arch" "$linux_arch"
    echo "[BUILD] Exporting Linux binary..."
    "$GODOT_BIN" --headless --export-release "Linux" "$BUILD_DIR/cylinder.$linux_arch"
    echo "[SUCCESS] Exported Linux binary to: $BUILD_DIR/cylinder.$linux_arch"
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
        cmd_android "${1:-}"
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
    echo "[MAPS] Generating schema 3 map..."
    shift || true
    "$GODOT_BIN" --headless --path . -s scripts/generate_map_cli.gd -- "$@"
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
        cmd_android "${2:-}"
        ;;
    linux)
        cmd_linux "${2:-}"
        ;;
    install)
        cmd_install "${2:-}"
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
