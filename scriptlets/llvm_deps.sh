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

echo "Verifying dependencies"
check_if_exists "${LLVM_STAGE1_INSTALL_DIR}"

ZLIB_VERSION="$(curl -s https://api.github.com/repos/zlib-ng/zlib-ng/releases/latest | jq -r .tag_name)"
ZSTD_VERSION="$(curl -s https://api.github.com/repos/facebook/zstd/releases/latest | jq -r .tag_name)"
# mimalloc doesn't make github releases hence the following mess
MIMALLOC_VERSION="$(curl -s https://api.github.com/repos/microsoft/mimalloc/git/refs/tags | jq -r '.[].ref' | sed 's|refs/tags/||' | grep -E '^v?[0-9]+\.[0-9]+(\.[0-9]+)?$' | sort -V | tail -n1)" # need to find better way

# Sync sources
cd "${SRC_DIR}"
git_get "https://github.com/microsoft/mimalloc.git" "${MIMALLOC_VERSION}" "${SRC_DIR}/mimalloc"
git_get "https://github.com/facebook/zstd.git" "${ZSTD_VERSION}" "${SRC_DIR}/zstd"
git_get "https://github.com/zlib-ng/zlib-ng.git" "${ZLIB_VERSION}" "${SRC_DIR}/zlib"

# Compiler configuration
MODDED_PATH="${LLVM_STAGE1_BIN_DIR}:${STOCK_PATH}"
export PATH="${MODDED_PATH}"
export LD_LIBRARY_PATH="${LLVM_STAGE1_INSTALL_DIR}/lib"

OPT_FLAGS="${LLVM_ARCH} ${CLANG_OPT_CFLAGS[*]} -fsplit-machine-functions --ld-path=${LLVM_STAGE1_BIN_DIR}/ld.lld"
OPT_FLAGS_LD="${CLANG_OPT_LDFLAGS[*]} -L${LLVM_STAGE1_INSTALL_DIR}/lib ${FULL_LLVM_LDFLAGS[*]}"

if [[ ${POLLY_OPT} -eq 1 ]]; then
    OPT_FLAGS+=" ${POLLY_PASS_FLAGS[*]}"
fi

if [[ ${LLVM_OPT} -eq 1 ]]; then
    OPT_FLAGS+=" ${LLVM_PASS_FLAGS[*]}"
fi

# MLGO flags
OPT_FLAGS+=" -mllvm -enable-ml-inliner=release -mllvm -regalloc-enable-advisor=release"
OPT_FLAGS_LD+=" -Wl,-mllvm,-enable-ml-inliner=release -Wl,-mllvm,-regalloc-enable-advisor=release"

# build mimalloc
rm -rf "${BUILD_DIR}/mimalloc"
mkdir -p "${BUILD_DIR}/mimalloc" && cd "${BUILD_DIR}/mimalloc"
cmake -G Ninja -Wno-dev --log-level=WARNING \
    -DCMAKE_INSTALL_PREFIX="${LLVM_STAGE1_INSTALL_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DMI_INSTALL_TOPLEVEL=ON \
    -DMI_BUILD_SHARED=OFF \
    -DMI_BUILD_STATIC=ON \
    -DCMAKE_C_COMPILER="${LLVM_STAGE1_BIN_DIR}"/clang \
    -DCMAKE_CXX_COMPILER="${LLVM_STAGE1_BIN_DIR}"/clang++ \
    -DCMAKE_AR="${LLVM_STAGE1_BIN_DIR}"/llvm-ar \
    -DCMAKE_NM="${LLVM_STAGE1_BIN_DIR}"/llvm-nm \
    -DCMAKE_STRIP="${LLVM_STAGE1_BIN_DIR}"/llvm-strip \
    -DCMAKE_OBJCOPY="${LLVM_STAGE1_BIN_DIR}"/llvm-objcopy \
    -DCMAKE_OBJDUMP="${LLVM_STAGE1_BIN_DIR}"/llvm-objdump \
    -DCMAKE_RANLIB="${LLVM_STAGE1_BIN_DIR}"/llvm-ranlib \
    -DCMAKE_READELF="${LLVM_STAGE1_BIN_DIR}"/llvm-readelf \
    -DCMAKE_ADDR2LINE="${LLVM_STAGE1_BIN_DIR}"/llvm-addr2line \
    -DCMAKE_C_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_ASM_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    -DCMAKE_MODULE_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    "${SRC_DIR}/mimalloc"

ninja install -j"$(getconf _NPROCESSORS_ONLN)" || (
    echo "Could not build mimalloc!"
    exit 1
)

OPT_FLAGS_LD+=" -lmimalloc"

# build zlib-ng
rm -rf "${BUILD_DIR}/zlib"
mkdir -p "${BUILD_DIR}/zlib" && cd "${BUILD_DIR}/zlib"
cmake -G Ninja -Wno-dev --log-level=WARNING \
    -DCMAKE_INSTALL_PREFIX="${LLVM_STAGE1_INSTALL_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DZLIB_COMPAT=ON \
    -DWITH_GTEST=OFF \
    "${SRC_DIR}/zlib"

ninja install -j"$(getconf _NPROCESSORS_ONLN)" || (
    echo "Could not build zlib-ng!"
    exit 1
)

# build zstd
rm -rf "${BUILD_DIR}/zstd"
mkdir -p "${BUILD_DIR}/zstd" && cd "${BUILD_DIR}/zstd"
cmake -G Ninja -Wno-dev --log-level=WARNING \
    -DCMAKE_INSTALL_PREFIX="${LLVM_STAGE1_INSTALL_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DZSTD_BUILD_TESTS=OFF \
    -DZSTD_BUILD_CONTRIB=OFF \
    -DZSTD_BUILD_SHARED=OFF \
    -DZSTD_BUILD_STATIC=ON \
    -DZSTD_MULTITHREAD_SUPPORT=ON \
    "${SRC_DIR}/zstd/build/cmake"

ninja install -j"$(getconf _NPROCESSORS_ONLN)" || (
    echo "Could not build zstd!"
    exit 1
)
