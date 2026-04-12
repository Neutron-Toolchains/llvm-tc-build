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

source "$(pwd)"/scriptlets/_llvm.sh

parse_llvm_args "$@"

log "STAGE 2B: PGO Training (Linux Kernel)"

info "Verifying dependencies"
check_if_exists "${LLVM_STAGE0_INSTALL_DIR}"
check_if_exists "${LLVM_STAGE2_BUILD_DIR}"

LLVM_STAGE2_BIN_DIR="${LLVM_STAGE2_BUILD_DIR}/bin"

# Fetch kernel source
LINUX_VER=$(curl -sL "https://www.kernel.org" | grep -A 1 "latest_link" | tail -n +2 | sed 's|.*">||' | sed 's|</a>||')

cd "${SRC_DIR}" || exit 1
get_linux_tarball "${LINUX_VER}"
KERNEL_SRC_DIR="${SRC_DIR}/linux-${LINUX_VER}"

mkdir -p "$PGO_RAW_DIR" && rm -rf "${PGO_RAW_DIR:?}/"*

export PATH="${LLVM_STAGE2_BIN_DIR}:${STOCK_PATH}"
export LD_LIBRARY_PATH="${LLVM_STAGE2_BIN_DIR}/../lib"

cd "${KERNEL_SRC_DIR}" || exit 1

# Patches
if [[ -d "${WORK_DIR}/patches/linux/common" ]]; then
    for pfile in "${WORK_DIR}/patches/linux/common"/*; do
        info "Applying: ${pfile}"
        patch -Np1 <"${pfile}" || warn "Skipping: ${pfile}"
    done
fi

if [[ -d "${WORK_DIR}/patches/linux/${LINUX_VER}" ]]; then
    for pfile in "${WORK_DIR}/patches/linux/${LINUX_VER}"/*; do
        info "Applying: ${pfile}"
        patch -Np1 <"${pfile}" || warn "Skipping: ${pfile}"
    done
fi

# Force profiling using O3
sed -i 's|-Os|-O3|g' Makefile
sed -i 's|-O2|-O3|g' Makefile

# As a speedup, lld invokes _Exit, which stops it from writing the PGO profiles.
export LLD_IN_TEST=1

build_kmakeflags "${LLVM_STAGE2_BIN_DIR}"

info "Building X86_64 kernel"
make distclean defconfig all -sj"${NPROC}" "${KMAKEFLAGS[@]}" || die "Training failed for x86_64"

info "Building ARM64 kernel"
make distclean defconfig all -sj"${NPROC}" ARCH=arm64 \
    "${KMAKEFLAGS[@]}" || die "Training failed for arm64"

unset LLD_IN_TEST

info "Merging PGO profiles"
info "Raw files: $(find "${PGO_RAW_DIR}" -name '*.profraw' 2>/dev/null | wc -l)"

"${LLVM_STAGE0_BIN_DIR}"/llvm-profdata merge \
    --output="${PGO_PROFDATA}" \
    --num-threads="${NPROC}" \
    "${PGO_RAW_DIR}"/*.profraw

info "PGO Profile Size: ${PGO_PROFDATA}: $(du -sh "${PGO_PROFDATA}" | cut -f1)"
ok "Stage 2B: PGO Profiling End"
