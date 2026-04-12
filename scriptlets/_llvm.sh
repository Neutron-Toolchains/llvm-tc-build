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

source "$(pwd)"/scriptlets/_opt_flags.sh

################
# LLVM Builder #
################

export CLEAN_BUILD=1
export USE_MOLD=0
export CI=0
export SHALLOW_CLONE=0

export LLVM_SRC_DIR="${SRC_DIR}/llvm-project"
export MLGO_DIR="${SRC_DIR}/mlgo-models"

export MLGO_X86_REGALLOC="${MLGO_DIR}/x86/regalloc"
export MLGO_X86_INLINE="${MLGO_DIR}/x86/inline"
export MLGO_ARM64_REGALLOC="${MLGO_DIR}/arm64/regalloc"
export MLGO_ARM64_INLINE="${MLGO_DIR}/arm64/inline/model"

export LLVM_STAGE0_BUILD_DIR="${BUILD_DIR}/stage0-bootstrap"
export LLVM_STAGE0_INSTALL_DIR="${LLVM_STAGE0_BUILD_DIR}"
export LLVM_STAGE0_BIN_DIR="${LLVM_STAGE0_INSTALL_DIR}/bin"

export LLVM_STAGE2_BUILD_DIR="${BUILD_DIR}/stage2-pgo-instr"
export LLVM_STAGE2_INSTALL_DIR="${LLVM_STAGE2_BUILD_DIR}"

export LLVM_STAGE3_BUILD_DIR="${BUILD_DIR}/stage3-cspgo-instr"
export LLVM_STAGE3_INSTALL_DIR="${LLVM_STAGE3_BUILD_DIR}"

export LLVM_STAGE4_LABELS_BUILD_DIR="${BUILD_DIR}/stage4-labels"
export LLVM_STAGE4_LABELS_INSTALL_DIR="${LLVM_STAGE4_LABELS_BUILD_DIR}"

export LLVM_STAGE4_FINAL_BUILD_DIR="${BUILD_DIR}/stage4-final"
export LLVM_STAGE4_FINAL_INSTALL_DIR="${LLVM_STAGE4_FINAL_BUILD_DIR}"

export LLVM_INSTALL_DIR="${WORK_DIR}/install"

export PROFILE_DIR="${BUILD_DIR}/profiles"
export PGO_RAW_DIR="${PROFILE_DIR}/pgo-raw"
export CSPGO_RAW_DIR="${PROFILE_DIR}/cspgo-raw"
export PROPELLER_RAW_DIR="${PROFILE_DIR}/propeller-raw"
export PGO_PROFDATA="${PROFILE_DIR}/pgo.profdata"
export CSPGO_PROFDATA="${PROFILE_DIR}/cspgo.profdata"
export PROPELLER_CC_PROFILE="${PROFILE_DIR}/cc_profile.txt"
export PROPELLER_LD_PROFILE="${PROFILE_DIR}/ld_profile.txt"

export MIMALLOC_STATIC="${LLVM_STAGE0_INSTALL_DIR}/lib/libmimalloc.a"

export STATIC_LINK_FLAGS=(
    "-Wl,--push-state -Wl,--whole-archive ${MIMALLOC_STATIC} -Wl,--pop-state"
    "-static-libstdc++"
)

export PROFILING_COMMON=(
    "-fprofile-update=atomic"
    "-mllvm" "-enable-value-profiling"
)

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
        wget "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$1.tar.xz"
    fi
    rm -rf linux-"$1"
    tar xf linux-"$1".tar.xz
}

parse_llvm_args() {
    for arg in "$@"; do
        case "${arg}" in
            "--incremental")
                CLEAN_BUILD=0
                ;;
            "--shallow-clone")
                SHALLOW_CLONE=1
                ;;
            "--use-mold")
                USE_MOLD=1
                ;;
            "--ci-run")
                CI=1
                ;;
            *)
                echo "Invalid argument passed: ${arg}"
                exit 1
                ;;
        esac
    done
}

export LLVM_COMMON_ARGS=(
    "-DCLANG_ENABLE_ARCMT=OFF"
    "-DCLANG_ENABLE_STATIC_ANALYZER=OFF"
    "-DCLANG_PLUGIN_SUPPORT=OFF"
    "-DCLANG_VENDOR='Neutron'"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DLLD_VENDOR='Neutron'"
    "-DLLVM_ENABLE_BACKTRACES=OFF"
    "-DLLVM_INCLUDE_BENCHMARKS=OFF"
    "-DLLVM_ENABLE_BINDINGS=OFF"
    "-DLLVM_ENABLE_OCAMLDOC=OFF"
    "-DLLVM_ENABLE_TERMINFO=OFF"
    "-DLLVM_ENABLE_WARNINGS=OFF"
    "-DLLVM_PARALLEL_COMPILE_JOBS=${NPROC}"
    "-DLLVM_PARALLEL_LINK_JOBS=${NPROC}"
    "-DLLVM_EXTERNAL_CLANG_TOOLS_EXTRA_SOURCE_DIR="
    "-DLLVM_INCLUDE_DOCS=OFF"
    "-DLLVM_INCLUDE_EXAMPLES=OFF"
    "-DLLVM_INCLUDE_TESTS=OFF"
    "-DLLVM_ENABLE_LIBEDIT=OFF"
    "-DLLVM_ENABLE_LIBPFM=OFF"
    "-DLLVM_ENABLE_LIBXML2=OFF"
    "-DLLVM_ENABLE_TELEMETRY=OFF"
    "-DLLVM_ENABLE_Z3_SOLVER=OFF"
)

build_kmakeflags() {
    local BIN_DIR="$1"
    export KMAKEFLAGS=(
        "LLVM=1"
        "LLVM_IAS=1"
        "CC=${BIN_DIR}/clang"
        "LD=${BIN_DIR}/ld.lld"
        "AR=${BIN_DIR}/llvm-ar"
        "NM=${BIN_DIR}/llvm-nm"
        "STRIP=${BIN_DIR}/llvm-strip"
        "OBJCOPY=${BIN_DIR}/llvm-objcopy"
        "OBJDUMP=${BIN_DIR}/llvm-objdump"
        "READELF=${BIN_DIR}/llvm-readelf"
        "HOSTCC=${BIN_DIR}/clang"
        "HOSTCXX=${BIN_DIR}/clang++"
        "HOSTAR=${BIN_DIR}/llvm-ar"
        "HOSTLD=${BIN_DIR}/ld.lld"
    )
}
