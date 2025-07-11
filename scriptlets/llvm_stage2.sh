#!/usr/bin/env bash
# Copyright (C) 2025 Dakkshesh <beakthoven@gmail.com>. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

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
OPT_FLAGS="${LLVM_AVX_FLAGS} ${CLANG_OPT_CFLAGS[*]}"
OPT_FLAGS_LD="${CLANG_OPT_LDFLAGS[*]} ${FULL_LLVM_LDFLAGS[*]}"

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

mkdir -p "${LLVM_STAGE2_BUILD_DIR}" && cd "${LLVM_STAGE2_BUILD_DIR}"
cmake -G Ninja -Wno-dev --log-level=WARNING \
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
    -DLLVM_DISTRIBUTION_COMPONENTS="clang;clang-resource-headers;lld;libclang-headers;llvm-ar;llvm-as;llvm-nm;llvm-objcopy;llvm-objdump;llvm-readelf;llvm-strip" \
    -DTENSORFLOW_AOT_PATH="$(python3 -c "import tensorflow; import os; print(os.path.dirname(tensorflow.__file__))")" \
    -DLLVM_RAEVICT_MODEL_PATH="${MLGO_DIR}/arm64/regalloc/model" \
    -DLLVM_INLINER_MODEL_PATH="${MLGO_DIR}/arm64/inline/model" \
    -DCMAKE_C_COMPILER="${LLVM_STAGE1_BIN_DIR}"/clang \
    -DCMAKE_CXX_COMPILER="${LLVM_STAGE1_BIN_DIR}"/clang++ \
    -DCMAKE_AR="${LLVM_STAGE1_BIN_DIR}"/llvm-ar \
    -DCMAKE_NM="${LLVM_STAGE1_BIN_DIR}"/llvm-nm \
    -DCMAKE_STRIP="${LLVM_STAGE1_BIN_DIR}"/llvm-strip \
    -DLLVM_USE_LINKER="${LINKER}" \
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
    -DCMAKE_INSTALL_PREFIX="${LLVM_STAGE2_INSTALL_DIR}" \
    "${LLVM_PROJECT}"

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