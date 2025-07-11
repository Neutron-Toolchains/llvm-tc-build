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

source "$(pwd)"/scriptlets/_llvm.sh
set -eou pipefail

parse_llvm_args "$@"

# Clear some variables if unused
clear_if_unused "POLLY_OPT" "POLLY_PASS_FLAGS"
clear_if_unused "LLVM_OPT" "LLVM_PASS_FLAGS"
clear_if_unused "BOLT_OPT" "BOLT_ARGS"

# Send a notification if building on CI
if [[ ${CI} -eq 1 ]]; then
    tgsend "\
        <b>🔨 Neutron Clang Build Started</b>
		Build Date: <code>$(date +"%Y-%m-%d %H:%M")</code>"
fi

echo "Starting LLVM Build"
# Where all relevant build-related repositories are cloned.
if [[ -d ${LLVM_SRC_DIR} ]]; then
    echo "Existing llvm source found. Fetching new changes"
    cd "${LLVM_SRC_DIR}"
    if [[ ${SHALLOW_CLONE} -eq 1 ]]; then
        llvm_fetch "fetch" "--depth=1"
        git reset --hard FETCH_HEAD
        git clean -dfx
    else
        is_shallow=$(git rev-parse --is-shallow-repository 2>/dev/null)
        if [ "$is_shallow" = "true" ]; then
            llvm_fetch "fetch" "--depth=1"
            git reset --hard FETCH_HEAD
            git clean -dfx
        else
            llvm_fetch "pull"
        fi
    fi
    cd "${WORK_DIR}"
else
    echo "Cloning llvm project repo"
    cd "${SRC_DIR}"
    if [[ ${SHALLOW_CLONE} -eq 1 ]]; then
        llvm_fetch "clone" "--depth=1"
    else
        llvm_fetch "clone"
    fi
    cd "${WORK_DIR}"
fi

echo "Patching LLVM"
# Patches
if [[ -d "${WORK_DIR}/patches/llvm" ]]; then
    cd "${LLVM_SRC_DIR}"
    for pfile in "${WORK_DIR}/patches/llvm"/*; do
        echo "Applying: ${pfile}"
        patch -Np1 <"${pfile}" || echo "Skipping: ${pfile}"
    done
fi

mkdir -p "${MLGO_DIR}"

# x86 regalloc
download_and_extract "${MLGO_DIR}/x86/regalloc" \
    "https://github.com/google/ml-compiler-opt/releases/download/regalloc-evict-v1.0/regalloc-evict-e67430c-v1.0.tar.gz"

# x86 inline
download_and_extract "${MLGO_DIR}/x86/inline" \
    "https://github.com/google/ml-compiler-opt/releases/download/inlining-Oz-v1.1/inlining-Oz-99f0063-v1.1.tar.gz"

# arm64 regalloc
download_and_extract "${MLGO_DIR}/arm64/regalloc" \
    "https://github.com/dakkshesh07/mlgo-linux-kernel/releases/download/regalloc-evict-v6.6.8-arm64-1/regalloc-evict-linux-v6.6.8-arm64-1.tar.zst"

# arm64 inline
download_and_extract "${MLGO_DIR}/arm64/inline/model" \
    "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/mlgo-models/arm64/inlining-Oz-chromium.tar.gz"

if [[ ${CLEAN_BUILD} -eq 1 ]]; then
    rm -rf "${BUILD_DIR}"
fi
mkdir -p "${BUILD_DIR}"

cd ${WORK_DIR}
bash "${WORK_DIR}"/scriptlets/llvm_stage1.sh "$@"

bash "${WORK_DIR}"/scriptlets/llvm_deps.sh "$@"

bash "${WORK_DIR}"/scriptlets/llvm_stage2.sh "$@"

bash "${WORK_DIR}"/scriptlets/llvm_pgo.sh "$@"

bash "${WORK_DIR}"/scriptlets/llvm_stage3.sh "$@"