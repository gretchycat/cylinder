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
    echo "  preflight       Check test, Android, and native Linux build requirements"
    echo "                  Also checks Rust/GDExtension tools and crate dependencies"
    echo "  maps SRC DEST [SEED]  Generate a new map from its descriptor"
    echo "  templates       Check status of Godot export templates"
    echo "  help            Show this help message"
    echo "=========================================================="
}

check_godot() {
    if [ ! -x "$GODOT_BIN" ]; then
        echo "[ERROR] Godot executable not found at '$GODOT_BIN'."
        echo "        Install Godot $(grep -E '^config/version=' project.godot | cut -d'"' -f2) for this host architecture,"
        echo "        or set GODOT_BIN=/path/to/godot and rerun: ./build.sh preflight"
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

godot_version() {
    "$GODOT_BIN" --version | cut -d'.' -f1-3
}

export_template_dir() {
    printf '%s/.local/share/godot/export_templates/%s.stable\n' "$HOME" "$(godot_version)"
}

prompt_to_install() {
    local prompt="$1"
    if [ ! -t 0 ]; then
        echo "[INFO] Noninteractive run; skipping the installation prompt."
        return 1
    fi
    local answer
    read -r -p "$prompt [y/N] " answer || answer=""
    case "$answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

rust_host_target() {
    local host_os host_arch
    host_os="$(uname -s)"
    host_arch="$(uname -m)"
    case "$host_os:$host_arch" in
        Linux:aarch64|Linux:arm64) echo "aarch64-unknown-linux-gnu" ;;
        Linux:x86_64|Linux:amd64) echo "x86_64-unknown-linux-gnu" ;;
        Darwin:arm64) echo "aarch64-apple-darwin" ;;
        Darwin:x86_64) echo "x86_64-apple-darwin" ;;
        *) echo "" ;;
    esac
}

install_rust_toolchain() {
    if command -v pkg >/dev/null 2>&1; then
        echo "        Termux command: pkg install rust"
        prompt_to_install "Install Rust with pkg?" || return 1
        pkg install rust || return 1
    elif command -v apt-get >/dev/null 2>&1; then
        if command -v sudo >/dev/null 2>&1; then
            echo "        Debian/Ubuntu command: sudo apt-get install -y cargo rustc"
            prompt_to_install "Install Rust with apt-get?" || return 1
            sudo apt-get install -y cargo rustc || return 1
        else
            echo "        Debian/Ubuntu command: apt-get install -y cargo rustc"
            prompt_to_install "Install Rust with apt-get?" || return 1
            apt-get install -y cargo rustc || return 1
        fi
    elif command -v dnf >/dev/null 2>&1; then
        echo "        Fedora command: sudo dnf install -y cargo rust"
        prompt_to_install "Install Rust with dnf?" || return 1
        sudo dnf install -y cargo rust || return 1
    else
        echo "        Install Rust and Cargo for $(uname -s) $(uname -m) using the platform's official Rust installer."
        echo "        Then rerun: ./build.sh preflight"
        return 1
    fi
}

ensure_rust_build_requirements() {
    local rust_target="$(rust_host_target)"
    if ! command -v rustc >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
        echo "[MISSING] Rust compiler and Cargo are required to build the Rust terrain extension."
        if ! install_rust_toolchain; then
            echo "[INFO] Rust installation skipped; Rust extension builds will be unavailable."
            return 1
        fi
    fi
    if ! command -v rustc >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
        echo "[ERROR] Rust/Cargo are still unavailable after the installation step."
        return 1
    fi
    echo "[READY] Rust $(rustc --version), Cargo $(cargo --version)"
    if [ -n "$rust_target" ]; then
        echo "[CHECK] Native Rust target: $rust_target"
        if rustc --print target-list | grep -Fxq "$rust_target"; then
            echo "[INFO] Rust target is supported by this toolchain; the target standard library may still need rustup for cross-builds."
        fi
    else
        echo "[INFO] No native Rust target mapping is configured for $(uname -s) $(uname -m)."
    fi
    echo "[CHECK] Android GDExtension target: aarch64-linux-android (requires Android NDK linker for cross-compilation)."
    if cargo fetch --locked --offline --manifest-path "$PROJECT_DIR/Cargo.toml" >/dev/null 2>&1; then
        echo "[READY] Rust crate dependencies are cached."
        return 0
    fi
    echo "[MISSING] One or more Cargo crates are not cached locally."
    echo "        Fetch the locked dependencies with: cargo fetch --locked --manifest-path '$PROJECT_DIR/Cargo.toml'"
    echo "        Cargo will show download progress while it fetches the crates."
    if prompt_to_install "Download the missing Rust crates now?"; then
        cargo fetch --locked --manifest-path "$PROJECT_DIR/Cargo.toml"
        return $?
    fi
    echo "[INFO] Rust crate download skipped; offline Rust builds may fail until dependencies are fetched."
    return 1
}

print_template_install_instructions() {
    local target="$1"
    local arch="$2"
    local build_command="$3"
    local template_dir
    template_dir="$(export_template_dir)"
    echo "        Install the matching Godot $(godot_version) export template in:"
    echo "        $template_dir"
    echo "        In the Godot Editor, choose Editor -> Manage Export Templates -> Download and Install."
    echo "        Then run: $build_command"
    if [ "$target" = "Linux" ]; then
        echo "        Required file: $template_dir/linux_release.$arch"
    else
        echo "        Required file: $template_dir/android_debug.apk"
    fi
}

install_export_templates() {
    local template_dir="$1"
    shift
    local entries=("$@")
    local version archive_url temp_dir entry dest
    version="$(godot_version)"
    archive_url="https://downloads.godotengine.org/?flavor=stable&platform=templates&slug=export_templates.tpz&version=$version"
    if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
        echo "[ERROR] Automatic template installation needs curl and unzip."
        if command -v pkg >/dev/null 2>&1; then
            echo "        Command: pkg install curl unzip"
            if prompt_to_install "Run pkg to install curl and unzip?"; then
                pkg install curl unzip || return 1
            else
                return 1
            fi
        elif command -v apt-get >/dev/null 2>&1; then
            if command -v sudo >/dev/null 2>&1; then
                echo "        Command: sudo apt-get install -y curl unzip"
                if prompt_to_install "Run apt-get to install curl and unzip?"; then
                    sudo apt-get install -y curl unzip || return 1
                else
                    return 1
                fi
            else
                echo "        Command: apt-get install -y curl unzip"
                if prompt_to_install "Run apt-get to install curl and unzip?"; then
                    apt-get install -y curl unzip || return 1
                else
                    return 1
                fi
            fi
        elif command -v dnf >/dev/null 2>&1; then
            echo "        Command: sudo dnf install -y curl unzip"
            if prompt_to_install "Run dnf to install curl and unzip?"; then
                sudo dnf install -y curl unzip || return 1
            else
                return 1
            fi
        else
            echo "        Install curl and unzip with the package manager for this host, then rerun the build command."
            return 1
        fi
        if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
            echo "[ERROR] curl and unzip are still unavailable after installation."
            return 1
        fi
    fi

    echo "[INSTALL] Downloading official Godot $version export templates."
    echo "          The complete archive may exceed 1 GB; only the requested files will be installed."
    temp_dir="$(mktemp -d)"
    if ! curl --fail --location --show-error --progress-bar "$archive_url" -o "$temp_dir/export_templates.tpz"; then
        rm -rf "$temp_dir"
        echo "[ERROR] Could not download the Godot export template archive."
        echo "        Check network access, or install templates through the Godot Editor."
        return 1
    fi
    mkdir -p "$template_dir"
    for entry in "${entries[@]}"; do
        dest="$template_dir/$entry"
        if ! unzip -p "$temp_dir/export_templates.tpz" "templates/$entry" > "$dest"; then
            rm -f "$dest"
            rm -rf "$temp_dir"
            echo "[ERROR] The downloaded archive did not contain templates/$entry."
            return 1
        fi
        case "$entry" in
            linux_*) chmod u+x "$dest" ;;
        esac
        echo "[INSTALL] Installed $dest"
    done
    rm -rf "$temp_dir"
}

ensure_export_templates() {
    local target="$1"
    local arch="$2"
    local template_dir entry missing=0
    shift 2
    local entries=("$@")
    template_dir="$(export_template_dir)"
    for entry in "${entries[@]}"; do
        if [ ! -f "$template_dir/$entry" ]; then
            echo "[MISSING] $target export template: $template_dir/$entry"
            missing=1
        fi
    done
    if [ "$missing" -eq 0 ]; then
        echo "[READY] $target export templates for $arch"
        return 0
    fi

    print_template_install_instructions "$target" "$arch" "./build.sh $(printf '%s' "$target" | tr '[:upper:]' '[:lower:]') $arch"
    if prompt_to_install "Download and install the missing $target template(s) now?"; then
        install_export_templates "$template_dir" "${entries[@]}"
        return $?
    fi
    echo "[INFO] Skipping automatic $target template installation."
    return 1
}

ensure_android_sdk() {
    local sdk_root="$ANDROID_SDK_ROOT"
    local sdkmanager=""
    local missing=0
    if [ ! -d "$sdk_root/platform-tools" ]; then
        echo "[MISSING] Android SDK platform-tools: $sdk_root/platform-tools"
        missing=1
    fi
    if [ ! -d "$sdk_root/build-tools" ]; then
        echo "[MISSING] Android SDK build-tools: $sdk_root/build-tools"
        missing=1
    else
        local apksigner_found=0 candidate
        for candidate in "$sdk_root"/build-tools/*/apksigner; do
            if [ -x "$candidate" ]; then
                apksigner_found=1
                break
            fi
        done
        if [ "$apksigner_found" -eq 0 ]; then
            echo "[MISSING] Executable apksigner under $sdk_root/build-tools/"
            missing=1
        fi
    fi
    if [ "$missing" -eq 0 ]; then
        echo "[READY] Android SDK tools at $sdk_root"
        return 0
    fi

    sdkmanager="$sdk_root/cmdline-tools/latest/bin/sdkmanager"
    if [ ! -x "$sdkmanager" ] && command -v sdkmanager >/dev/null 2>&1; then
        sdkmanager="$(command -v sdkmanager)"
    fi
    if [ -x "$sdkmanager" ]; then
        echo "        Install platform-tools and build-tools with:"
        echo "        ANDROID_SDK_ROOT=\"$sdk_root\" \"$sdkmanager\" --install platform-tools 'build-tools;36.0.0'"
        if prompt_to_install "Run sdkmanager to install the missing Android SDK components?"; then
            export ANDROID_SDK_ROOT="$sdk_root"
            "$sdkmanager" --install platform-tools 'build-tools;36.0.0' || return 1
            ensure_android_sdk
            return $?
        fi
    else
        echo "        Install Android SDK Command-line Tools for host $(uname -m), then set:"
        echo "        export ANDROID_SDK_ROOT=\"$HOME/Android/Sdk\""
        echo "        export ANDROID_HOME=\"\$ANDROID_SDK_ROOT\""
        echo "        Then run: \"\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager\" --install platform-tools 'build-tools;36.0.0'"
        echo "        On Termux, also install host-native adb with: pkg install android-tools"
    fi
    return 1
}

check_adb_tool() {
    ADB_BIN="$(command -v adb 2>/dev/null || true)"
    if [ -z "$ADB_BIN" ]; then
        ADB_BIN="$ANDROID_SDK_ROOT/platform-tools/adb"
    fi
    if [ ! -x "$ADB_BIN" ] || ! "$ADB_BIN" version >/dev/null 2>&1; then
        echo "[MISSING] Host-runnable adb for $(uname -m): $ADB_BIN"
        if command -v pkg >/dev/null 2>&1; then
            echo "        Termux: pkg install android-tools"
        elif [ -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
            echo "        \"$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager\" --install platform-tools"
        else
            echo "        Install Android platform-tools built for this host architecture and add adb to PATH."
        fi
        return 1
    fi
    echo "[READY] Host-runnable adb: $ADB_BIN"
    return 0
}

preflight_tests() {
    check_godot
    local host_arch linux_arch android_arch missing_tests=0 package_missing=0 script
    host_arch="$(uname -m)"
    linux_arch="$(detect_linux_arch)" || return 1
    android_arch="$(normalize_android_arch "${ANDROID_ARCH:-arm64-v8a}")" || return 1
    echo "[CHECK] Host: $(uname -s) $host_arch | Godot: $(godot_version)"
    echo "[CHECK] Native Linux package command: ./build.sh linux $linux_arch"
    echo "[CHECK] Android package command: ./build.sh android $android_arch"
    local rust_missing=0
    ensure_rust_build_requirements || rust_missing=1
    for script in scripts/test_map_pipeline.gd scripts/preview_woodland_bush.gd scripts/test_map_scene.gd scripts/test_map_imports.gd scripts/test_map_library.gd scripts/test_edit_controls.gd scripts/test_simulation.gd; do
        if [ ! -f "$PROJECT_DIR/$script" ]; then
            echo "[MISSING] Test script: $PROJECT_DIR/$script"
            missing_tests=1
        fi
    done
    if [ "$missing_tests" -ne 0 ]; then
        echo "[ERROR] Test preflight failed because one or more test scripts are missing."
        return 1
    fi
    if ! ensure_android_sdk; then
        package_missing=1
    fi
    if ! check_adb_tool; then
        echo "[INFO] APK export does not require adb; ./build.sh install will need the host-native tool above."
    fi
    if ! ensure_export_templates "Android" "$android_arch" android_debug.apk; then
        package_missing=1
    fi
    if ! ensure_export_templates "Linux" "$linux_arch" "linux_release.$linux_arch"; then
        package_missing=1
    fi
    if [ "$package_missing" -ne 0 ]; then
        echo "[WARN] Package prerequisites are incomplete; headless tests can run, but the affected package command will stop before exporting."
    else
        echo "[READY] Headless tests and Android/native Linux package prerequisites."
    fi
    if [ "$rust_missing" -ne 0 ]; then
        echo "[WARN] Rust extension prerequisites are incomplete; the GDScript terrain fallback will be used where the extension is unavailable."
    fi
    return 0
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
include_filter="*.json,*.cylh,assets/maps/*/*.png"
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
include_filter="*.json,*.cylh,assets/maps/*/*.png"
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

run_test_step() {
    local script="$1"
    local timeout_sec="${2:-120s}"
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_sec" "$GODOT_BIN" --headless -s "$script"
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "[ERROR] Test script '$script' timed out after $timeout_sec!"
            exit 124
        elif [ $exit_code -ne 0 ]; then
            echo "[ERROR] Test script '$script' failed with exit code $exit_code!"
            exit $exit_code
        fi
    else
        "$GODOT_BIN" --headless -s "$script"
    fi
}

cmd_test() {
    preflight_tests
    run_test_step "scripts/test_map_pipeline.gd"
    run_test_step "scripts/preview_woodland_bush.gd"
    run_test_step "scripts/test_map_scene.gd"
    run_test_step "scripts/test_map_imports.gd"
    run_test_step "scripts/test_map_library.gd"
    echo "[TEST] Running touch controls, world editing, and save/reload tests..."
    run_test_step "scripts/test_edit_controls.gd"
    echo "[TEST] Running automated test suite in headless mode..."
    run_test_step "scripts/test_simulation.gd"
}

cmd_android() {
    check_godot
    local android_arch
    android_arch="$(normalize_android_arch "${1:-${ANDROID_ARCH:-arm64-v8a}}")"
    if ! ensure_android_sdk; then
        echo "[ERROR] Android SDK prerequisites are incomplete. See the setup instructions above."
        exit 1
    fi
    if ! ensure_export_templates "Android" "$android_arch" android_debug.apk; then
        echo "[ERROR] Android export templates are incomplete. See the setup instructions above."
        exit 1
    fi
    generate_export_presets "$android_arch" "x86_64"

    echo "[BUILD] Exporting Android APK..."
    "$GODOT_BIN" --headless --export-debug "Android" "$BUILD_DIR/cylinder.apk"
    echo "[SUCCESS] Exported Android APK to: $BUILD_DIR/cylinder.apk"
}

cmd_linux() {
    check_godot
    local android_arch linux_arch
    android_arch="$(normalize_android_arch "${ANDROID_ARCH:-arm64-v8a}")"
    linux_arch="$(normalize_linux_arch "${1:-${LINUX_ARCH:-$(detect_linux_arch)}}")"
    if ! ensure_export_templates "Linux" "$linux_arch" "linux_release.$linux_arch"; then
        echo "[ERROR] Linux export templates are incomplete. See the setup instructions above."
        exit 1
    fi
    generate_export_presets "$android_arch" "$linux_arch"
    echo "[BUILD] Exporting Linux binary..."
    "$GODOT_BIN" --headless --export-release "Linux" "$BUILD_DIR/cylinder.$linux_arch"
    echo "[SUCCESS] Exported Linux binary to: $BUILD_DIR/cylinder.$linux_arch"
}

cmd_install() {
    if ! check_adb_tool; then
        echo "[ERROR] Device installation cannot continue until host-native adb is installed."
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
    local linux_arch android_arch
    linux_arch="$(detect_linux_arch)" || exit 1
    android_arch="$(normalize_android_arch "${ANDROID_ARCH:-arm64-v8a}")" || exit 1
    echo "[PREFLIGHT] Host: $(uname -s) $(uname -m) | Godot: $(godot_version)"
    ensure_android_sdk || true
    ensure_export_templates "Android" "$android_arch" android_debug.apk || true
    ensure_export_templates "Linux" "$linux_arch" "linux_release.$linux_arch" || true
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
    preflight)
        preflight_tests
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
