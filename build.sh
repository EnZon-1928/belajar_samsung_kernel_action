#!/usr/bin/env bash

set -e

SECONDS=0
USER="Builder"
HOSTNAME="GitHub-Actions"
DEVICE_TARGET=${DEVICE_TARGET:-"A235F"}
DEFCONFIG=${DEFCONFIG:-"a23_eur_open_defconfig"}
LTO=${LTO:-"none"}
CLANG_VERSION=${CLANG_VERSION:-"aosp-12"}
TC_DIR="$HOME/neutron-clang"
GCC_DIR="$HOME/androidcc"
OUT_DIR="$(pwd)/out"
KCFLAGS_W=${KCFLAGS_W:-"false"}

export TERM=xterm
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
reset='\033[0m'

msg() { echo -e "${blue}INFO: ${reset}$1"; }
error() { echo -e "${red}ERROR: ${reset}$1"; exit 1; }

setup_deps() {
    set -e
    msg "Updating package lists and installing dependencies..."
    sudo apt update -y || error "apt update failed."
    sudo apt install -y --no-install-recommends \
        bc bison ccache cpio curl flex git libssl-dev lz4 perl python-is-python3 tar wget zstd
    msg "Dependencies installed successfully."
}

_setup_toolchain() {
    msg "Downloading Toolchain: $CLANG_VERSION..."
    rm -rf "$TC_DIR"
    mkdir -p "$TC_DIR"
    
    local CLANG_URL=""
    case "$CLANG_VERSION" in
        "neutron-clang23") CLANG_URL="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/26052026/neutron-clang-26052026.tar.zst" ;;
        "aosp-23") CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-r614150.tar.gz" ;;
        "aosp-22") CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-r584948.tar.gz" ;;
        "aosp-21") CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-r510928.tar.gz" ;;
        "aosp-20") CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-r547379.tar.gz" ;;
        "aosp-12") CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/bd96dfe349c962681f0e5388af874c771ef96670/clang-r416183b.tar.gz" ;;
        *) msg "Unknown version, defaulting to aosp-12"; CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/bd96dfe349c962681f0e5388af874c771ef96670/clang-r416183b.tar.gz" ;;
    esac

    if [[ "$CLANG_URL" == *".tar.zst" ]]; then
        wget -q "$CLANG_URL" -O /tmp/clang.tar.zst
        tar -xf /tmp/clang.tar.zst -C "$TC_DIR"
    else
        wget -q "$CLANG_URL" -O /tmp/clang.tar.gz
        mkdir -p "$TC_DIR/temp"
        tar -xf /tmp/clang.tar.gz -C "$TC_DIR/temp"
        mv "$TC_DIR/temp"/* "$TC_DIR/" 2>/dev/null || mv "$TC_DIR/temp"/*/* "$TC_DIR/"
        rm -rf "$TC_DIR/temp"
    fi
    
    if [ -f "$TC_DIR/bin/clang" ]; then
        msg "Clang verified: $($TC_DIR/bin/clang --version | head -n1)"
    else
        CLANG_PATH=$(find "$TC_DIR" -name "clang" -type f 2>/dev/null | head -n1)
        if [ -n "$CLANG_PATH" ]; then
            mkdir -p "$TC_DIR/bin"
            ln -sf "$CLANG_PATH" "$TC_DIR/bin/clang"
            CLANGPP_PATH=$(find "$TC_DIR" -name "clang++" -type f 2>/dev/null | head -n1)
            [ -n "$CLANGPP_PATH" ] && ln -sf "$CLANGPP_PATH" "$TC_DIR/bin/clang++"
        else
            error "Clang binary missing after extraction."
        fi
    fi
    
    msg "Downloading GCC (AndroidCC)..."
    rm -rf "$GCC_DIR"
    if git clone --depth=1 https://github.com/blxyzY/toolchain -b androidcc-4.9 "$GCC_DIR" 2>/dev/null; then
        msg "GCC fetched from blxyzY."
    elif git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 -b master "$GCC_DIR" 2>/dev/null; then
        msg "GCC fetched from Google AOSP."
    elif git clone --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 -b lineage-21.0 "$GCC_DIR" 2>/dev/null; then
        msg "GCC fetched from LineageOS."
    else
        error "All GCC download mirrors failed."
    fi
    
    cd "$GCC_DIR/bin"
    if [ ! -f "aarch64-linux-android-gcc" ]; then
        GCC_BIN=$(ls | grep "aarch64-linux-android-gcc" | head -1)
        [ -n "$GCC_BIN" ] && ln -sf "$GCC_BIN" aarch64-linux-android-gcc
    fi
    cd ../..
    
    if [ -f "$GCC_DIR/bin/aarch64-linux-android-gcc" ]; then
        msg "GCC verified: $($GCC_DIR/bin/aarch64-linux-android-gcc --version | head -n1)"
    else
        error "GCC binary missing after extraction."
    fi
    
    rm -f /tmp/clang.tar.* 2>/dev/null || true
    msg "Toolchains provisioned successfully."
}

setup_toolchain() {
    if [ "$UPDATE_TOOLCHAINS" = "true" ]; then
        msg "Purging toolchain cache..."
        rm -rf $TC_DIR $GCC_DIR ~/.ccache
    fi
    if [ ! -d "$TC_DIR" ] || [ ! -d "$GCC_DIR" ]; then
        _setup_toolchain
    else
        msg "Verifying existing toolchains..."
        if [ -f "$TC_DIR/bin/clang" ] && [ -f "$GCC_DIR/bin/aarch64-linux-android-gcc" ]; then
            msg "Found Clang: $($TC_DIR/bin/clang --version | head -n1)"
            msg "Found GCC: $($GCC_DIR/bin/aarch64-linux-android-gcc --version | head -n1)"
        else
            msg "Toolchain corrupted. Re-downloading..."
            _setup_toolchain
        fi
    fi
    exit 0
}

configure_lto() {
    msg "Applying LTO Policy: ${LTO^^}"
    case "${LTO:-none}" in
        "thin")
            ./scripts/config --file out/.config --disable LTO_NONE
            ./scripts/config --file out/.config --enable LTO
            ./scripts/config --file out/.config --enable THINLTO
            ./scripts/config --file out/.config --enable LTO_CLANG
            ./scripts/config --file out/.config --enable ARCH_SUPPORTS_LTO_CLANG
            ./scripts/config --file out/.config --enable ARCH_SUPPORTS_THINLTO
            ;;
        "full")
            ./scripts/config --file out/.config --disable LTO_NONE
            ./scripts/config --file out/.config --enable LTO
            ./scripts/config --file out/.config --disable THINLTO
            ./scripts/config --file out/.config --enable LTO_CLANG
            ./scripts/config --file out/.config --enable ARCH_SUPPORTS_LTO_CLANG
            ./scripts/config --file out/.config --enable ARCH_SUPPORTS_THINLTO
            ;;
        *)
            ./scripts/config --file out/.config --enable LTO_NONE
            ./scripts/config --file out/.config --disable LTO
            ./scripts/config --file out/.config --disable THINLTO
            ./scripts/config --file out/.config --disable LTO_CLANG
            ./scripts/config --file out/.config --enable ARCH_SUPPORTS_LTO_CLANG
            ./scripts/config --file out/.config --enable ARCH_SUPPORTS_THINLTO
            ;;
    esac
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
    msg "Purging output directories..."
    rm -rf "$OUT_DIR" *.zip 2>/dev/null
    make clean mrproper
    exit 0
    ;;
esac

[ -z "$DEVICE_TARGET" ] && error "DEVICE_TARGET is undefined."
[ -z "$DEFCONFIG" ] && error "DEFCONFIG is undefined."

msg "Target Device: $DEVICE_TARGET"
msg "Defconfig: $DEFCONFIG"

export KBUILD_BUILD_USER=$USER
export KBUILD_BUILD_HOST=$HOSTNAME
export PATH="$TC_DIR/bin:$GCC_DIR/bin:$PATH"
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
export CROSS_COMPILE="$GCC_DIR/bin/aarch64-linux-android-"
export CLANG_TRIPLE="aarch64-linux-gnu-"

if [ ! -f "$TC_DIR/bin/clang" ] || [ ! -f "$GCC_DIR/bin/aarch64-linux-android-gcc" ]; then
    error "Compiler binaries missing. Ensure toolchains are fully downloaded."
fi

[ "$KCFLAGS_W" = "true" ] && export KCFLAGS="-w"
export KCFLAGS="$KCFLAGS -Wno-error=unused-command-line-argument -Wno-error=gnu -Wno-error=register -Wno-error=unknown-attributes -Wno-error=incompatible-pointer-types -Wno-error=pedantic -Wno-error=deprecated-declarations -Wno-error=incompatible-function-pointer-types"

COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "untracked")
ZIPNAME=${CI_ZIPNAME:-"kernel_$DEVICE_TARGET-$(date '+%Y%m%d-%H%M')-$COMMIT_HASH.zip"}
BUILD_FLAGS="O=$OUT_DIR ARCH=arm64 -j$(nproc --all)"

msg "Disabling HDM & DEFEX strict compilation in security/Makefile..."
if [ -f "security/Makefile" ]; then
    sed -i '/hdm/d' security/Makefile
    sed -i '/defex/d' security/Makefile
fi

msg "Injecting LLVM_IAS bypass for legacy ARM64 assembly files..."
for makefile_dir in arch/arm64/crypto arch/arm64/lib; do
    if [ -f "$makefile_dir/Makefile" ]; then
        sed -i '/ccflags-y += -fno-integrated-as/d' "$makefile_dir/Makefile"
        if ! grep -q "aflags-y += -fno-integrated-as" "$makefile_dir/Makefile"; then
            echo "aflags-y += -fno-integrated-as" >> "$makefile_dir/Makefile"
            echo "asflags-y += -fno-integrated-as" >> "$makefile_dir/Makefile"
        fi
    fi
done

msg "Patching kernel/modules.c for vendor module compatibility..."
if [ -f "kernel/modules.c" ]; then
    sed -i 's/return -ENOEXEC;/\/\/return -ENOEXEC;/g' kernel/modules.c
fi

mkdir -p "$OUT_DIR"
msg "Generating base defconfig..."
make $BUILD_FLAGS $DEFCONFIG

msg "Applying security and module overrides..."
./scripts/config --file "$OUT_DIR/.config" --disable MODVERSIONS
./scripts/config --file "$OUT_DIR/.config" --disable MODULE_SIG
./scripts/config --file "$OUT_DIR/.config" --disable MODULE_SIG_FORCE
./scripts/config --file "$OUT_DIR/.config" --disable MODULE_SIG_ALL
./scripts/config --file "$OUT_DIR/.config" --disable MODULE_SIG_SHA512
./scripts/config --file "$OUT_DIR/.config" --disable MODULE_SIG_HASH

./scripts/config --file "$OUT_DIR/.config" --disable UH
./scripts/config --file "$OUT_DIR/.config" --disable UH_RKP
./scripts/config --file "$OUT_DIR/.config" --disable TIMA
./scripts/config --file "$OUT_DIR/.config" --disable TIMA_LKMAUTH
./scripts/config --file "$OUT_DIR/.config" --disable TIMA_LKM_BLOCK
./scripts/config --file "$OUT_DIR/.config" --disable TIMA_LKMAUTH_CODE_PROT
./scripts/config --file "$OUT_DIR/.config" --disable FIVE
./scripts/config --file "$OUT_DIR/.config" --disable KNOX_KAP
./scripts/config --file "$OUT_DIR/.config" --disable SEC_RESTRICT_ROOTING

./scripts/config --file "$OUT_DIR/.config" --disable SECURITY_DEFEX
./scripts/config --file "$OUT_DIR/.config" --disable PROCA
./scripts/config --file "$OUT_DIR/.config" --disable INTEGRITY
./scripts/config --file "$OUT_DIR/.config" --disable INTEGRITY_SIGNATURE
./scripts/config --file "$OUT_DIR/.config" --disable INTEGRITY_ASYMMETRIC_KEYS
./scripts/config --file "$OUT_DIR/.config" --disable INTEGRITY_TRUSTED_KEYRING
./scripts/config --file "$OUT_DIR/.config" --disable INTEGRITY_AUDIT

./scripts/config --file "$OUT_DIR/.config" --disable CRYPTO_SHA1_ARM64_CE
./scripts/config --file "$OUT_DIR/.config" --disable CRYPTO_SHA2_ARM64_CE
./scripts/config --file "$OUT_DIR/.config" --disable CRYPTO_GHASH_ARM64_CE
./scripts/config --file "$OUT_DIR/.config" --disable CRYPTO_AES_ARM64_CE_CCM
./scripts/config --file "$OUT_DIR/.config" --disable CRYPTO_AES_ARM64_CE_BLK
./scripts/config --file "$OUT_DIR/.config" --disable CRYPTO_CRCT10DIF_ARM64_CE
./scripts/config --file "$OUT_DIR/.config" --disable CRYPTO_CRC32_ARM64_CE

msg "Applying SELinux Policy: ${SELINUX^^}..."
if [ "$SELINUX" = "permissive" ]; then
    ./scripts/config --file "$OUT_DIR/.config" --set-str CMDLINE "androidboot.selinux=permissive"
    ./scripts/config --file "$OUT_DIR/.config" --enable SECURITY_SELINUX_DEVELOP
    ./scripts/config --file "$OUT_DIR/.config" --disable SECURITY_SELINUX_ALWAYS_ENFORCE
    ./scripts/config --file "$OUT_DIR/.config" --enable SECURITY_SELINUX_ALWAYS_PERMISSIVE
else
    ./scripts/config --file "$OUT_DIR/.config" --disable SECURITY_SELINUX_DEVELOP
    ./scripts/config --file "$OUT_DIR/.config" --enable SECURITY_SELINUX_ALWAYS_ENFORCE
    ./scripts/config --file "$OUT_DIR/.config" --disable SECURITY_SELINUX_ALWAYS_PERMISSIVE
fi

make $BUILD_FLAGS olddefconfig

configure_lto
msg "Initiating compilation phase..."
make $BUILD_FLAGS

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANYKERNEL_DIR="$ROOT_DIR/external/anykernel3"

if [ ! -d "$ANYKERNEL_DIR" ]; then
    error "AnyKernel3 directory not found at $ANYKERNEL_DIR"
fi

if [ -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
    msg "Compilation successful. Packaging build artifacts..."

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
    fi

    pushd "$ANYKERNEL_DIR" >/dev/null
    zip -r9 "$ROOT_DIR/$ZIPNAME" ./*
    popd >/dev/null

    MD5_CHECK=$(md5sum "$ROOT_DIR/$ZIPNAME" | cut -d' ' -f1)
    msg "Output ZIP: $ZIPNAME | Checksum (MD5): $MD5_CHECK"

    [ "$DO_CLEAN" = "true" ] && rm -rf "$OUT_DIR"

    echo -e "\n${green}Build completed successfully in $((SECONDS / 60)) minute(s).${reset}"
else
    error "Build failed. Image executable not found."
fi
