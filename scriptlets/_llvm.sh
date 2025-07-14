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

source "$(pwd)"/scriptlets/utils.sh

################
# LLVM Builder #
################
export CLEAN_BUILD=1
export POLLY_OPT=0
export BOLT_OPT=0
export LLVM_OPT=0
export USE_MOLD=0
export LLVM_SRC_DIR="${SRC_DIR}/llvm-project"

export LLVM_STAGE1_BUILD_DIR="${BUILD_DIR}/stage1"
export LLVM_STAGE1_INSTALL_DIR="${LLVM_STAGE1_BUILD_DIR}"
export LLVM_STAGE1_BIN_DIR="${LLVM_STAGE1_INSTALL_DIR}/bin"

export LLVM_STAGE2_BUILD_DIR="${BUILD_DIR}/stage2"
export LLVM_STAGE2_INSTALL_DIR="${LLVM_STAGE2_BUILD_DIR}"
export LLVM_STAGE2_BIN_DIR="${LLVM_STAGE2_INSTALL_DIR}/bin"

export LLVM_STAGE3_BUILD_DIR="${BUILD_DIR}/stage3"
export LLVM_INSTALL_DIR="${WORK_DIR}/install"

export PROFILE_DIR="${LLVM_STAGE2_BUILD_DIR}/profiles"
export PROFDATA_OUT="${PROFILE_DIR}/llvm.profdata"

export MLGO_DIR="${SRC_DIR}/mlgo-models"

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
    rm -rf linux-"$1"
    tar xf linux-"$1".tar.xz
}

export LLVM_ARCH="${ARCH_GENERIC}"

parse_llvm_args() {
    for arg in "$@"; do
        case "${arg}" in
            "--all-opts")
                POLLY_OPT=1
                BOLT_OPT=1
                LLVM_OPT=1
                AVX_OPT=1
                ;;
            "--incremental")
                CLEAN_BUILD=0
                ;;
            "--shallow-clone")
                SHALLOW_CLONE=1
                ;;
            "--polly-opt")
                POLLY_OPT=1
                ;;
            "--bolt-opt")
                BOLT_OPT=1
                ;;
            "--llvm-opt")
                LLVM_OPT=1
                ;;
            "--use-mold")
                USE_MOLD=1
                ;;
            "--install-dir"*)
                FINAL_INSTALL_DIR="${arg#*--install-dir}"
                FINAL_INSTALL_DIR=${FINAL_INSTALL_DIR:1}
                ;;
            "--ci-run")
                CI=1
                LLVM_STAGE1_INSTALL_DIR="${LLVM_STAGE1_BUILD_DIR}/install"
                LLVM_STAGE2_INSTALL_DIR="${LLVM_STAGE2_BUILD_DIR}/install"
                ;;
            "--avx2")
                AVX_OPT=1
                export LLVM_ARCH="${ARCH_AVX2}"
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
    "-DLLVM_ENABLE_BINDINGS=OFF"
    "-DLLVM_ENABLE_LTO=Thin"
    "-DLLVM_ENABLE_OCAMLDOC=OFF"
    "-DLLVM_ENABLE_TERMINFO=OFF"
    "-DLLVM_ENABLE_WARNINGS=OFF"
    "-DLLVM_PARALLEL_COMPILE_JOBS=$(getconf _NPROCESSORS_ONLN)"
    "-DLLVM_PARALLEL_LINK_JOBS=$(getconf _NPROCESSORS_ONLN)"
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
