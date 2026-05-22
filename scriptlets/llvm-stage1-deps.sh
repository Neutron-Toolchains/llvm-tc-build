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

log "STAGE 1: Building dependencies"

info "Verifying dependencies"
check_if_exists "${LLVM_STAGE0_INSTALL_DIR}"

ZLIB_VERSION="2.3.3"
ZSTD_VERSION="v1.5.7"
MIMALLOC_VERSION="v3.3.2"

# Sync sources
cd "${SRC_DIR}"
git_get "https://github.com/microsoft/mimalloc.git" "${MIMALLOC_VERSION}" "${SRC_DIR}/mimalloc"
git_get "https://github.com/facebook/zstd.git" "${ZSTD_VERSION}" "${SRC_DIR}/zstd"
git_get "https://github.com/zlib-ng/zlib-ng.git" "${ZLIB_VERSION}" "${SRC_DIR}/zlib"

# Use stage 0 toolchain
MODDED_PATH="${LLVM_STAGE0_BIN_DIR}:${STOCK_PATH}"
export PATH="${MODDED_PATH}"
export LD_LIBRARY_PATH="${LLVM_STAGE0_INSTALL_DIR}/lib"

# Optimization
_OPT_CFLAGS=(
    "-march=x86-64-v3"
    "${GLOBAL_CFLAGS[@]}"
    "-mprefer-vector-width=256"
    "${POLLY_PASSES[@]}"
    "${VECTORIZATION_PASSES[@]}"
    "-fPIC"
)

info "Building mimalloc"
rm -rf "${BUILD_DIR}/mimalloc"
mkdir -p "${BUILD_DIR}/mimalloc" && cd "${BUILD_DIR}/mimalloc"
cmake -G Ninja -Wno-dev --log-level=WARNING \
    -DCMAKE_INSTALL_PREFIX="${LLVM_STAGE0_INSTALL_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DMI_INSTALL_TOPLEVEL=ON \
    -DMI_BUILD_SHARED=OFF \
    -DMI_BUILD_STATIC=ON \
    -DMI_SKIP_COLLECT_ON_EXIT=ON \
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
    -DCMAKE_C_FLAGS="${_OPT_CFLAGS[*]}" \
    -DCMAKE_CXX_FLAGS="${_OPT_CFLAGS[*]}" \
    "${SRC_DIR}/mimalloc"
ninja install -j"${NPROC}" || die "Could not build mimalloc!"
[[ -f ${MIMALLOC_STATIC} ]] || die "mimalloc not built: ${MIMALLOC_STATIC}"
ok "mimalloc built and installed to ${MIMALLOC_STATIC}"

info "Building zlib-ng"
rm -rf "${BUILD_DIR}/zlib"
mkdir -p "${BUILD_DIR}/zlib" && cd "${BUILD_DIR}/zlib"
cmake -G Ninja -Wno-dev --log-level=WARNING \
    -DCMAKE_INSTALL_PREFIX="${LLVM_STAGE0_INSTALL_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DZLIB_COMPAT=ON \
    -DWITH_GTEST=OFF \
    -DCMAKE_C_COMPILER="${LLVM_STAGE0_BIN_DIR}"/clang \
    -DCMAKE_CXX_COMPILER="${LLVM_STAGE0_BIN_DIR}"/clang++ \
    -DCMAKE_C_FLAGS="${_OPT_CFLAGS[*]}" \
    -DCMAKE_CXX_FLAGS="${_OPT_CFLAGS[*]}" \
    "${SRC_DIR}/zlib"
ninja install -j"${NPROC}" || die "STAGE 1: Could not build zlib-ng!"
ok "zlib-ng built and installed"

info "Building zstd"
rm -rf "${BUILD_DIR}/zstd"
mkdir -p "${BUILD_DIR}/zstd" && cd "${BUILD_DIR}/zstd"
cmake -G Ninja -Wno-dev --log-level=WARNING \
    -DCMAKE_INSTALL_PREFIX="${LLVM_STAGE0_INSTALL_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DZSTD_BUILD_TESTS=OFF \
    -DZSTD_BUILD_CONTRIB=OFF \
    -DZSTD_BUILD_SHARED=OFF \
    -DZSTD_BUILD_STATIC=ON \
    -DZSTD_MULTITHREAD_SUPPORT=ON \
    -DCMAKE_C_COMPILER="${LLVM_STAGE0_BIN_DIR}"/clang \
    -DCMAKE_CXX_COMPILER="${LLVM_STAGE0_BIN_DIR}"/clang++ \
    -DCMAKE_C_FLAGS="${_OPT_CFLAGS[*]}" \
    -DCMAKE_CXX_FLAGS="${_OPT_CFLAGS[*]}" \
    "${SRC_DIR}/zstd/build/cmake"
ninja install -j"${NPROC}" || die "Could not build zstd!"
ok "zstd built and installed"

info "Building generate_propeller_profiles"
PROPELLER_SRC="${SRC_DIR}/llvm-propeller"
git_get "https://github.com/google/llvm-propeller.git" "main" "${PROPELLER_SRC}"

#TODO: Remove once upstream is stable
cd "${PROPELLER_SRC}"
git checkout ca1d2e6826461ca506eaa045d1d74b9031c8bce0 || die "Could not checkout propeller source!"

if ! command -v generate_propeller_profiles >/dev/null; then
    rm -rf "${BUILD_DIR}/propeller-tool"
    mkdir -p "${BUILD_DIR}/propeller-tool" && cd "${BUILD_DIR}/propeller-tool"
    cmake -G Ninja -Wno-dev --log-level=WARNING \
        -DCMAKE_C_COMPILER="${LLVM_STAGE0_BIN_DIR}"/clang \
        -DCMAKE_CXX_COMPILER="${LLVM_STAGE0_BIN_DIR}"/clang++ \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_EXE_LINKER_FLAGS="-L${LLVM_STAGE0_INSTALL_DIR}/lib" \
        -DCMAKE_MODULE_LINKER_FLAGS="-L${LLVM_STAGE0_INSTALL_DIR}/lib" \
        -DCMAKE_SHARED_LINKER_FLAGS="-L${LLVM_STAGE0_INSTALL_DIR}/lib" \
        "${PROPELLER_SRC}"
    ninja generate_propeller_profiles -j"${NPROC}" || die "Could not build generate_propeller_profiles!"
    cp -f "${BUILD_DIR}/propeller-tool/propeller/generate_propeller_profiles" "${LLVM_STAGE0_BIN_DIR}/"
else
    info "host generate_propeller_profiles already found, linking to ${LLVM_STAGE0_BIN_DIR}"
    ln -sv "$(readlink -f "$(command -v generate_propeller_profiles)")" "${LLVM_STAGE0_BIN_DIR}/generate_propeller_profiles"
fi
ok "generate_propeller_profiles installed to ${LLVM_STAGE0_BIN_DIR}"

ok "Dependencies built and installed: ${LLVM_STAGE0_INSTALL_DIR}"
