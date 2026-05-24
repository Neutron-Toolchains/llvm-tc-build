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

log "STAGE 2A: CSSPGO Instrumented Build"

info "Verifying dependencies"
check_if_exists "${LLVM_SRC_DIR}"
check_if_exists "${LLVM_STAGE0_INSTALL_DIR}"
#TODO: Re-enable once MLGO is added
#check_if_exists "${MLGO_DIR}/arm64"
MODDED_PATH="${LLVM_STAGE0_BIN_DIR}:${STOCK_PATH}"
export PATH="${MODDED_PATH}"
export LD_LIBRARY_PATH="${LLVM_STAGE0_INSTALL_DIR}/lib"

_OPT_CFLAGS=(
    "-march=x86-64-v3"
    "${GLOBAL_CFLAGS[@]}"
    "-flto=thin"
    "-fwhole-program-vtables"
    "-fsplit-lto-unit"
    "-mprefer-vector-width=256"
    "${STRUCTURAL_CFLAGS[@]}"
    "${POLLY_PASSES[@]}"
    "${VECTORIZATION_PASSES[@]}"
    "-Wno-ignored-optimization-argument"
    "-Wno-unused-command-line-argument"
)

_OPT_LDFLAGS=(
    "-L${LLVM_STAGE0_INSTALL_DIR}/lib"
    "${STATIC_LINK_FLAGS[@]}"
    "${FULL_LDFLAGS[@]}"
    "-fuse-ld=${LLVM_STAGE0_BIN_DIR}/ld.lld"
    "-Wl,--build-id=sha1"
)

rm -rf "${LLVM_STAGE2_BUILD_DIR}"
mkdir -p "${LLVM_STAGE2_BUILD_DIR}" && cd "${LLVM_STAGE2_BUILD_DIR}"
#TODO: Enable once MLGO is added
#export TF_CPP_MIN_LOG_LEVEL=2
cmake -G Ninja -Wno-dev \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_INSTALL_PREFIX="${LLVM_STAGE2_INSTALL_DIR}" \
    -DLLVM_TARGETS_TO_BUILD='AArch64;ARM;X86' \
    -DLLVM_ENABLE_PROJECTS='clang;lld;polly' \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt" \
    -DLLVM_DISTRIBUTION_COMPONENTS="clang;clang-resource-headers;lld;libclang-headers;llvm-ar;llvm-as;llvm-nm;llvm-objcopy;llvm-objdump;llvm-readelf;llvm-strip;runtimes;builtins" \
    -DCLANG_DEFAULT_LINKER="lld" \
    -DCLANG_DEFAULT_OBJCOPY="llvm-objcopy" \
    -DCOMPILER_RT_BUILD_BUILTINS=ON \
    -DCOMPILER_RT_BUILD_CRT=ON \
    -DCOMPILER_RT_BUILD_PROFILE=ON \
    -DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
    -DCOMPILER_RT_BUILD_MEMPROF=OFF \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
    -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_ORC=OFF \
    -DENABLE_LINKER_BUILD_ID=ON \
    -DLLVM_BUILD_INSTRUMENTED=CSSPGO \
    -DLLVM_ENABLE_LTO=Thin \
    -DLLVM_ENABLE_LLD=ON \
    -DLLVM_ENABLE_PIC=ON \
    -DLLVM_STATIC_LINK_CXX_STDLIB=ON \
    -DLINK_POLLY_INTO_TOOLS=ON \
    -DLLVM_ENABLE_ZLIB=ON \
    -DLLVM_ENABLE_ZSTD=ON \
    -DLLVM_USE_STATIC_ZSTD=ON \
    -DZLIB_INCLUDE_DIR="${LLVM_STAGE0_INSTALL_DIR}/include" \
    -DZLIB_LIBRARY="${LLVM_STAGE0_INSTALL_DIR}/lib/libz.a" \
    -Dzstd_INCLUDE_DIR="${LLVM_STAGE0_INSTALL_DIR}/include" \
    -Dzstd_LIBRARY="${LLVM_STAGE0_INSTALL_DIR}/lib/libzstd.a" \
    -DCMAKE_C_COMPILER="${LLVM_STAGE0_BIN_DIR}"/clang \
    -DCMAKE_CXX_COMPILER="${LLVM_STAGE0_BIN_DIR}"/clang++ \
    -DCMAKE_AR="${LLVM_STAGE0_BIN_DIR}"/llvm-ar \
    -DCMAKE_NM="${LLVM_STAGE0_BIN_DIR}"/llvm-nm \
    -DCMAKE_STRIP="${LLVM_STAGE0_BIN_DIR}"/llvm-strip \
    -DCMAKE_OBJCOPY="${LLVM_STAGE0_BIN_DIR}"/llvm-objcopy \
    -DCMAKE_OBJDUMP="${LLVM_STAGE0_BIN_DIR}"/llvm-objdump \
    -DCMAKE_RANLIB="${LLVM_STAGE0_BIN_DIR}"/llvm-ranlib \
    -DCMAKE_READELF="${LLVM_STAGE0_BIN_DIR}"/llvm-readelf \
    -DCMAKE_ADDR2LINE="${LLVM_STAGE0_BIN_DIR}"/llvm-addr2line \
    -DCLANG_TABLEGEN="${LLVM_STAGE0_BIN_DIR}"/clang-tblgen \
    -DLLVM_TABLEGEN="${LLVM_STAGE0_BIN_DIR}"/llvm-tblgen \
    -DCMAKE_C_FLAGS="${_OPT_CFLAGS[*]}" \
    -DCMAKE_CXX_FLAGS="${_OPT_CFLAGS[*]}" \
    -DCMAKE_ASM_FLAGS="${_OPT_CFLAGS[*]}" \
    -DCMAKE_EXE_LINKER_FLAGS="${_OPT_LDFLAGS[*]}" \
    -DCMAKE_MODULE_LINKER_FLAGS="${_OPT_LDFLAGS[*]}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${_OPT_LDFLAGS[*]}" \
    "${LLVM_COMMON_ARGS[@]}" \
    "${LLVM_SRC_DIR}"/llvm

ninja distribution -j"${NPROC}" || die "Could not build project!"

ok "STAGE 2A: build complete"
