#!/usr/bin/env bash
# Some common functions and varibles to be sourced by our build scripts

# Global variables
BUILDDIR="$(pwd)"
export BUILDDIR

# Variables and arrays for build_clang.sh
export CLEAN_BUILD=1
export POLLY_OPT=0
export BOLT_OPT=0
export LLVM_OPT=0
export USE_MOLD=0
export FINAL_INSTALL_DIR="install"
export CI=0
export TEMP_BINTUILS_BUILD="${BUILDDIR}/temp-binutils-build"
export TEMP_BINTUILS_INSTALL="${BUILDDIR}/temp-binutils"
export SHALLOW_CLONE=0
LLVM_LD_JOBS=$(getconf _NPROCESSORS_ONLN)
export LLVM_LD_JOBS

export COMMON_OPT_FLAGS_LD="-Wl,-O3,--sort-common,--as-needed,-z,now,--lto-O3,--strip-debug"

export COMMON_OPT_FLAGS=(
    "-O3"
    "-ffunction-sections"
    "-fdata-sections"
    "-flto=thin"
    "-fsplit-lto-unit"
    "-falign-functions=32"
    "-fno-math-errno"
    "-fno-trapping-math"
    "-fomit-frame-pointer"
    "-mharden-sls=none"
)

export POLLY_OPT_FLAGS=(
    "-fopenmp"
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

export LLVM_OPT_FLAGS=(
    "-mllvm -aggressive-ext-opt"
    "-mllvm -allow-unroll-and-jam"
    "-mllvm -enable-loop-distribute"
    "-mllvm -enable-loop-flatten"
    "-mllvm -enable-loopinterchange"
    "-mllvm -enable-unroll-and-jam"
    "-mllvm -extra-vectorizer-passes"
    "-mllvm -interleave-small-loop-scalar-reduction"
    "-mllvm -unroll-runtime-multi-exit"
)

export BOLT_OPT_FLAGS=(
    "--dyno-stats"
    "--eliminate-unreachable"
    "--frame-opt=hot"
    "--icf=1"
    "--inline-all"
    "--inline-ap"
    "--jump-tables=basic"
    "--peepholes=all"
    "--plt=hot"
    "--reorder-blocks=ext-tsp"
    "--reorder-functions=hfsort+"
    "--sctc-mode=always"
    "--simplify-conditional-tail-calls"
    "--split-all-cold"
    "--split-eh"
    "--split-functions"
    "--thread-count=$(getconf _NPROCESSORS_ONLN)"
    "--use-gnu-stack"
)

export COMMON_BINUTILS_FLAGS=(
    'CC=gcc'
    'CXX=g++'
    'CFLAGS=-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections -fgraphite-identity -floop-nest-optimize -falign-functions=32 -fno-math-errno -fno-trapping-math -fomit-frame-pointer -mharden-sls=none'
    'CXXFLAGS=-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections -fgraphite-identity -floop-nest-optimize -falign-functions=32 -fno-math-errno -fno-trapping-math -fomit-frame-pointer -mharden-sls=none'
    'LDFLAGS=-Wl,-O3,--sort-common,--as-needed,-z,now,--strip-debug'
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

export BINUTILS_DIR="${BUILDDIR}/binutils-gdb"
export INSTALL_DIR="${BUILDDIR}/install"
export BINUTILS_BUILD="${BUILDDIR}/binutils-build"
export NO_UPDATE=0

tgsend() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="@neutron_updates" -d "disable_web_page_preview=true" -d "parse_mode=html" -d text="$1"
}

# Functions
llvm_fetch() {

    if ! git "$1" https://github.com/llvm/llvm-project.git "$2"; then
        echo "llvm-project git ${1}: Failed" >&2
        exit 1
    fi
}

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

get_linux_tarball() {

    if [[ -e linux-"$1".tar.xz ]]; then
        echo "Existing linux-$1 tarball found, skipping download"
    else
        echo "Downloading linux-$1 tarball"
        wget "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$1.tar.xz"
    fi
    tar xf linux-"$1".tar.xz
}

clear_if_unused() {
    if [[ $1 -eq 0 ]]; then
        unset "$2"
    fi
}
