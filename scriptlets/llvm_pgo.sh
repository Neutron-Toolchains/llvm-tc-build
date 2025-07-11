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

check_if_exists "${LLVM_STAGE1_BIN_DIR}"
check_if_exists "${LLVM_STAGE2_BIN_DIR}"

LINUX_VER=$(curl -sL "https://www.kernel.org" | grep -A 1 "latest_link" | tail -n +2 | sed 's|.*">||' | sed 's|</a>||')

cd "${SRC_DIR}"
get_linux_tarball "${LINUX_VER}"
KERNEL_SRC_DIR="${SRC_DIR}/linux-${LINUX_VER}"

mkdir -p "$PROFILE_DIR" && rm -rf "${PROFILE_DIR}/"*

MAX_SIZE=$((2 * 1024 * 1024 * 1024)) # 2 GiB
SLEEP_INTERVAL=60                    # seconds
LOCK_FILE="/tmp/build_in_progress.lock"

# Function: background merge daemon
profile_merge_daemon() {
    echo "[*] Profile merge daemon started"
    while [[ -f $LOCK_FILE ]]; do
        total_size=$(du -sb "${PROFILE_DIR}" | awk '{print $1}')

        if ((total_size > MAX_SIZE)); then
            echo "[+] Merging profiles... size: ${total_size}"

            mapfile -t profraw_files < <(find "${PROFILE_DIR}" -maxdepth 1 -type f -name '*.profraw' | sort)

            if ((${#profraw_files[@]} > 0)); then
                temp_profdata="$(mktemp --suffix=.profdata)"
                if [[ -f $PROFDATA_OUT ]]; then
                    "${LLVM_STAGE1_BIN_DIR}"/llvm-profdata merge -o "${temp_profdata}" "${PROFDATA_OUT}" "${profraw_files[@]}"
                else
                    "${LLVM_STAGE1_BIN_DIR}"/llvm-profdata merge -o "${temp_profdata}" "${profraw_files[@]}"
                fi
                mv "${temp_profdata}" "${PROFDATA_OUT}"
                rm -f "${profraw_files[@]}"
                echo "[+] Merge and cleanup done."
            fi
        else
            echo "[-] Profile dir under threshold. Sleeping..."
        fi

        sleep "${SLEEP_INTERVAL}"
    done

    echo "[*] Build finished. Final merge..."

    # Final merge of remaining profraw files
    mapfile -t remaining_files < <(find "${PROFILE_DIR}" -maxdepth 1 -type f -name '*.profraw')
    if ((${#remaining_files[@]} > 0)); then
        temp_profdata="$(mktemp --suffix=.profdata)"
        if [[ -f $PROFDATA_OUT ]]; then
            "${LLVM_STAGE1_BIN_DIR}"/llvm-profdata merge -o "${temp_profdata}" "${PROFDATA_OUT}" "${remaining_files[@]}"
        else
            "${LLVM_STAGE1_BIN_DIR}"/llvm-profdata merge -o "${temp_profdata}" "${remaining_files[@]}"
        fi
        mv "${temp_profdata}" "${PROFDATA_OUT}"
        rm -f "${remaining_files[@]}"
        echo "[+] Final merge complete."
    fi

    echo "[*] Merge daemon exiting."
}

echo "Stage 2: PGO Train Start"

export PATH="${LLVM_STAGE2_BIN_DIR}:${STOCK_PATH}"
export LD_LIBRARY_PATH="${LLVM_STAGE2_BIN_DIR}/../lib"

cd "${KERNEL_SRC_DIR}"

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
    "CC=${LLVM_STAGE2_BIN_DIR}/clang"
    "LD=${LLVM_STAGE2_BIN_DIR}/ld.lld"
    "AR=${LLVM_STAGE2_BIN_DIR}/llvm-ar"
    "NM=${LLVM_STAGE2_BIN_DIR}/llvm-nm"
    "STRIP=${LLVM_STAGE2_BIN_DIR}/llvm-strip"
    "OBJCOPY=${LLVM_STAGE2_BIN_DIR}/llvm-objcopy"
    "OBJDUMP=${LLVM_STAGE2_BIN_DIR}/llvm-objdump"
    "READELF=${LLVM_STAGE2_BIN_DIR}/llvm-readelf"
    "HOSTCC=${LLVM_STAGE2_BIN_DIR}/clang"
    "HOSTCXX=${LLVM_STAGE2_BIN_DIR}/clang++"
    "HOSTAR=${LLVM_STAGE2_BIN_DIR}/llvm-ar"
    "HOSTLD=${LLVM_STAGE2_BIN_DIR}/ld.lld")

# Create the build-in-progress lock
touch "$LOCK_FILE"

# Start the profile merge daemon in the background
profile_merge_daemon &
DAEMON_PID=$!

export LLVM_PROFILE_FILE="${PROFILE_DIR}/default_%m_%p.profraw"

echo "Training x86"
make distclean defconfig all -sj"$(getconf _NPROCESSORS_ONLN)" "${KMAKEFLAGS[@]}" || exit ${?}

echo "Training arm64"
make distclean defconfig all -sj"$(getconf _NPROCESSORS_ONLN)" ARCH=arm64 KCFLAGS="-mllvm -regalloc-enable-advisor=release" KLDFLAGS="-mllvm -regalloc-enable-advisor=release" \
    "${KMAKEFLAGS[@]}" || exit ${?}

echo "Training arm"
make distclean defconfig all -sj"$(getconf _NPROCESSORS_ONLN)" ARCH=arm KCFLAGS="-mllvm -regalloc-enable-advisor=release" KLDFLAGS="-mllvm -regalloc-enable-advisor=release" \
    "${KMAKEFLAGS[@]}" || exit ${?}

# Mark build as done
rm -f "$FLAG_LOCK"

# Wait for the daemon to exit
wait $DAEMON_PID

unset LLD_IN_TEST

du -sh "${PROFDATA_OUT}"
echo "Stage 2: PGO Training End"
