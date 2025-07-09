#!/usr/bin/env bash
# Some common functions and varibles to be sourced by our build scripts

####################
# Global variables #
####################
BUILDDIR="$(pwd)"
export BUILDDIR
export SHALLOW_CLONE=0
export AVX_OPT=0

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

######################
# Optimization flags #
######################

# AVX2 OPT
export NO_AVX_FLAGS="-march=x86-64 -mtune=generic"
export AVX_FLAGS="-march=x86-64-v3 -mprefer-vector-width=256"

# Polly
export POLLY_PASS_FLAGS=(
    "-mllvm -polly"
    "-mllvm -polly-vectorizer=stripmine"
    "-mllvm -polly-tiling"
    "-mllvm -polly-scheduling=dynamic"
    "-mllvm -polly-scheduling-chunksize=1"
    "-mllvm -polly-run-inliner"
    "-mllvm -polly-run-dce"
    "-mllvm -polly-reschedule"
    "-mllvm -polly-postopts"
    "-mllvm -polly-optimizer=isl"
    "-mllvm -polly-omp-backend=LLVM"
    "-mllvm -polly-num-threads=0"
    "-mllvm -polly-loopfusion-greedy"
    "-mllvm -polly-isl-arg=--no-schedule-serialize-sccs"
    "-mllvm -polly-invariant-load-hoisting"
    "-mllvm -polly-dependences-computeout=0"
    "-mllvm -polly-dependences-analysis-type=value-based"
    "-mllvm -polly-ast-use-context"
)

# Extra LLVM passes
export LLVM_PASS_FLAGS=(
    "-mllvm -vectorizer-maximize-bandwidth"
    "-mllvm -unroll-runtime-multi-exit"
    "-mllvm -slp-vectorize-hor-store"
    "-mllvm -extra-vectorizer-passes"
    "-mllvm -enable-unroll-and-jam"
    "-mllvm -enable-masked-interleaved-mem-accesses"
    "-mllvm -enable-loopinterchange"
    "-mllvm -enable-loop-flatten"
    "-mllvm -enable-loop-distribute"
    "-mllvm -enable-interleaved-mem-accesses"
    "-mllvm -enable-gvn-hoist=1"
    "-mllvm -enable-ext-tsp-block-placement=1"
    "-mllvm -enable-dfa-jump-thread=1"
    "-mllvm -enable-cond-stores-vec"
    "-mllvm -aggressive-ext-opt"
    "-mllvm -adce-remove-loops"
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
export CLANG_OPT_LDFLAGS="-Wl,-O3,--sort-common,--as-needed,-z,now,--lto-O3,--strip-debug,--gc-sections"
export CLANG_OPT_CFLAGS=(
    "-pipe"
    "-O3"
    "-integrated-as"
    "-fwhole-program-vtables"
    "-funroll-loops"
    "-fstack-arrays"
    "-fsplit-lto-unit"
    "-freciprocal-math"
    "-fomit-frame-pointer"
    "-fno-trapping-math"
    "-fno-semantic-interposition"
    "-fno-plt"
    "-fno-math-errno"
    "-flto=thin"
    "-ffunction-sections"
    "-ffp-contract=fast"
    "-fexcess-precision=fast"
    "-fdata-sections"
    "-fcf-protection=none"
    "-falign-functions=32"
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
