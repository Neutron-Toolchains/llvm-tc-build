#!/usr/bin/env bash
source utils.sh
# A Script to build jemalloc lib
set -e

JEMALLOC_DIR="${BUILDDIR}/jemalloc"
JEMALLOC_VER="5.3.0"

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

jemalloc_source_prep() {
    if [[ -d ${JEMALLOC_DIR} ]]; then
        if [[ ${NO_UPDATE} -eq 0 ]]; then
            echo "Existing jemalloc source found. Fetching new changes"
            cd "${JEMALLOC_DIR}"
            if [[ ${SHALLOW_CLONE} -eq 1 ]]; then
                jemalloc_fetch "fetch" "${JEMALLOC_VER}" "--depth=1"
                git reset --hard FETCH_HEAD
                git clean -dfx
            else
                is_shallow=$(git rev-parse --is-shallow-repository 2>/dev/null)
                if [ "$is_shallow" = "true" ]; then
                    jemalloc_fetch "fetch" "${JEMALLOC_VER}" "--depth=1"
                    git reset --hard FETCH_HEAD
                    git clean -dfx
                else
                    git reset --hard HEAD
                    jemalloc_fetch "pull" "${JEMALLOC_VER}"
                fi
            fi
            sed -i "s/-g3/-g0/g" configure.ac
            cd "${BUILDDIR}"
        fi
    else
        echo "Cloning jemalloc repo"
        if [[ ${SHALLOW_CLONE} -eq 1 ]]; then
            jemalloc_clone "${JEMALLOC_VER}" "--depth=1"
        else
            jemalloc_clone "${JEMALLOC_VER}"
        fi
        sed -i "s/-g3/-g0/g" jemalloc/configure.ac
    fi
}

jemalloc_build() {
    cd "${JEMALLOC_DIR}"
    rm -rf "${JEMALLOC_BUILD_DIR}" && mkdir -p "${JEMALLOC_BUILD_DIR}"
    export CC="gcc"
    export CXX="g++"
    export CFLAGS="-march=x86-64 -mtune=generic -O3 -pipe -ffunction-sections -fdata-sections -fgraphite-identity -floop-nest-optimize -falign-functions=32 -fno-math-errno -fno-trapping-math -fomit-frame-pointer -mharden-sls=none"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-Wl,-O3,--sort-common,--as-needed,-z,now,--strip-debug"
    ./configure \
        --enable-autogen \
        --prefix="${JEMALLOC_BUILD_DIR}" \
        --enable-static \
        --disable-shared \
        --disable-stats \
        --disable-doc \
        --disable-debug
    make -j"$(getconf _NPROCESSORS_ONLN)"
    make install -j"$(getconf _NPROCESSORS_ONLN)"

    # Now that build is done, set jemalloc specific vars
    jemalloc_var_set

    # Rename the static jemalloc lib to avoid conflicts with the .so one
    cp "${JEMALLOC_LIB_DIR}/libjemalloc.a" "${JEMALLOC_LIB_DIR}/libjemalloc_static.a"
}

for arg in "$@"; do
    case "${arg}" in
        "--sync-source-only")
            jemalloc_source_prep
            exit 0
            ;;
    esac
done

jemalloc_source_prep
jemalloc_build
