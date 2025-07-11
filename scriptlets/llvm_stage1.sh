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

set -eoux pipefail

source "$(pwd)"/scriptlets/_llvm.sh

parse_llvm_args "$@"

echo "Verifying dependencies"
check_if_exists "${LLVM_SRC_DIR}"
check_if_exists "${MLGO_DIR}/x86"

echo "Starting Stage 1 Build"
mkdir -p "${LLVM_STAGE1_BUILD_DIR}" && cd "${LLVM_STAGE1_BUILD_DIR}"

LLVM_BIN_DIR=$(readlink -f "$(which clang)" | rev | cut -d'/' -f2- | rev)

LINKER="lld"
if [[ ${USE_MOLD} -eq 1 ]]; then
    LINKER="mold"
fi

OPT_FLAGS="-march=native -mtune=native ${CLANG_OPT_CFLAGS[*]} -fuse-ld=${LINKER}"
OPT_FLAGS_LD="${CLANG_OPT_LDFLAGS[*]}"

OPT_FLAGS_LD_EXE="${OPT_FLAGS_LD}"

STAGE1_PROJS="clang;lld"

if [[ ${BOLT_OPT} -eq 1 ]]; then
    STAGE1_PROJS+=";bolt"
fi

if [[ ${POLLY_OPT} -eq 1 ]]; then
    STAGE1_PROJS+=";polly"
fi

export TF_CPP_MIN_LOG_LEVEL=2
rm -rf "${LLVM_STAGE1_BUILD_DIR}"
mkdir -p "${LLVM_STAGE1_BUILD_DIR}" && cd "${LLVM_STAGE1_BUILD_DIR}"
cmake -G Ninja -Wno-dev \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DLLVM_ENABLE_PROJECTS="${STAGE1_PROJS}" \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt;libunwind;libcxx;libcxxabi" \
    -DCMAKE_INSTALL_PREFIX="${LLVM_STAGE1_INSTALL_DIR}" \
    -DLLVM_TARGETS_TO_BUILD="X86" \
    -DCLANG_DEFAULT_CXX_STDLIB="libc++" \
    -DCLANG_DEFAULT_LINKER="lld" \
    -DCLANG_DEFAULT_OBJCOPY="llvm-objcopy" \
    -DCLANG_DEFAULT_RTLIB="compiler-rt" \
    -DCLANG_DEFAULT_UNWINDLIB="libunwind" \
    -DCOMPILER_RT_BUILD_BUILTINS=ON \
    -DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
    -DCOMPILER_RT_BUILD_MEMPROF=OFF \
    -DCOMPILER_RT_BUILD_ORC=OFF \
    -DCOMPILER_RT_BUILD_PROFILE=ON \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
    -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_HAS_GCC_S_LIB=OFF \
    -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
    -DLIBCXX_CXX_ABI=libcxxabi \
    -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=OFF \
    -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
    -DLIBCXX_HAS_ATOMIC_LIB=OFF \
    -DLIBCXX_HAS_GCC_LIB=OFF \
    -DLIBCXX_HAS_GCC_S_LIB=OFF \
    -DLIBCXX_HAS_MUSL_LIBC=OFF \
    -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
    -DLIBCXX_INCLUDE_DOCS=OFF \
    -DLIBCXX_INCLUDE_TESTS=OFF \
    -DLIBCXX_USE_COMPILER_RT=ON \
    -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
    -DLIBCXXABI_INCLUDE_TESTS=OFF \
    -DLIBCXXABI_USE_COMPILER_RT=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBUNWIND_INCLUDE_DOCS=OFF \
    -DLIBUNWIND_INCLUDE_TESTS=OFF \
    -DLIBUNWIND_INSTALL_HEADERS=ON \
    -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DLINK_POLLY_INTO_TOOLS=ON \
    -DLLVM_CCACHE_BUILD=ON \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
    -DLLVM_ENABLE_PIC=OFF \
    -DTENSORFLOW_AOT_PATH="$(python3 -c "import tensorflow; import os; print(os.path.dirname(tensorflow.__file__))")" \
    -DLLVM_INLINER_MODEL_PATH="${MLGO_DIR}/x86/inline/model" \
    -DLLVM_RAEVICT_MODEL_PATH="${MLGO_DIR}/x86/regalloc/model" \
    -DLLVM_TOOL_LLVM_DRIVER_BUILD=ON \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DCMAKE_C_COMPILER="${LLVM_BIN_DIR}"/clang \
    -DCMAKE_CXX_COMPILER="${LLVM_BIN_DIR}"/clang++ \
    -DCMAKE_AR="${LLVM_BIN_DIR}"/llvm-ar \
    -DCMAKE_NM="${LLVM_BIN_DIR}"/llvm-nm \
    -DCMAKE_STRIP="${LLVM_BIN_DIR}"/llvm-strip \
    -DLLVM_USE_LINKER="${LINKER}" \
    -DCMAKE_OBJCOPY="${LLVM_BIN_DIR}"/llvm-objcopy \
    -DCMAKE_OBJDUMP="${LLVM_BIN_DIR}"/llvm-objdump \
    -DCMAKE_RANLIB="${LLVM_BIN_DIR}"/llvm-ranlib \
    -DCMAKE_READELF="${LLVM_BIN_DIR}"/llvm-readelf \
    -DCMAKE_ADDR2LINE="${LLVM_BIN_DIR}"/llvm-addr2line \
    -DCMAKE_C_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_ASM_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${OPT_FLAGS_LD_EXE}" \
    -DCMAKE_MODULE_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    "${LLVM_COMMON_ARGS[@]}" \
    "${LLVM_SRC_DIR}"/llvm

ninja -j"$(getconf _NPROCESSORS_ONLN)" || (
    echo "Could not build project!"
    exit 1
)

if [[ ${CI} -eq 1 ]]; then
    echo "Installing to ${LLVM_STAGE1_INSTALL_DIR}"
    ninja install -j"$(getconf _NPROCESSORS_ONLN)" || (
        echo "Could not install project!"
        exit 1
    )
fi

echo "Ending Stage 1 Build"
