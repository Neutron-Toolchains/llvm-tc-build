#!/usr/bin/env bash
source utils.sh
# A Script to build GNU binutils
set -e

# Specify some variables.
BUILDDIR=$(pwd)
BINUTILS_DIR="${BUILDDIR}/binutils-gdb"
INSTALL_DIR="${BUILDDIR}/install"
BINUTILS_BUILD="${BUILDDIR}/binutils-build"

# The main build function that builds GNU binutils.
build_binutils() {

    if [[ -d "$2" ]]; then
        rm -rf "$2"
    fi
    mkdir -p "$2"
    cd "$2"
    case $1 in
        "X86")
            "${BINUTILS_DIR}"/configure \
                --enable-relro \
                --enable-targets=x86_64-pep \
                --prefix="$3" \
                --target=x86_64-pc-linux-gnu \
                --with-pic \
                "${COMMON_BINUTILS_FLAGS[@]}"
            ;;
        "ARM64")
            "${BINUTILS_DIR}"/configure \
                --disable-multilib \
                --disable-nls \
                --prefix="$3" \
                --target=aarch64-linux-gnu \
                --with-gnu-as \
                --with-gnu-ld \
                "${COMMON_BINUTILS_FLAGS[@]}"
            ;;
        "ARM")
            "${BINUTILS_DIR}"/configure \
                --disable-multilib \
                --disable-nls \
                --prefix="$3" \
                --target=arm-linux-gnueabi \
                --with-gnu-as \
                --with-gnu-ld \
                "${COMMON_BINUTILS_FLAGS[@]}"
            ;;
        *)
            echo "You have specified a wrong architecture type or one that we do not support! Do specify the correct one or feel free to make a PR with the relevant changes to add support to the architecture that you are trying to build this toolchain for."
            exit 1
            ;;
    esac

    make -j$(($(nproc --all) + 2)) >/dev/null
    make install -j$(($(nproc --all) + 2)) >/dev/null
}

# This is where the build starts.
echo "Starting Binutils Build"
echo "Starting Binutils Build for x86-64"
build_binutils "X86" "${BINUTILS_BUILD}" "${INSTALL_DIR}" || (
    echo "x86-64 Build failed!"
    exit 1
)
echo "Starting Binutils Build for arm"
build_binutils "ARM" "${BINUTILS_BUILD}" "${INSTALL_DIR}" || (
    echo "arm Build failed!"
    exit 1
)
echo "Starting Binutils Build for arm64"
build_binutils "ARM64" "${BINUTILS_BUILD}" "${INSTALL_DIR}" || (
    echo "arm64 Build failed!"
    exit 1
)
