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

echo "=> Verifying dependencies"
check_if_exists "${LLVM_STAGE0_INSTALL_DIR}"
check_if_exists "${LLVM_INSTALL_DIR}"

# Remove unused products
echo "Removing unused products..."
rm -rf "${LLVM_INSTALL_DIR:?}"/include
rm -rf "${LLVM_INSTALL_DIR:?}"/lib/*.a "${LLVM_INSTALL_DIR:?}"/lib/*.la

# Strip remaining real files only (-type f excludes symlinks).
echo "Stripping remaining products (real files only, skipping symlinks)..."
for f in $(find "${LLVM_INSTALL_DIR}" -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
    f="${f::-1}"
    echo "Stripping: ${f}"
    "${LLVM_STAGE0_BIN_DIR}"/llvm-strip --strip-all-gnu "${f}"
done

# Set executable rpaths on real ELF binaries only (-type f skips symlinks)
echo "Setting library load paths for portability..."
for bin in $(find "${LLVM_INSTALL_DIR}" -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
    bin="${bin::-1}"
    echo "${bin}"
    patchelf --set-rpath '$ORIGIN/../lib' "${bin}"
done

echo "=> Post-build cleanup complete"
