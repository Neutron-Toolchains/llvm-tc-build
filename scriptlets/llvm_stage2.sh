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
check_if_exists "${LLVM_SRC_DIR}"
check_if_exists "${LLVM_STAGE1_INSTALL_DIR}"
check_if_exists "${MLGO_DIR}/arm64"

echo "Starting Stage 2 Build"
MODDED_PATH="${LLVM_STAGE1_BIN_DIR}:${STOCK_PATH}"
export PATH="${MODDED_PATH}"
export LD_LIBRARY_PATH="${LLVM_STAGE1_INSTALL_DIR}/lib"

# Default optimization flags
OPT_FLAGS="${LLVM_ARCH} ${CLANG_OPT_CFLAGS[*]} --ld-path=${LLVM_STAGE1_BIN_DIR}/ld.lld"
OPT_FLAGS_LD="${CLANG_OPT_LDFLAGS[*]} -L${LLVM_STAGE1_INSTALL_DIR}/lib -lmimalloc ${FULL_LLVM_LDFLAGS[*]}"

# Polly flags
if [[ ${POLLY_OPT} -eq 1 ]]; then
    OPT_FLAGS+=" ${POLLY_PASS_FLAGS[*]}"
fi

# LLVM passes
if [[ ${LLVM_OPT} -eq 1 ]]; then
    OPT_FLAGS+=" ${LLVM_PASS_FLAGS[*]}"
fi

# MLGO flags
OPT_FLAGS+=" -mllvm -enable-ml-inliner=release -mllvm -regalloc-enable-advisor=release"
OPT_FLAGS_LD+=" -Wl,-mllvm,-enable-ml-inliner=release -Wl,-mllvm,-regalloc-enable-advisor=release"

# Todo: add mimalloc linking
OPT_FLAGS_LD_EXE="${OPT_FLAGS_LD}"

# PGO flags
OPT_FLAGS+=" -fprofile-generate -fprofile-update=atomic -mllvm -vp-counters-per-site=8"

rm -rf "${LLVM_STAGE2_BUILD_DIR}"
mkdir -p "${LLVM_STAGE2_BUILD_DIR}" && cd "${LLVM_STAGE2_BUILD_DIR}"
cmake -G Ninja -Wno-dev \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_INSTALL_PREFIX="${LLVM_STAGE2_INSTALL_DIR}" \
    -DLLVM_TARGETS_TO_BUILD='AArch64;ARM;X86' \
    -DLLVM_ENABLE_PROJECTS='clang;lld' \
    -DCLANG_DEFAULT_LINKER="lld" \
    -DCLANG_DEFAULT_OBJCOPY="llvm-objcopy" \
    -DLIBCLANG_BUILD_STATIC=ON \
    -DLIBCXX_HAS_ATOMIC_LIB=OFF \
    -DLLVM_BUILD_INSTRUMENTED=IR \
    -DLLVM_BUILD_RUNTIME=OFF \
    -DLLVM_ENABLE_LIBCXX=ON \
    -DLLVM_ENABLE_LIBCXX=ON \
    -DLLVM_ENABLE_UNWIND_TABLES=OFF \
    -DLLVM_INCLUDE_UTILS=ON \
    -DLLVM_LINK_LLVM_DYLIB=OFF \
    -DLLVM_STATIC_LINK_CXX_STDLIB=ON \
    -DLLVM_TOOL_LLVM_DRIVER_BUILD=ON \
    -DLLVM_VP_COUNTERS_PER_SITE=8 \
    -DLLVM_ENABLE_LLD=ON \
    -DLLVM_ENABLE_PIC=OFF \
    -DLLVM_DISTRIBUTION_COMPONENTS="clang;clang-resource-headers;lld;libclang-headers;llvm-ar;llvm-as;llvm-nm;llvm-objcopy;llvm-objdump;llvm-readelf;llvm-strip" \
    -DTENSORFLOW_AOT_PATH="$(python3 -c "import tensorflow; import os; print(os.path.dirname(tensorflow.__file__))")" \
    -DLLVM_RAEVICT_MODEL_PATH="${MLGO_DIR}/arm64/regalloc/model" \
    -DLLVM_INLINER_MODEL_PATH="${MLGO_DIR}/arm64/inline/model" \
    -DLLVM_ENABLE_ZLIB=ON \
    -DLLVM_ENABLE_ZSTD=ON \
    -DLLVM_USE_STATIC_ZSTD=ON \
    -DZLIB_INCLUDE_DIR="${LLVM_STAGE1_INSTALL_DIR}/include" \
    -DZLIB_LIBRARY="${LLVM_STAGE1_INSTALL_DIR}/lib/libz.a" \
    -Dzstd_INCLUDE_DIR="${LLVM_STAGE1_INSTALL_DIR}/include" \
    -Dzstd_LIBRARY="${LLVM_STAGE1_INSTALL_DIR}/lib/libzstd.a" \
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
    -DCLANG_TABLEGEN="${LLVM_STAGE1_BIN_DIR}"/clang-tblgen \
    -DLLVM_TABLEGEN="${LLVM_STAGE1_BIN_DIR}"/llvm-tblgen \
    -DCMAKE_C_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_ASM_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${OPT_FLAGS_LD_EXE}" \
    -DCMAKE_MODULE_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    "${LLVM_COMMON_ARGS[@]}" \
    "${LLVM_SRC_DIR}"/llvm

ninja distribution -j"$(getconf _NPROCESSORS_ONLN)" || (
    echo "Could not build project!"
    exit 1
)

if [[ ${CI} -eq 1 ]]; then
    echo "Installing to ${LLVM_STAGE2_INSTALL_DIR}"
    ninja install-distribution -j"$(getconf _NPROCESSORS_ONLN)" || (
        echo "Could not install project!"
        exit 1
    )
fi
