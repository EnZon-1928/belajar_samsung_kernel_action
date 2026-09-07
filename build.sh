#!/usr/bin/env bash

set -e

SECONDS=0
USER="Noir"
HOSTNAME="norprjkt-lab"
DEVICE_TARGET=${DEVICE_TARGET:-"A235F"}
DEFCONFIG=${DEFCONFIG:-"a23_eur_open_defconfig"}
LTO=${LTO:-"none"}
CLANG_VERSION=${CLANG_VERSION:-"neutron-clang23"}
TC_DIR="$HOME/neutron-clang"
GCC_DIR="$HOME/androidcc"
OUT_DIR="$(pwd)/out"
KCFLAGS_W=${KCFLAGS_W:-"false"}
BUILD_STOCK=${BUILD_STOCK:-"false"}

export TERM=xterm
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
reset='\033[0m'

msg() { echo -e "${blue}INFO: ${reset}$1"; }
error() {
    echo -e "${red}ERROR: ${reset}$1"
    exit 1
}

send_telegram() {
    local file="$1"
    local md5="$2"
    local time="$(($3 / 60))"

    if [[ -z "$TG_TOKEN" || -z "$TG_CHAT_ID" ]]; then
        msg "Telegram credentials missing. Skipping upload."
        return
    fi

    msg "Uploading to Telegram..."
    curl -s -F document=@$file \
        -F chat_id="$TG_CHAT_ID" \
        -F caption="$msg_bar" \
        -F "disable_web_page_preview=true" \
        "https://api.telegram.org/bot$TG_TOKEN/sendDocument"
    msg "Upload completed!"
}

setup_deps() {
    set -e
    echo "INFO: Changing to faster APT mirror..."
    sudo sed -i 's/archive.ubuntu.com/kartolo.sby.datautama.net.id/g' /etc/apt/sources.list
    sudo sed -i 's/security.ubuntu.com/kartolo.sby.datautama.net.id/g' /etc/apt/sources.list
    
    echo "INFO: Updating package lists..."
    sudo apt update -y || { echo "ERROR: apt update failed"; exit 1; }
    
    echo "INFO: Installing dependencies..."
    sudo apt install -y --no-install-recommends \
        bc bison ccache cpio curl flex git libssl-dev lz4 perl python-is-python3 tar wget zstd
    
    echo "INFO: Dependencies installation completed!"
}

_setup_toolchain() {
    msg "Downloading Clang: $CLANG_VERSION ..."
    
    # Clean existing directory
    rm -rf "$TC_DIR"
    mkdir -p "$TC_DIR"
    
    case "$CLANG_VERSION" in
        "neutron-clang23")
            wget -q https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/26052026/neutron-clang-26052026.tar.zst -O /tmp/clang.tar.zst
            msg "Extracting Neutron Clang 23..."
            tar -xf /tmp/clang.tar.zst -C "$TC_DIR"
            ;;
        "aosp-22")
            wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-r584948.tar.gz -O /tmp/clang.tar.gz
            msg "Extracting AOSP Clang 22..."
            mkdir -p "$TC_DIR/temp"
            tar -xf /tmp/clang.tar.gz -C "$TC_DIR/temp"
            if [ -d "$TC_DIR/temp/clang-r584948" ]; then
                mv "$TC_DIR/temp/clang-r584948"/* "$TC_DIR/"
            else
                mv "$TC_DIR/temp"/* "$TC_DIR/"
            fi
            rm -rf "$TC_DIR/temp"
            ;;
        "aosp-23")
            wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-r614150.tar.gz -O /tmp/clang.tar.gz
            msg "Extracting AOSP Clang 23..."
            mkdir -p "$TC_DIR/temp"
            tar -xf /tmp/clang.tar.gz -C "$TC_DIR/temp"
            if [ -d "$TC_DIR/temp/clang-r614150" ]; then
                mv "$TC_DIR/temp/clang-r614150"/* "$TC_DIR/"
            else
                mv "$TC_DIR/temp"/* "$TC_DIR/"
            fi
            rm -rf "$TC_DIR/temp"
            ;;
        "aosp-21")
            wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-r510928.tar.gz -O /tmp/clang.tar.gz
            msg "Extracting AOSP Clang 21..."
            mkdir -p "$TC_DIR/temp"
            tar -xf /tmp/clang.tar.gz -C "$TC_DIR/temp"
            if [ -d "$TC_DIR/temp/clang-r510928" ]; then
                mv "$TC_DIR/temp/clang-r510928"/* "$TC_DIR/"
            else
                mv "$TC_DIR/temp"/* "$TC_DIR/"
            fi
            rm -rf "$TC_DIR/temp"
            ;;
        "aosp-20")
            wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-r547379.tar.gz -O /tmp/clang.tar.gz
            msg "Extracting AOSP Clang 20..."
            mkdir -p "$TC_DIR/temp"
            tar -xf /tmp/clang.tar.gz -C "$TC_DIR/temp"
            if [ -d "$TC_DIR/temp/clang-r547379" ]; then
                mv "$TC_DIR/temp/clang-r547379"/* "$TC_DIR/"
            else
                mv "$TC_DIR/temp"/* "$TC_DIR/"
            fi
            rm -rf "$TC_DIR/temp"
            ;;
        "aosp-12")
            wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/bd96dfe349c962681f0e5388af874c771ef96670/clang-r416183b.tar.gz -O /tmp/clang.tar.gz
            msg "Extracting AOSP Clang 12..."
            mkdir -p "$TC_DIR/temp"
            tar -xf /tmp/clang.tar.gz -C "$TC_DIR/temp"
            if [ -d "$TC_DIR/temp/clang-r416183b" ]; then
                mv "$TC_DIR/temp/clang-r416183b"/* "$TC_DIR/"
            else
                mv "$TC_DIR/temp"/* "$TC_DIR/"
            fi
            rm -rf "$TC_DIR/temp"
            ;;
        *)
            msg "Unknown CLANG_VERSION: $CLANG_VERSION, using neutron-clang23 as default"
            wget -q https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/26052026/neutron-clang-26052026.tar.zst -O /tmp/clang.tar.zst
            msg "Extracting Neutron Clang 23..."
            tar -xf /tmp/clang.tar.zst -C "$TC_DIR"
            ;;
    esac
    
    # Verify Clang installation
    if [ -f "$TC_DIR/bin/clang" ]; then
        msg "✅ Clang installed successfully: $($TC_DIR/bin/clang --version | head -n1)"
    else
        msg "⚠️ Clang not found in expected location, searching..."
        CLANG_PATH=$(find "$TC_DIR" -name "clang" -type f 2>/dev/null | head -n1)
        if [ -n "$CLANG_PATH" ]; then
            CLANG_DIR=$(dirname "$CLANG_PATH")
            msg "Found Clang at: $CLANG_PATH"
            mkdir -p "$TC_DIR/bin"
            ln -sf "$CLANG_PATH" "$TC_DIR/bin/clang"
            CLANGPP_PATH=$(find "$TC_DIR" -name "clang++" -type f 2>/dev/null | head -n1)
            if [ -n "$CLANGPP_PATH" ]; then
                ln -sf "$CLANGPP_PATH" "$TC_DIR/bin/clang++"
            fi
            msg "✅ Clang symlinks created successfully!"
            msg "Clang version: $($TC_DIR/bin/clang --version | head -n1)"
        else
            error "❌ Clang installation failed! Clang binary not found in $TC_DIR"
        fi
    fi
    
    msg "Downloading GCC (AndroidCC) ..."
    if [ -d "$GCC_DIR" ]; then
        rm -rf "$GCC_DIR"
    fi
    
    # Try multiple GCC sources
    msg "Attempting to download GCC from blxyzY..."
    if git clone --depth=1 https://github.com/blxyzY/toolchain -b androidcc-4.9 "$GCC_DIR" 2>/dev/null; then
        msg "✅ GCC downloaded from blxyzY"
    else
        msg "Failed to download from blxyzY, trying Google AOSP..."
        if git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 -b master "$GCC_DIR" 2>/dev/null; then
            msg "✅ GCC downloaded from Google AOSP"
        else
            msg "Failed to download from Google AOSP, trying alternative source..."
            if git clone --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 -b lineage-21.0 "$GCC_DIR" 2>/dev/null; then
                msg "✅ GCC downloaded from LineageOS"
            else
                error "❌ All GCC download attempts failed!"
            fi
        fi
    fi
    
    # Create symlink for GCC
    cd "$GCC_DIR/bin"
    if [ ! -f "aarch64-linux-android-gcc" ]; then
        GCC_BIN=$(ls | grep "aarch64-linux-android-gcc" | head -1)
        if [ -n "$GCC_BIN" ]; then
            ln -sf "$GCC_BIN" aarch64-linux-android-gcc
            msg "Created symlink for aarch64-linux-android-gcc"
        fi
    fi
    cd ../..
    
    # Verify GCC installation
    if [ -f "$GCC_DIR/bin/aarch64-linux-android-gcc" ]; then
        msg "✅ GCC installed successfully: $($GCC_DIR/bin/aarch64-linux-android-gcc --version | head -n1)"
    else
        # Try to find GCC binary
        GCC_PATH=$(find "$GCC_DIR" -name "aarch64-linux-android-gcc" -type f 2>/dev/null | head -n1)
        if [ -n "$GCC_PATH" ]; then
            GCC_BIN_DIR=$(dirname "$GCC_PATH")
            mkdir -p "$GCC_DIR/bin"
            ln -sf "$GCC_PATH" "$GCC_DIR/bin/aarch64-linux-android-gcc"
            msg "✅ GCC symlink created from: $GCC_PATH"
        else
            error "❌ GCC installation failed! No GCC binary found."
        fi
    fi
    
    # Clean up temp files
    rm -f /tmp/clang.tar.* 2>/dev/null || true
    
    msg "✅ Toolchain setup completed!"
}

setup_toolchain() {
    if [ "$UPDATE_TOOLCHAINS" = "true" ]; then
        msg "Cleaning up old toolchains cache.."
        rm -rf $TC_DIR $GCC_DIR
        if [ -d ~/.ccache ]; then
            rm -rf ~/.ccache
            mkdir -p ~/.ccache
        fi
    fi
    if [ ! -d "$TC_DIR" ] || [ ! -d "$GCC_DIR" ]; then
        _setup_toolchain
    else
        msg "Toolchain already exists"
        # Verify existing toolchain
        if [ -f "$TC_DIR/bin/clang" ] && [ -f "$GCC_DIR/bin/aarch64-linux-android-gcc" ]; then
            msg "Existing Clang: $($TC_DIR/bin/clang --version | head -n1)"
            msg "Existing GCC: $($GCC_DIR/bin/aarch64-linux-android-gcc --version | head -n1)"
        else
            msg "Toolchain corrupted, re-downloading..."
            rm -rf "$TC_DIR" "$GCC_DIR"
            _setup_toolchain
        fi
    fi
    exit 0
}

configure_lto() {
    msg "Configuring LTO: ${LTO:-none}"
    case "${LTO:-none}" in
        "thin")
            ./scripts/config --file out/.config --disable LTO_NONE
            ./scripts/config --file out/.config --enable LTO
            ./scripts/config --file out/.config --enable THINLTO
            ./scripts/config --file out/.config --enable LTO_CLANG
            ./scripts/config --file out/.config --enable ARCH_SUPPORTS_LTO_CLANG
            ./scripts/config --file out/.config --enable ARCH_SUPPORTS_THINLTO
            msg "LTO: Thin mode enabled"
            ;;
        "full")
            ./scripts/config --file out/.config --disable LTO_NONE
            ./scripts/config --file out/.config --enable LTO
            ./scripts/config --file out/.config --disable THINLTO
            ./scripts/config --file out/.config --enable LTO_CLANG
            ./scripts/config --file out/.config --enable ARCH_SUPPORTS_LTO_CLANG
            ./scripts/config --file out/.config --enable ARCH_SUPPORTS_THINLTO
            msg "LTO: Full mode enabled"
            ;;
        *)
            ./scripts/config --file out/.config --enable LTO_NONE
            ./scripts/config --file out/.config --disable LTO
            ./scripts/config --file out/.config --disable THINLTO
            ./scripts/config --file out/.config --disable LTO_CLANG
            ./scripts/config --file out/.config --enable ARCH_SUPPORTS_LTO_CLANG
            ./scripts/config --file out/.config --enable ARCH_SUPPORTS_THINLTO
            msg "LTO: Disabled"
            ;;
    esac
}

regen_defconfig() {
    [ -z "$DEVICE_TARGET" ] && error "DEVICE_TARGET is required to regen!"
    mkdir -p "$OUT_DIR"
    msg "Generating minimal defconfig for $DEVICE_TARGET..."
    make $BUILD_FLAGS "$DEFCONFIG"
    make $BUILD_FLAGS savedefconfig
    msg "Done!"
}

case "$1" in
"--setup-deps")
    setup_deps
    exit 0
    ;;
"--fetch-toolchains")
    setup_toolchain
    exit 0
    ;;
"--clean")
    msg "Cleaning..."
    rm -rf "$OUT_DIR" *.zip 2>/dev/null
    make clean mrproper
    exit 0
    ;;
esac

[ -z "$DEVICE_TARGET" ] && error "DEVICE_TARGET cannot be empty!"
[ -z "$DEFCONFIG" ] && error "DEFCONFIG cannot be empty!"

msg "Using defconfig: $DEFCONFIG"
msg "LTO: ${LTO:-none}"
msg "Clang version: $CLANG_VERSION"

export KBUILD_BUILD_USER=$USER
export KBUILD_BUILD_HOST=$HOSTNAME
export PATH="$TC_DIR/bin:$GCC_DIR/bin:$PATH"
export ARCH=arm64
export LLVM_IAS=1
export LLVM=1
export CROSS_COMPILE="$GCC_DIR/bin/aarch64-linux-android-"
export CLANG_TRIPLE="aarch64-linux-gnu-"

# Verify toolchain paths before build
msg "Verifying toolchain paths..."
if [ ! -d "$TC_DIR" ]; then
    error "Clang directory not found at: $TC_DIR"
fi
if [ ! -d "$GCC_DIR" ]; then
    error "GCC directory not found at: $GCC_DIR"
fi
if [ ! -f "$TC_DIR/bin/clang" ]; then
    error "Clang binary not found at: $TC_DIR/bin/clang"
fi
if [ ! -f "$GCC_DIR/bin/aarch64-linux-android-gcc" ]; then
    error "GCC binary not found at: $GCC_DIR/bin/aarch64-linux-android-gcc"
fi

msg "Clang: $($TC_DIR/bin/clang --version | head -n1)"
msg "GCC: $($GCC_DIR/bin/aarch64-linux-android-gcc --version | head -n1)"

msg "KCFLAGS=-w is $KCFLAGS_W"
[ "$KCFLAGS_W" = "true" ] && export KCFLAGS="-w"

export KCFLAGS="$KCFLAGS -Wno-error=unused-command-line-argument -Wno-error=gnu -Wno-error=register -Wno-error=unknown-attributes -Wno-error=incompatible-pointer-types -Wno-error=pedantic -Wno-error=deprecated-declarations -Wno-error=incompatible-function-pointer-types"

COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "untracked")
[ -z "$CI_ZIPNAME" ] && ZIPNAME="rsuntk_$DEVICE_TARGET-$(date '+%Y%m%d-%H%M')-$COMMIT_HASH.zip" || ZIPNAME=$CI_ZIPNAME
BUILD_FLAGS="O=$OUT_DIR ARCH=arm64 -j$(nproc --all)"

if [ "$1" = "--regen-defconfig" ]; then
    regen_defconfig
    exit 0
fi

mkdir -p "$OUT_DIR"
msg "Starting compilation for $DEVICE_TARGET using $DEFCONFIG..."
make $BUILD_FLAGS $DEFCONFIG
configure_lto
make $BUILD_FLAGS

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANYKERNEL_DIR="$ROOT_DIR/external/anykernel3"

if [ ! -d "$ANYKERNEL_DIR" ]; then
    error "AnyKernel3 directory not found at: $ANYKERNEL_DIR"
fi

if [ -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
    msg "Kernel compiled successfully! Packaging..."

    cp "$OUT_DIR/arch/arm64/boot/Image" "$ANYKERNEL_DIR/"

    cat > utsrelease.c << 'EOF'
#include <stdio.h>
#include "out/include/generated/utsrelease.h"
int main() { printf("%s\n", UTS_RELEASE); return 0; }
EOF
    
    UTSRELEASE=""
    if gcc -CC utsrelease.c -o getutsrel 2>/dev/null && [ -f "./getutsrel" ]; then
        UTSRELEASE=$(./getutsrel)
        rm -f getutsrel utsrelease.c
    fi

    if [ -z "$UTSRELEASE" ]; then
        UTSRELEASE=$(make kernelversion 2>/dev/null || echo "unknown")
    fi

    if [ -f "$ANYKERNEL_DIR/anykernel.sh" ]; then
        sed -i "s/kernel\.string=.*/kernel.string=$UTSRELEASE/" "$ANYKERNEL_DIR/anykernel.sh"
        msg "Updated kernel.string to: $UTSRELEASE"
    fi

    pushd "$ANYKERNEL_DIR" >/dev/null
    zip -r9 "$ROOT_DIR/$ZIPNAME" ./*
    popd >/dev/null

    msg "ZIP created: $ZIPNAME"

    MD5_CHECK=$(md5sum "$ROOT_DIR/$ZIPNAME" | cut -d' ' -f1)
    msg "MD5: $MD5_CHECK"

    send_telegram "$ROOT_DIR/$ZIPNAME" "$MD5_CHECK" "$SECONDS"

    [ "$DO_CLEAN" = "true" ] && rm -rf "$OUT_DIR"

    echo -e "\n${green}Build completed in $((SECONDS / 60)) minute(s)!${reset}"
    msg "Output Zip: $ZIPNAME (at $ROOT_DIR)"
else
    error "Compilation failed! Image file not found."
fi
