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

log "STAGE 4B: Propeller Profile Collection"

info "Verifying dependencies"
check_if_exists "${LLVM_STAGE0_INSTALL_DIR}"
check_if_exists "${LLVM_STAGE4_LABELS_BUILD_DIR}"

LABELS_BIN_DIR="${LLVM_STAGE4_LABELS_BUILD_DIR}/bin"
LABELS_CLANG_BINARY=$(readlink -f "${LABELS_BIN_DIR}/clang")
LABELS_LLD_BINARY=$(readlink -f "${LABELS_BIN_DIR}/ld.lld")
LABELS_AR_BINARY=$(readlink -f "${LABELS_BIN_DIR}/llvm-ar")

[[ -f ${LABELS_CLANG_BINARY} ]] || die "Labels binary not found: ${LABELS_CLANG_BINARY}"
[[ -f ${LABELS_LLD_BINARY} ]] || die "Labels ld.lld binary not found: ${LABELS_LLD_BINARY}"
[[ -f ${LABELS_AR_BINARY} ]] || die "Labels llvm-ar binary not found: ${LABELS_AR_BINARY}"
[[ -x "${LLVM_STAGE0_BIN_DIR}/generate_propeller_profiles" ]] || die "generate_propeller_profiles not found in ${LLVM_STAGE0_BIN_DIR}"

# Verify LBR availability
if ! perf record -e cycles:u -j any,u -o /dev/null -- true &>/dev/null 2>&1; then
    die "LBR not available."
fi

# Fetch kernel source
cd "${SRC_DIR}" || exit 1
LINUX_VER=$(curl -sL "https://www.kernel.org" | grep -A 1 "latest_link" | tail -n +2 | sed 's|.*">||' | sed 's|</a>||')
get_linux_tarball "${LINUX_VER}"
KERNEL_SRC_DIR="${SRC_DIR}/linux-${LINUX_VER}"

rm -rf "${PROPELLER_RAW_DIR}" && mkdir -p "${PROPELLER_RAW_DIR}"

export PATH="${LABELS_BIN_DIR}:${STOCK_PATH}"
export LD_LIBRARY_PATH="${LLVM_STAGE4_LABELS_BUILD_DIR}/lib"

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

build_kmakeflags "${LABELS_BIN_DIR}"

info "Profiling X86_64 kernel build"
perf record \
    -e cycles:u \
    -j any,u \
    -c 500009 \
    -o "${PROPELLER_RAW_DIR}/perf.x86_64" \
    -- make distclean defconfig all -sj"${NPROC}" "${KMAKEFLAGS[@]}" || exit ${?}

info "Profiling ARM64 kernel build"
perf record \
    -e cycles:u \
    -j any,u \
    -c 500009 \
    -o "${PROPELLER_RAW_DIR}/perf.arm64" \
    -- make distclean defconfig all -sj"${NPROC}" ARCH=arm64 "${KMAKEFLAGS[@]}" || exit ${?}

info "perf data: $(du -shc "${PROPELLER_RAW_DIR}"/perf.x86_64 "${PROPELLER_RAW_DIR}"/perf.arm64 | tail -1 | cut -f1)"
COMBINED_PERF="${PROPELLER_RAW_DIR}/perf.x86_64,${PROPELLER_RAW_DIR}/perf.arm64"

info "STAGE 4B: Generating Propeller profiles"

# clang
info "Generating Propeller profiles for clang"
"${LLVM_STAGE0_BIN_DIR}"/generate_propeller_profiles \
    --binary="${LABELS_CLANG_BINARY}" \
    --profile="${COMBINED_PERF}" \
    --cc_profile="${PROPELLER_RAW_DIR}/clang_cc.txt" \
    --ld_profile="${PROPELLER_RAW_DIR}/clang_ld.txt"

# lld
info "Generating Propeller profiles for lld"
"${LLVM_STAGE0_BIN_DIR}"/generate_propeller_profiles \
    --binary="${LABELS_LLD_BINARY}" \
    --profile="${COMBINED_PERF}" \
    --cc_profile="${PROPELLER_RAW_DIR}/lld_cc.txt" \
    --ld_profile="${PROPELLER_RAW_DIR}/lld_ld.txt"

# llvm-ar
info "Generating Propeller profiles for llvm-ar"
"${LLVM_STAGE0_BIN_DIR}"/generate_propeller_profiles \
    --binary="${LABELS_AR_BINARY}" \
    --profile="${COMBINED_PERF}" \
    --cc_profile="${PROPELLER_RAW_DIR}/ar_cc.txt" \
    --ld_profile="${PROPELLER_RAW_DIR}/ar_ld.txt"

# Merge profiles
info "Merging cc_profiles"
cat \
    "${PROPELLER_RAW_DIR}/clang_cc.txt" \
    "${PROPELLER_RAW_DIR}/lld_cc.txt" \
    "${PROPELLER_RAW_DIR}/ar_cc.txt" \
    >"${PROPELLER_CC_PROFILE}"

info "Merging ld_profiles"
cat \
    "${PROPELLER_RAW_DIR}/clang_ld.txt" \
    "${PROPELLER_RAW_DIR}/lld_ld.txt" \
    "${PROPELLER_RAW_DIR}/ar_ld.txt" \
    >"${PROPELLER_LD_PROFILE}"

[[ -f ${PROPELLER_CC_PROFILE} ]] || die "cc_profile not generated: ${PROPELLER_CC_PROFILE}"
[[ -f ${PROPELLER_LD_PROFILE} ]] || die "ld_profile not generated: ${PROPELLER_LD_PROFILE}"

info "cc_profile: $(du -sh "${PROPELLER_CC_PROFILE}" | cut -f1)"
info "ld_profile: $(du -sh "${PROPELLER_LD_PROFILE}" | cut -f1)"

ok "STAGE 4B: Propeller profile collection complete"
