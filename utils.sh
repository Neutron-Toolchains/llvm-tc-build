#!/usr/bin/env bash
# Some common functions and varibles to be sourced by our build scripts

####################
# Global variables #
####################
BUILDDIR="$(pwd)"
export BUILDDIR
export SHALLOW_CLONE=0
export AVX_OPT=0

############
# Jemalloc #
############
export USE_JEMALLOC=0
export JEMALLOC_BUILD_DIR="${BUILDDIR}/jemalloc-build"

jemalloc_fetch_vars() {
    if [[ -e "${JEMALLOC_BUILD_DIR}/bin/jemalloc-config" ]]; then
        export JEMALLOC_LIB_DIR="$(${JEMALLOC_BUILD_DIR}/bin/jemalloc-config --libdir)"
        export JEMALLOC_LIBS="$(${JEMALLOC_BUILD_DIR}/bin/jemalloc-config --libs)"
        export JEMALLOC_FLAGS="-L${JEMALLOC_LIB_DIR} -Wl,--push-state -Wl,-whole-archive -ljemalloc_pic -Wl,--pop-state ${JEMALLOC_LIBS}"
        export NO_JEMALLOC=0
    else
        export NO_JEMALLOC=1
    fi
}

jemalloc_clone() {

    if ! git clone "https://github.com/jemalloc/jemalloc.git" -b "$1" "$2"; then
        echo "jemalloc git clone: Failed" >&2
        exit 1
    fi
}

jemalloc_fetch() {

    if ! git "$1" "https://github.com/jemalloc/jemalloc.git" "$2" "$3"; then
        echo "jemalloc git $1: Failed" >&2
        exit 1
    fi
}

################
# LLVM Builder #
################
export CLEAN_BUILD=1
export POLLY_OPT=0
export BOLT_OPT=0
export LLVM_OPT=0
export USE_MOLD=0
export FINAL_INSTALL_DIR="install"
export CI=0

llvm_fetch() {

    if ! git "$1" https://github.com/llvm/llvm-project.git "$2"; then
        echo "llvm-project git ${1}: Failed" >&2
        exit 1
    fi
}

get_linux_tarball() {

    if [[ -e linux-"$1".tar.xz ]]; then
        echo "Existing linux-$1 tarball found, skipping download"
    else
        echo "Downloading linux-$1 tarball"
        wget "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$1.tar.xz"
    fi
    tar xf linux-"$1".tar.xz
}

####################
# Binutils builder #
####################
export BINUTILS_DIR="${BUILDDIR}/binutils-gdb"
export INSTALL_DIR="${BUILDDIR}/install"
export BINUTILS_BUILD="${BUILDDIR}/binutils-build"
export NO_UPDATE=0
export COMMON_BINUTILS_ARGS=(
    '--disable-docs'
    '--disable-gdb'
    '--disable-gdbserver'
    '--disable-libdecnumber'
    '--disable-readline'
    '--disable-sim'
    '--enable-deterministic-archives'
    '--enable-gold'
    '--enable-ld=default'
    '--enable-lto'
    '--enable-new-dtags'
    '--enable-plugins'
    '--enable-threads'
    '--quiet'
    '--with-pkgversion=Neutron Binutils'
    '--disable-werror'
    '--disable-compressed-debug-sections'
)

binutils_clone() {

    if ! git clone "https://sourceware.org/git/binutils-gdb.git" -b "binutils-$1-branch" "$2"; then
        echo "binutils git clone: Failed" >&2
        exit 1
    fi
}

binutils_fetch() {

    if ! git "$1" "https://sourceware.org/git/binutils-gdb.git" "binutils-$2-branch" "$3"; then
        echo "binutils git $1: Failed" >&2
        exit 1
    fi
}

######################
# Optimization flags #
######################

# AVX2 OPT
export NO_AVX_FLAGS="-mtune=generic"
export BARE_AVX_FLAGS="-mavx -mavx2 -mfma -msse3 -mssse3 -msse4.1 -msse4.2 -mf16c -mprefer-vector-width=128"
export AVX_FLAGS="-mtune=haswell ${BARE_AVX_FLAGS}"

# Polly
export POLLY_PASS_FLAGS=(
    "-mllvm -polly"
    "-mllvm -polly-ast-use-context"
    "-mllvm -polly-dependences-analysis-type=value-based"
    "-mllvm -polly-dependences-computeout=0"
    "-mllvm -polly-enable-delicm"
    "-mllvm -polly-invariant-load-hoisting"
    "-mllvm -polly-loopfusion-greedy"
    "-mllvm -polly-num-threads=0"
    "-mllvm -polly-omp-backend=LLVM"
    "-mllvm -polly-optimizer=isl"
    "-mllvm -polly-parallel"
    "-mllvm -polly-postopts"
    "-mllvm -polly-reschedule"
    "-mllvm -polly-run-dce"
    "-mllvm -polly-run-inliner"
    "-mllvm -polly-scheduling-chunksize=1"
    "-mllvm -polly-scheduling=dynamic"
    "-mllvm -polly-tiling"
    "-mllvm -polly-vectorizer=stripmine"
)

# Extra LLVM passes
export LLVM_PASS_FLAGS=(
    "-mllvm -enable-masked-interleaved-mem-accesses"
    "-mllvm -enable-interleaved-mem-accesses"
    "-mllvm -extra-vectorizer-passes"
    "-mllvm -enable-cond-stores-vec"
    "-mllvm -slp-vectorize-hor-store"
    "-mllvm -enable-loopinterchange"
    "-mllvm -enable-loop-distribute"
    "-mllvm -enable-unroll-and-jam"
    "-mllvm -enable-loop-flatten"
    "-mllvm -unroll-runtime-multi-exit"
    "-mllvm -aggressive-ext-opt"
    "-mllvm -adce-remove-loops"
    "-mllvm -enable-ext-tsp-block-placement"
    "-mllvm -enable-gvn-hoist"
    "-mllvm -enable-dfa-jump-thread"
    "-mllvm -vectorizer-maximize-bandwidth"
)

# BOLT 
export BOLT_ARGS=(
    "--dyno-stats"
    "--eliminate-unreachable"
    "--frame-opt=hot"
    "--icf=1"
    "--plt=hot"
    "--reorder-blocks=ext-tsp"
    "--reorder-functions=hfsort+"
    "--split-all-cold"
    "--split-eh"
    "--split-functions"
    "--thread-count=$(getconf _NPROCESSORS_ONLN)"
    "--use-gnu-stack"
)

# Clang
export CLANG_OPT_LDFLAGS="-Wl,-O3,--sort-common,--as-needed,-z,now,--lto-O3,--strip-debug,-zmax-page-size=0x200000"
export CLANG_OPT_CFLAGS=(
    "-O3"
    "-funroll-loops"
    "-ffunction-sections"
    "-fdata-sections"
    "-flto=thin"
    "-fsplit-lto-unit"
    "-falign-functions=32"
    "-fno-math-errno"
    "-fno-trapping-math"
    "-fomit-frame-pointer"
    "-mharden-sls=none"
    "-ffp-contract=fast"
)

# GCC
export GCC_OPT_LDFLAGS="-Wl,-O3,--sort-common,--as-needed,-z,now,--strip-debug"
export GCC_OPT_CFLAGS=(
    '-O3'
    '-ffp-contract=fast'
    '-pipe'
    '-ffunction-sections'
    '-fdata-sections'
    '-fgraphite-identity'
    '-floop-nest-optimize'
    '-falign-functions=32'
    '-fno-math-errno'
    '-fno-trapping-math'
    '-fomit-frame-pointer'
    '-mharden-sls=none'
)

########
# Misc #
########
tgsend() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="@neutron_updates" -d "disable_web_page_preview=true" -d "parse_mode=html" -d text="$1"
}

clear_if_unused() {
    if [[ $1 -eq 0 ]]; then
        unset "$2"
    fi
}
