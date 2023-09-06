#!/usr/bin/env bash
source utils.sh
# A Script to build GNU binutils
set -e

# Binutils version
BINUTILS_VER="2_41"

for arg in "$@"; do
    case "${arg}" in
        "--use-jemalloc")
            USE_JEMALLOC=1
            ;;
    esac
done

if [[ ${USE_JEMALLOC} -eq 1 ]]; then
    build_jemalloc() {
        cd "${BUILDDIR}"
        jemalloc_fetch_vars
        if [[ ${NO_JEMALLOC} -eq 1 ]]; then
            bash "${BUILDDIR}/build_jemalloc.sh" --shallow-clone
        fi
    }
fi

# The main build function that builds GNU binutils.
build_binutils() {

    if [[ ${USE_JEMALLOC} -eq 1 ]]; then
        echo "Building jemalloc libs if not built already"
        build_jemalloc
    fi

    export CC="gcc"
    export CXX="g++"
    export CFLAGS="-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections -fgraphite-identity -floop-nest-optimize -falign-functions=32 -fno-math-errno -fno-trapping-math -fomit-frame-pointer -mharden-sls=none"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-Wl,-O3,--sort-common,--as-needed,-z,now,--strip-debug"
    if [[ ${USE_JEMALLOC} -eq 1 ]]; then
        export LDFLAGS+=" ${JEMALLOC_FLAGS}"
    fi

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

    make -j$(($(getconf _NPROCESSORS_ONLN) + 2)) >/dev/null
    make install -j$(($(getconf _NPROCESSORS_ONLN) + 2)) >/dev/null
    unset CC CXX CFLAGS CXXFLAGS LDFLAGS
}

for arg in "$@"; do
    case "${arg}" in
        "--no-update")
            NO_UPDATE=1
            ;;
    esac
done

for arg in "$@"; do
    case "${arg}" in
        "--shallow-clone")
            SHALLOW_CLONE=1
            ;;
    esac
done

for arg in "$@"; do
    case "${arg}" in
        "--sync-source-only")
            if [[ -d ${BINUTILS_DIR} ]]; then
                if [[ ${NO_UPDATE} -eq 0 ]]; then
                    echo "Existing binutils source found. Fetching new changes"
                    cd "${BINUTILS_DIR}"
                    if [[ ${SHALLOW_CLONE} -eq 1 ]]; then
                        binutils_fetch "fetch" "${BINUTILS_VER}" "--depth=1"
                        git reset --hard FETCH_HEAD
                        git clean -dfx
                    else
                        is_shallow=$(git rev-parse --is-shallow-repository 2>/dev/null)
                        if [ "$is_shallow" = "true" ]; then
                            binutils_fetch "fetch" "${BINUTILS_VER}" "--depth=1"
                            git reset --hard FETCH_HEAD
                            git clean -dfx
                        else
                            git reset --hard HEAD
                            binutils_fetch "pull" "${BINUTILS_VER}"
                        fi
                    fi
                    sed -i '/^development=/s/true/false/' bfd/development.sh
                    cd "${BUILDDIR}"
                fi
            else
                echo "Cloning binutils repo"
                if [[ ${SHALLOW_CLONE} -eq 1 ]]; then
                    binutils_clone "${BINUTILS_VER}" "--depth=1"
                else
                    binutils_clone "${BINUTILS_VER}"
                fi
                sed -i '/^development=/s/true/false/' binutils-gdb/bfd/development.sh
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
                if [[ ${NO_UPDATE} -eq 0 ]]; then
                    echo "Existing binutils source found. Fetching new changes"
                    cd "${BINUTILS_DIR}"
                    if [[ ${SHALLOW_CLONE} -eq 1 ]]; then
                        binutils_fetch "fetch" "${BINUTILS_VER}" "--depth=1"
                        git reset --hard FETCH_HEAD
                        git clean -dfx
                    else
                        if $(git rev-parse --is-shallow-repository); then
                            binutils_fetch "fetch" "${BINUTILS_VER}" "--depth=1"
                            git reset --hard FETCH_HEAD
                            git clean -dfx
                        else
                            git reset --hard HEAD
                            binutils_fetch "pull" "${BINUTILS_VER}"
                        fi
                    fi
                    sed -i '/^development=/s/true/false/' bfd/development.sh
                    cd "${BUILDDIR}"
                fi
            else
                echo "Cloning binutils repo"
                if [[ ${SHALLOW_CLONE} -eq 1 ]]; then
                    binutils_clone "${BINUTILS_VER}" "--depth=1"
                else
                    binutils_clone "${BINUTILS_VER}"
                fi
                sed -i '/^development=/s/true/false/' binutils-gdb/bfd/development.sh
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
