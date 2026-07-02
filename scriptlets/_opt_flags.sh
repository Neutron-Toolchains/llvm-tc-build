#!/usr/bin/env bash
#
# Copyright (C) 2026 Dakkshesh <beakthoven@gmail.com>. All rights reserved.
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

set -eou pipefail

source "$(pwd)"/scriptlets/_utils.sh
export NPROC=$(getconf _NPROCESSORS_ONLN)
export GLOBAL_CFLAGS=(
    "-pipe"
    "-O3"
    "-integrated-as"
    "-ffunction-sections"
    "-fdata-sections"
    "-fcf-protection=none"
    "-funroll-loops"
)

export STRUCTURAL_CFLAGS=(
    "-fvisibility=hidden"
    "-fvisibility-inlines-hidden"
    "-funique-internal-linkage-names"
    "-fno-semantic-interposition"
    "-fno-plt"
    "-fno-trapping-math"
    "-fno-math-errno"
    "-mharden-sls=none"
    "-ffp-contract=fast"
    "-fexcess-precision=fast"
    "-mllvm" "-enable-gvn-hoist=1"
    "-mllvm" "-enable-dfa-jump-thread=1"
    "-mllvm" "-adce-remove-loops"
)

export PGO_CFLAGS=(
    "-mllvm" "-enable-chr=true"
    "-fsplit-machine-functions"
)

export VECTORIZATION_PASSES=(
    "-mllvm" "-vectorizer-maximize-bandwidth"
    "-mllvm" "-unroll-runtime-multi-exit"
    "-mllvm" "-slp-vectorize-hor-store"
    "-mllvm" "-extra-vectorizer-passes"
    "-mllvm" "-enable-unroll-and-jam"
    "-mllvm" "-enable-masked-interleaved-mem-accesses"
    "-mllvm" "-enable-loopinterchange"
    "-mllvm" "-enable-loop-flatten"
    "-mllvm" "-enable-loop-distribute"
    "-mllvm" "-enable-interleaved-mem-accesses"
    "-mllvm" "-aggressive-ext-opt"
)

_POLLY_PASSES=(
    "-mllvm" "-polly"
    "-mllvm" "-polly-vectorizer=stripmine"
    "-mllvm" "-polly-tiling"
    "-mllvm" "-polly-scheduling=dynamic"
    "-mllvm" "-polly-scheduling-chunksize=1"
    "-mllvm" "-polly-run-inliner"
    "-mllvm" "-polly-run-dce"
    "-mllvm" "-polly-reschedule"
    "-mllvm" "-polly-postopts"
    "-mllvm" "-polly-optimizer=isl"
    "-mllvm" "-polly-num-threads=0"
    "-mllvm" "-polly-loopfusion-greedy"
    "-mllvm" "-polly-isl-arg=--no-schedule-serialize-sccs"
    "-mllvm" "-polly-enable-optree"
    "-mllvm" "-polly-enable-delicm"
    "-mllvm" "-polly-dependences-use-reductions"
    "-mllvm" "-polly-dependences-computeout=0"
    "-mllvm" "-polly-dependences-analysis-type=value-based"
    "-mllvm" "-polly-ast-use-context"
    "-mllvm" "-polly-2nd-level-tiling"
)
export POLLY_PASSES=()
if [[ ${USE_POLLY:-1} -eq 1 ]]; then
    POLLY_PASSES=("${_POLLY_PASSES[@]}")
fi

export FULL_OPT_CFLAGS=(
    "-march=x86-64-v3"
    "${GLOBAL_CFLAGS[@]}"
    "-flto=thin"
    "-fwhole-program-vtables"
    "-fsplit-lto-unit"
    "-mprefer-vector-width=256"
    "${STRUCTURAL_CFLAGS[@]}"
    "${PGO_CFLAGS[@]}"
    "${POLLY_PASSES[@]}"
    "${VECTORIZATION_PASSES[@]}"
)

export GLOBAL_LDFLAGS=(
    "-Wl,-O3"
    "-Wl,--gc-sections"
    "-Wl,--as-needed"
    "-Wl,-z,now"
    "-Wl,--icf=safe"
    "-Wl,-Bsymbolic-functions"
    "-Wl,-z,keep-text-section-prefix"
    "-Wl,-z,max-page-size=0x200000"
)

export LTO_LDFLAGS=(
    "-flto=thin"
    "-Wl,--lto-O3"
    "-Wl,--lto-CGO3"
    "-Wl,--thinlto-jobs=${NPROC}"
)

export FULL_LDFLAGS=(
    "${GLOBAL_LDFLAGS[@]}"
    "${LTO_LDFLAGS[@]}"
)
