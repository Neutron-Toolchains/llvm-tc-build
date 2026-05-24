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

log "STAGE 2B: CSSPGO Profile Collection"

info "Verifying dependencies"
check_if_exists "${LLVM_STAGE0_INSTALL_DIR}"
check_if_exists "${LLVM_STAGE2_INSTALL_DIR}"

_BIN_DIR="${LLVM_STAGE2_INSTALL_DIR}/bin"
_CLANG_BINARY=$(readlink -f "${_BIN_DIR}/clang")
_LLD_BINARY=$(readlink -f "${_BIN_DIR}/ld.lld")
_AR_BINARY=$(readlink -f "${_BIN_DIR}/llvm-ar")

[[ -f ${_CLANG_BINARY} ]] || die "clang binary not found: ${_CLANG_BINARY}"
[[ -f ${_LLD_BINARY} ]] || die "ld.lld binary not found: ${_LLD_BINARY}"
[[ -f ${_AR_BINARY} ]] || die "llvm-ar binary not found: ${_AR_BINARY}"
[[ -x "${LLVM_STAGE0_BIN_DIR}/llvm-profgen" ]] || die "llvm-profgen not found in ${LLVM_STAGE0_BIN_DIR}"

PERF_EVENT=""
for event in "ex_ret_brn_tkn:u" "br_inst_retired.near_taken:uppp" "br_inst_retired.near_taken:u"; do
    if perf record -e "${event}" -j any,u -o /dev/null -- true >/dev/null 2>&1; then
        PERF_EVENT="${event}"
        break
    fi
done
[[ -z ${PERF_EVENT} ]] && die "No valid LBR event found. Check kernel >= 6.1 and perf_event_paranoid <= 1"

info "Using perf event: ${PERF_EVENT}"

# Fetch kernel source
cd "${SRC_DIR}" || exit 1
LINUX_VER=$(curl -sL "https://www.kernel.org" | grep -A 1 "latest_link" | tail -n +2 | sed 's|.*">||' | sed 's|</a>||')
get_linux_tarball "${LINUX_VER}"
KERNEL_SRC_DIR="${SRC_DIR}/linux-${LINUX_VER}"

rm -rf "${CSSSPGO_RAW_DIR}" && mkdir -p "${CSSSPGO_RAW_DIR}"

export PATH="${_BIN_DIR}:${STOCK_PATH}"
export LD_LIBRARY_PATH="${LLVM_STAGE2_INSTALL_DIR}/lib"

cd "${KERNEL_SRC_DIR}" || exit 1

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

sed -i 's|-Os|-O3|g' Makefile
sed -i 's|-O2|-O3|g' Makefile

build_kmakeflags "${_BIN_DIR}"

info "Profiling x86_64 kernel build"
perf record \
    -g \
    --call-graph fp \
    -e "${PERF_EVENT}" \
    -j any,u \
    -c 500009 \
    -o "${CSSSPGO_RAW_DIR}/perf.x86_64" \
    -- make distclean defconfig all -sj"${NPROC}" "${KMAKEFLAGS[@]}"

info "Profiling arm64 kernel build"
perf record \
    -g \
    --call-graph fp \
    -e "${PERF_EVENT}" \
    -j any,u \
    -c 500009 \
    -o "${CSSSPGO_RAW_DIR}/perf.arm64" \
    -- make distclean defconfig all -sj"${NPROC}" ARCH=arm64 "${KMAKEFLAGS[@]}"

run_profgen() {
    "${LLVM_STAGE0_BIN_DIR}/llvm-profgen" \
        --perfdata="${1}" \
        --binary="${2}" \
        --output="${3}" \
        --format=extbinary \
        --infer-missing-frames \
        --update-total-samples \
        --load-function-from-symbol
}

info "Generating profiles"
run_profgen "${CSSSPGO_RAW_DIR}/perf.x86_64" "${_CLANG_BINARY}" "${CSSSPGO_RAW_DIR}/clang_x86_64.prof"
run_profgen "${CSSSPGO_RAW_DIR}/perf.x86_64" "${_LLD_BINARY}" "${CSSSPGO_RAW_DIR}/lld_x86_64.prof"
run_profgen "${CSSSPGO_RAW_DIR}/perf.x86_64" "${_AR_BINARY}" "${CSSSPGO_RAW_DIR}/ar_x86_64.prof"
run_profgen "${CSSSPGO_RAW_DIR}/perf.arm64" "${_CLANG_BINARY}" "${CSSSPGO_RAW_DIR}/clang_arm64.prof"
run_profgen "${CSSSPGO_RAW_DIR}/perf.arm64" "${_LLD_BINARY}" "${CSSSPGO_RAW_DIR}/lld_arm64.prof"
run_profgen "${CSSSPGO_RAW_DIR}/perf.arm64" "${_AR_BINARY}" "${CSSSPGO_RAW_DIR}/ar_arm64.prof"

"${LLVM_STAGE0_BIN_DIR}/llvm-profdata" merge \
    --sample \
    --extbinary \
    --output="${CSSSPGO_PROFDATA}" \
    "${CSSSPGO_RAW_DIR}"/*.prof

info "CSSPGO profile: $(du -sh "${CSSSPGO_PROFDATA}" | cut -f1)"

ok "STAGE 2B: CSSPGO profile collection complete"
