#!/usr/bin/env bash
# Some common functions and varibles to be sourced by our build scripts

# Variables
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
    '--dyno-stats'
    '--eliminate-unreachable'
    '--frame-opt=hot'
    '--icf=1'
    '--indirect-call-promotion=all'
    '--inline-all'
    '--inline-ap'
    '--jump-tables=aggressive'
    '--peepholes=all'
    '--plt=hot'
    '--reorder-blocks=ext-tsp'
    '--reorder-functions-use-hot-size'
    '--reorder-functions=hfsort+'
    '--split-all-cold'
    '--split-eh'
    '--split-functions'
    "--thread-count=$(nproc --all)"
    '--use-gnu-stack'
)

export COMMON_BINUTILS_FLAGS=(
    'CC="gcc"'
    'CXX="g++"'
    'CFLAGS="-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections -fgraphite-identity -floop-nest-optimize"'
    'CXXFLAGS="-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections -fgraphite-identity -floop-nest-optimize"'
    'LDFLAGS="-Wl,-O3,--sort-common,--as-needed,-z,now,--strip-debug"'
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
    '--with-pkgversion="Neutron Binutils"'
    '--disable-werror'
    '--disable-compressed-debug-sections'
)

export BINUTILS_VER="2_40"

# Functions
llvm_clone() {

    if ! git clone https://github.com/llvm/llvm-project.git; then
        echo "llvm-project git clone: Failed" >&2
        exit 1
    fi
}

llvm_pull() {

    if ! git pull https://github.com/llvm/llvm-project.git; then
        echo "llvm-project git Pull: Failed" >&2
        exit 1
    fi
}

binutils_clone() {

    if ! git clone "https://sourceware.org/git/binutils-gdb.git" -b "binutils-${BINUTILS_VER}-branch"; then
        echo "binutils git clone: Failed" >&2
        exit 1
    fi
}

binutils_pull() {

    if ! git "pull https://sourceware.org/git/binutils-gdb.git" "binutils-${BINUTILS_VER}-branch"; then
        echo "binutils git Pull: Failed" >&2
        exit 1
    fi
}

get_linux_tarball() {

    if [ -e linux-"$1".tar.xz ]; then
        echo "Existing linux-$1 tarball found, skipping download"
        tar xf linux-"$1".tar.xz
    else
        echo "Downloading linux-$1 tarball"
        wget "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$1.tar.xz"
        tar xf linux-"$1".tar.xz
    fi
}

clear_if_unused() {
    if [[ $1 -eq 0 ]]; then
        unset "$2"
    fi
}
