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

log "STAGE 0: Bootstrap Compiler"

info "Verifying dependencies"
check_if_exists "${LLVM_SRC_DIR}"
#TODO: Re-enable once MLGO is added
#check_if_exists "${MLGO_DIR}/x86"

LLVM_BIN_DIR=$(readlink -f "$(which clang)" | rev | cut -d'/' -f2- | rev)

LINKER="lld"
if [[ ${USE_MOLD} -eq 1 ]]; then
    LINKER="mold"
fi

_OPT_CFLAGS=(
    "-march=native"
    "-mtune=native"
    "${GLOBAL_CFLAGS[@]}"
)
_OPT_LDFLAGS=(
    "-fuse-ld=${LINKER}"
    "${GLOBAL_LDFLAGS[@]}"
)

rm -rf "${LLVM_STAGE0_BUILD_DIR}"
mkdir -p "${LLVM_STAGE0_BUILD_DIR}" && cd "${LLVM_STAGE0_BUILD_DIR}"
#TODO: Enable once MLGO is added
#export TF_CPP_MIN_LOG_LEVEL=2
cmake -Wno-dev -G Ninja \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DLLVM_ENABLE_PROJECTS="clang;lld;polly" \
    -DLLVM_DISTRIBUTION_COMPONENTS="clang;lld;llvm-ar;llvm-nm;llvm-objcopy;llvm-objdump;llvm-readobj;llvm-symbolizer;llvm-profdata;llvm-as;runtimes" \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt;libunwind;libcxx;libcxxabi" \
    -DCMAKE_INSTALL_PREFIX="${LLVM_STAGE0_INSTALL_DIR}" \
    -DLLVM_TARGETS_TO_BUILD="X86" \
    -DCLANG_DEFAULT_LINKER="lld" \
    -DCLANG_DEFAULT_OBJCOPY="llvm-objcopy" \
    -DCLANG_DEFAULT_RTLIB="compiler-rt" \
    -DCLANG_DEFAULT_CXX_STDLIB="libc++" \
    -DCLANG_DEFAULT_UNWINDLIB="libunwind" \
    -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
    -DLIBUNWIND_ENABLE_SHARED=OFF \
    -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
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
    -DLIBUNWIND_INCLUDE_DOCS=OFF \
    -DLIBUNWIND_INCLUDE_TESTS=OFF \
    -DLIBUNWIND_INSTALL_HEADERS=ON \
    -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DLINK_POLLY_INTO_TOOLS=ON \
    -DLLVM_CCACHE_BUILD=ON \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
    -DLLVM_ENABLE_PIC=ON \
    -DLLVM_ENABLE_LTO=OFF \
    -DLLVM_STATIC_LINK_CXX_STDLIB=ON \
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
    -DCMAKE_C_FLAGS="${_OPT_CFLAGS[*]}" \
    -DCMAKE_CXX_FLAGS="${_OPT_CFLAGS[*]}" \
    -DCMAKE_ASM_FLAGS="${_OPT_CFLAGS[*]}" \
    -DCMAKE_EXE_LINKER_FLAGS="${_OPT_LDFLAGS[*]}" \
    -DCMAKE_MODULE_LINKER_FLAGS="${_OPT_LDFLAGS[*]}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${_OPT_LDFLAGS[*]}" \
    "${LLVM_COMMON_ARGS[@]}" \
    "${LLVM_SRC_DIR}"/llvm

ninja -j"${NPROC}" distribution || die "Could not build project!"

if [[ ${CI} -eq 1 ]]; then
    info "Installing to ${LLVM_STAGE0_INSTALL_DIR}"
    ninja install-distribution -j"${NPROC}" || die "Could not install project!"
fi

ok "Stage 0: Build complete"
