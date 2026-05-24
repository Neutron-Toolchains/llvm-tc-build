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

source "$(pwd)"/scriptlets/_llvm.sh
set -eou pipefail

parse_llvm_args "$@"

log "Starting LLVM build process"

log "Fetching and preparing sources"

# Where all relevant build-related repositories are cloned.
if [[ -d ${LLVM_SRC_DIR} ]]; then
    info "Existing llvm source found. Fetching new changes"
    cd "${LLVM_SRC_DIR}"
    if [[ ${SHALLOW_CLONE} -eq 1 ]]; then
        llvm_fetch "fetch" "--depth=1"
        git reset --hard FETCH_HEAD
        git clean -dfx >/dev/null
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
    info "Cloning llvm project repo"
    mkdir -p "${SRC_DIR}" && cd "${SRC_DIR}"
    if [[ ${SHALLOW_CLONE} -eq 1 ]]; then
        llvm_fetch "clone" "--depth=1"
    else
        llvm_fetch "clone"
    fi
    cd "${WORK_DIR}"
fi

info "Patching LLVM"
# Patches
if [[ -d "${WORK_DIR}/patches/llvm" ]]; then
    cd "${LLVM_SRC_DIR}"
    for pfile in "${WORK_DIR}/patches/llvm"/*; do
        echo "Applying: ${pfile}"
        patch -Np1 <"${pfile}" || echo "Skipping: ${pfile}"
    done
fi

mkdir -p "${MLGO_DIR}"

# TODO: Re-enable once MLGO is added
# x86 regalloc
#download_and_extract "${MLGO_DIR}/x86/regalloc" \
#    "https://github.com/google/ml-compiler-opt/releases/download/regalloc-evict-v1.1/model.zip"
#
# x86 inline
#download_and_extract "${MLGO_DIR}/x86/inline" \
#    "https://github.com/google/ml-compiler-opt/releases/download/inlining-Oz-v1.2/saved_model.zip"
#
# arm64 regalloc
#download_and_extract "${MLGO_DIR}/arm64/regalloc" \
#    "https://github.com/dakkshesh07/mlgo-linux-kernel/releases/download/regalloc-evict-v6.6.8-arm64-1/regalloc-evict-linux-v6.6.8-arm64-1.tar.zst"
#
# arm64 inline
#download_and_extract "${MLGO_DIR}/arm64/inline/model" \
#    "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/mlgo-models/arm64/inlining-Oz-chromium.tar.gz"

if [[ ${CLEAN_BUILD} -eq 1 ]]; then
    rm -rf "${BUILD_DIR}"
fi
mkdir -p "${BUILD_DIR}"

cd "${WORK_DIR}"

# Stage 0: Bootstrap compiler
bash "${WORK_DIR}"/scriptlets/llvm-stage0-bootstrap.sh "$@"

# Stage 1: Dependencies (mimalloc, zlib-ng, zstd, generate_propeller_profiles)
bash "${WORK_DIR}"/scriptlets/llvm-stage1-deps.sh "$@"

if [[ ${CSSPGO} -eq 0 ]]; then
    # Stage 2A: IR PGO instrumented build
    bash "${WORK_DIR}"/scriptlets/llvm-stage2A-irpgo.sh "$@"

    # Stage 2B: PGO training
    bash "${WORK_DIR}"/scriptlets/llvm-stage2B-irpgo-train.sh "$@"

    # Stage 3A: CSPGO instrumented build
    bash "${WORK_DIR}"/scriptlets/llvm-stage3A-cspgo.sh "$@"

    # Stage 3B: CSPGO training
    bash "${WORK_DIR}"/scriptlets/llvm-stage3B-cspgo-train.sh "$@"
else
    # Stage 2A: CSSPGO instrumented build
    bash "${WORK_DIR}"/scriptlets/llvm-stage2A-cssspgo.sh "$@"

    # Stage 2B: CSSPGO training
    bash "${WORK_DIR}"/scriptlets/llvm-stage2B-cssspgo-train.sh "$@"
fi

# Stage 4A: Propeller labels build
bash "${WORK_DIR}"/scriptlets/llvm-stage4A-propeller-labels.sh "$@"

# Stage 4B: Propeller profile collection (sampling)
bash "${WORK_DIR}"/scriptlets/llvm-stage4B-propeller-profile.sh "$@"

# Stage 4C: Propeller optimized final build
bash "${WORK_DIR}"/scriptlets/llvm-stage4C-propeller-final.sh "$@"

ok "LLVM build installation complete: ${LLVM_INSTALL_DIR}"
log "LLVM build process complete"
