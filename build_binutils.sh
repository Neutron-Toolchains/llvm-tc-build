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
build() {

    if [[ -d "${BINUTILS_BUILD}" ]]; then
        rm -rf "${BINUTILS_BUILD}"
    fi
    mkdir -p "${BINUTILS_BUILD}"
    cd "${BINUTILS_BUILD}"
    case $1 in
        "X86")
            "${BINUTILS_DIR}"/configure \
                --target=x86_64-pc-linux-gnu \
                --enable-targets=x86_64-pep \
                --enable-relro \
                --with-pic \
                --prefix="${INSTALL_DIR}" \
                "${COMMON_BINUTILS_FLAGS[@]}"
            ;;
        "ARM64")
            "${BINUTILS_DIR}"/configure \
                --target=aarch64-linux-gnu \
                --prefix="${INSTALL_DIR}" \
                --disable-nls \
                --with-gnu-as \
                --with-gnu-ld \
                --disable-multilib \
                "${COMMON_BINUTILS_FLAGS[@]}"
            ;;
        "ARM")
            "${BINUTILS_DIR}"/configure \
                --target=arm-linux-gnueabi \
                --prefix="${INSTALL_DIR}" \
                --disable-nls \
                --with-gnu-as \
                --with-gnu-ld \
                --disable-multilib \
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
build "X86" || (
    echo "x86-64 Build failed!"
    exit 1
)
echo "Starting Binutils Build for arm"
build "ARM" || (
    echo "arm Build failed!"
    exit 1
)
echo "Starting Binutils Build for arm64"
build "ARM64" || (
    echo "arm64 Build failed!"
    exit 1
)
