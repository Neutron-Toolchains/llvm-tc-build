#!/usr/bin/env bash
source utils.sh
# A Script to build GNU binutils
set -e

# Binutils version
BINUTILS_VER="2_40"

# The main build function that builds GNU binutils.
build_binutils() {

    case $1 in
        "X86")
            echo "Starting Binutils Build for x86-64"
            rm -rf "$2" && mkdir -p "$2" && cd "$2"
            "${BINUTILS_DIR}"/configure \
                --enable-relro \
                --enable-targets=x86_64-pep \
                --prefix="$3" \
                --target=x86_64-pc-linux-gnu \
                --with-pic \
                "${COMMON_BINUTILS_FLAGS[@]}"
            ;;
        "ARM64")
            echo "Starting Binutils Build for arm64"
            rm -rf "$2" && mkdir -p "$2" && cd "$2"
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
            echo "Starting Binutils Build for arm"
            rm -rf "$2" && mkdir -p "$2" && cd "$2"
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
            echo "Invalid target: $1. Supported targets are: ARM,ARM64,X86"
            exit 1
            ;;
    esac

    make -j$(($(nproc --all) + 2)) >/dev/null
    make install -j$(($(nproc --all) + 2)) >/dev/null
}

for arg in "$@"; do
    case "${arg}" in
        "--sync-source-only")
            if [[ -d ${BINUTILS_DIR} ]]; then
                cd "${BINUTILS_DIR}"
                if ! git status &>/dev/null; then
                    echo "GNU binutils dir found but not a git repo, recloning"
                    cd "${BUILDDIR}" && rm -rf "${BINUTILS_DIR}" && binutils_clone "${BINUTILS_VER}"
                else
                    echo "Existing binutils repo found, skipping clone"
                    echo "Fetching new changes"
                    binutils_pull "${BINUTILS_VER}"
                    cd "${BUILDDIR}"
                fi
            else
                echo "cloning GNU binutils repo"
                binutils_clone "${BINUTILS_VER}"
            fi
            exit 0
            ;;
    esac
done

for arg in "$@"; do
    case "${arg}" in
        "--install-dir"*)
            INSTALL_DIR="${arg#*--install-dir}"
            INSTALL_DIR=${INSTALL_DIR:1}
            ;;
        "--build-dir"*)
            BINUTILS_BUILD="${arg#*--build-dir}"
            BINUTILS_BUILD=${BINUTILS_BUILD:1}
            ;;
    esac
done

for arg in "$@"; do
    case "${arg}" in
        "--targets"*)
            targets="${arg#*--targets}"
            targets=${targets:1}
            IFS=', ' read -r -a archs <<<"${targets}"
            echo "Build dir path: ${BINUTILS_BUILD}"
            echo "Installing at: ${INSTALL_DIR}"
            if [[ -d ${BINUTILS_DIR} ]]; then
                cd "${BINUTILS_DIR}"
                if ! git status &>/dev/null; then
                    echo "GNU binutils dir found but not a git repo, recloning"
                    cd "${BUILDDIR}" && rm -rf "${BINUTILS_DIR}" && binutils_clone "${BINUTILS_VER}"
                else
                    echo "Existing binutils repo found, skipping clone"
                    echo "Fetching new changes"
                    binutils_pull "${BINUTILS_VER}"
                    cd "${BUILDDIR}"
                fi
            else
                echo "cloning GNU binutils repo"
                binutils_clone "${BINUTILS_VER}"
            fi
            for arch in "${archs[@]}"; do
                build_binutils "${arch}" "${BINUTILS_BUILD}" "${INSTALL_DIR}"
            done
            exit 0
            ;;
        *)
            echo "Invalid argument passed: ${arg}"
            exit 1
            ;;
    esac
done
