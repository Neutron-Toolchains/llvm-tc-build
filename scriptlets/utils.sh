#!/usr/bin/env bash
#
# Copyright (C) 2025 Dakkshesh <beakthoven@gmail.com>. All rights reserved.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

# Some common functions and varibles to be sourced by our build scripts

####################
# Global variables #
####################
export WORK_DIR="$(pwd)"
export SRC_DIR="${WORK_DIR}/sources"
export BUILD_DIR="${WORK_DIR}/build"
export SHALLOW_CLONE=0
export AVX_OPT=0
export STOCK_PATH="${PATH}"

######################
# Optimization flags #
######################

# AVX2 OPT
export ARCH_GENERIC="-march=x86-64 -mtune=generic"
export ARCH_AVX2="-march=x86-64-v3 -mprefer-vector-width=256"

# Clang
export CLANG_OPT_LDFLAGS=(
    "-Wl,-O3"
    "-Wl,--lto-O3"
    "-Wl,--sort-common"
    "-Wl,--as-needed"
    "-Wl,-z,now"
    "-Wl,--strip-debug"
    "-Wl,--gc-sections"
    "-Wl,--icf=all"
    "-Wl,-Bsymbolic"
    "-Wl,-Bsymbolic-functions"
)

export CLANG_OPT_CFLAGS=(
    "-pipe"
    "-O3"
    "-integrated-as"
    "-fvisibility=hidden"
    "-fvisibility-inlines-hidden"
    "-fwhole-program-vtables"
    "-funroll-loops"
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

export FULL_LLVM_LDFLAGS=(
    "-Wl,-Bstatic"
    "-stdlib=libc++"
    "--unwindlib=libunwind"
    "-lc++"
    "-lc++abi"
    "-Wl,-Bdynamic"
)

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

########
# Misc #
########
tgsend() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="@NeutronTC_Updates" -d "disable_web_page_preview=true" -d "parse_mode=html" -d text="$1"
}

clear_if_unused() {
    if [[ $1 -eq 0 ]]; then
        unset "$2"
    fi
}

check_if_exists() {
    if [ -d "$1" ] && [ "$(ls -A "$1")" ]; then
        echo "dir: $1 exists."
    else
        echo "dir: $1 does not exist."
        exit 1
    fi
}

git_get() {
    local repo="$1"
    local branch="$2"
    local dir="$3"

    if [[ -d $dir ]]; then
        echo "Directory $dir already exists, skipping git clone."
        echo "Checking for updates..."
        cd "$dir"
        git pull origin "$branch"
    else
        echo "Cloning $repo into $dir"
        git clone "$repo" "$dir" -b "$branch"
    fi

}

download_and_extract() {
    local target_dir="$1"
    local url="$2"
    local archive_name
    archive_name=$(basename "$url")

    if [ -d "$target_dir" ] && [ "$(ls -A "$target_dir")" ]; then
        echo "Skipping download: $target_dir already exists and is not empty"
    else
        echo "Downloading and extracting $archive_name into $target_dir"
        mkdir -p "$target_dir"
        cd "$target_dir"
        wget -q "$url"
        tar -xf "$archive_name"
        rm -f "$archive_name"
    fi
}
