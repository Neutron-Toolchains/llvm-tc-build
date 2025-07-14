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

set -eou pipefail

source "$(pwd)"/scriptlets/_llvm.sh

parse_llvm_args "$@"

echo "=> Verifying dependencies"
check_if_exists "${LLVM_STAGE1_BIN_DIR}"
check_if_exists "${LLVM_INSTALL_DIR}"
check_if_exists "${LLVM_STAGE3_INSTALL_DIR}"
LLVM_STAGE1_BIN_DIR="${LLVM_STAGE1_INSTALL_DIR}/bin"
LLVM_STAGE3_BIN_DIR="${LLVM_STAGE3_INSTALL_DIR}/bin"

LINUX_VER=$(curl -sL "https://www.kernel.org" | grep -A 1 "latest_link" | tail -n +2 | sed 's|.*">||' | sed 's|</a>||')

cd "${SRC_DIR}" || exit 1
get_linux_tarball "${LINUX_VER}"
KERNEL_SRC_DIR="${SRC_DIR}/linux-${LINUX_VER}"

#MODDED_PATH="${LLVM_STAGE1_BIN_DIR}:${STOCK_PATH}"
#export PATH="${MODDED_PATH}"
#export LD_LIBRARY_PATH="${LLVM_STAGE1_INSTALL_DIR}/lib"

BOLT_PROFILES="${LLVM_STAGE3_BUILD_DIR}/clang-bolt-profile"
mkdir -p "${BOLT_PROFILES}" && rm -rf "${BOLT_PROFILES:?}/"*

echo "=> Starting BOLT optimization (mode: instrumentation)"
CLANG_SUFFIX=$(basename "$(readlink -f "${LLVM_STAGE3_BIN_DIR}"/clang)")
"${LLVM_STAGE1_BIN_DIR}"/llvm-bolt \
    --instrument \
    --instrumentation-file-append-pid \
    --instrumentation-file="${BOLT_PROFILES}/${CLANG_SUFFIX}.fdata" \
    "${LLVM_STAGE3_BIN_DIR}/${CLANG_SUFFIX}" \
    -o "${LLVM_STAGE3_BIN_DIR}/${CLANG_SUFFIX}.inst"

mv "${LLVM_STAGE3_BIN_DIR}/${CLANG_SUFFIX}" "${LLVM_STAGE3_BIN_DIR}/${CLANG_SUFFIX}.org"
mv "${LLVM_STAGE3_BIN_DIR}/${CLANG_SUFFIX}.inst" "${LLVM_STAGE3_BIN_DIR}/${CLANG_SUFFIX}"

"${LLVM_STAGE1_BIN_DIR}"/llvm-bolt \
    --instrument \
    --instrumentation-file-append-pid \
    --instrumentation-file="${BOLT_PROFILES}/lld.fdata" \
    "${LLVM_STAGE3_BIN_DIR}/lld" \
    -o "${LLVM_STAGE3_BIN_DIR}/lld.inst"

mv "${LLVM_STAGE3_BIN_DIR}/lld" "${LLVM_STAGE3_BIN_DIR}/lld.org"
mv "${LLVM_STAGE3_BIN_DIR}/lld.inst" "${LLVM_STAGE3_BIN_DIR}/lld"

MAX_SIZE=$((1 * 1024 * 1024 * 1024)) # 1 GiB
SLEEP_INTERVAL=30                    # seconds
LOCK_FILE="/tmp/build_in_progress.lock"
FDATA_OUT="${BOLT_PROFILES}/llvm.fdata"

# Function: background merge daemon
profile_merge_daemon() {
    echo "[*] Profile merge daemon started"
    while [[ -f $LOCK_FILE ]]; do
        total_size=$(du -sb "${BOLT_PROFILES}" | awk '{print $1}')

        if ((total_size > MAX_SIZE)); then
            echo "[+] Merging profiles... size: ${total_size}"

            mapfile -t fdata_files < <(find "${BOLT_PROFILES}" -maxdepth 1 -type f -name '*.fdata' | sort)

            if ((${#fdata_files[@]} > 0)); then
                temp_fdata="$(mktemp --suffix=.fdata)"
                if [[ -f $FDATA_OUT ]]; then
                    "${LLVM_STAGE1_BIN_DIR}"/merge-fdata "${FDATA_OUT}" "${fdata_files[@]}" 2>merge-fdata.log 1>"${temp_fdata}"
                else
                    "${LLVM_STAGE1_BIN_DIR}"/merge-fdata "${fdata_files[@]}" 2>merge-fdata.log 1>"${temp_fdata}"
                fi
                mv "${temp_fdata}" "${FDATA_OUT}"
                rm -f "${fdata_files[@]}"
                echo "[+] Merge and cleanup done."
            fi
        else
            echo "[-] Profile dir under threshold. Sleeping..."
        fi

        sleep "${SLEEP_INTERVAL}"
    done

    echo "[*] Build finished. Final merge..."

    # Final merge of remaining fdata files
    mapfile -t remaining_files < <(find "${BOLT_PROFILES}" -maxdepth 1 -type f -name '*.fdata')
    if ((${#remaining_files[@]} > 0)); then
        temp_fdata="$(mktemp --suffix=.fdata)"
        if [[ -f $FDATA_OUT ]]; then
            "${LLVM_STAGE1_BIN_DIR}"/merge-fdata "${FDATA_OUT}" "${remaining_files[@]}" 2>merge-fdata.log 1>"${temp_fdata}"
        else
            "${LLVM_STAGE1_BIN_DIR}"/merge-fdata "${remaining_files[@]}" 2>merge-fdata.log 1>"${temp_fdata}"
        fi
        mv "${temp_fdata}" "${FDATA_OUT}"
        rm -f "${remaining_files[@]}"
        echo "[+] Final merge complete."
    fi

    echo "[*] Merge daemon exiting."
}

echo "=> Starting BOLT training"

export PATH="${LLVM_STAGE3_BIN_DIR}:${STOCK_PATH}"
export LD_LIBRARY_PATH="${LLVM_STAGE3_BIN_DIR}/../lib"

cd "${KERNEL_SRC_DIR}" || exit 1

# Patches
if [[ -d "${WORK_DIR}/patches/linux/common" ]]; then
    for pfile in "${WORK_DIR}/patches/linux/common"/*; do
        echo "Applying: ${pfile}"
        patch -Np1 <"${pfile}" || echo "Skipping: ${pfile}"
    done
fi

if [[ -d "${WORK_DIR}/patches/linux/${LINUX_VER}" ]]; then
    for pfile in "${WORK_DIR}/patches/linux/${LINUX_VER}"/*; do
        echo "Applying: ${pfile}"
        patch -Np1 <"${pfile}" || echo "Skipping: ${pfile}"
    done
fi

# Force profiling using O3
sed -i 's|-Os|-O3|g' Makefile
sed -i 's|-O2|-O3|g' Makefile

# As a speedup, lld invokes _Exit, which stops it from writing the PGO profiles.
export LLD_IN_TEST=1

# Train PGO
KMAKEFLAGS=("LLVM=1"
    "LLVM_IAS=1"
    "CC=${LLVM_STAGE3_BIN_DIR}/clang"
    "LD=${LLVM_STAGE3_BIN_DIR}/ld.lld"
    "AR=${LLVM_STAGE3_BIN_DIR}/llvm-ar"
    "NM=${LLVM_STAGE3_BIN_DIR}/llvm-nm"
    "STRIP=${LLVM_STAGE3_BIN_DIR}/llvm-strip"
    "OBJCOPY=${LLVM_STAGE3_BIN_DIR}/llvm-objcopy"
    "OBJDUMP=${LLVM_STAGE3_BIN_DIR}/llvm-objdump"
    "READELF=${LLVM_STAGE3_BIN_DIR}/llvm-readelf"
    "HOSTCC=${LLVM_STAGE3_BIN_DIR}/clang"
    "HOSTCXX=${LLVM_STAGE3_BIN_DIR}/clang++"
    "HOSTAR=${LLVM_STAGE3_BIN_DIR}/llvm-ar"
    "HOSTLD=${LLVM_STAGE3_BIN_DIR}/ld.lld")

# Create the build-in-progress lock
touch "$LOCK_FILE"

# Start the profile merge daemon in the background
profile_merge_daemon &
DAEMON_PID=$!

echo "Training x86"
make distclean defconfig all -sj"$(getconf _NPROCESSORS_ONLN)" "${KMAKEFLAGS[@]}" || exit ${?}

echo "Training arm64"
make distclean defconfig all -sj"$(getconf _NPROCESSORS_ONLN)" ARCH=arm64 KCFLAGS="-mllvm -regalloc-enable-advisor=release" KLDFLAGS="-mllvm -regalloc-enable-advisor=release" \
    "${KMAKEFLAGS[@]}" || exit ${?}

# Mark build as done
rm -f "$LOCK_FILE"

# Wait for the daemon to exit
wait $DAEMON_PID

unset LLD_IN_TEST

du -sh "${FDATA_OUT}"
echo "=> BOLT training complete"

echo "=> Applying BOLT optimization"
mv "${LLVM_INSTALL_DIR}/bin/llvm" "${LLVM_INSTALL_DIR}/bin/llvm.org"
"${LLVM_STAGE1_BIN_DIR}"/llvm-bolt \
    "${LLVM_INSTALL_DIR}/bin/llvm.org" \
    --data "${FDATA_OUT}" \
    -o "${LLVM_INSTALL_DIR}/bin/llvm" \
    "${BOLT_ARGS[@]}"

echo "=> BOLT optimization complete"
