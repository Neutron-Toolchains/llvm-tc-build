#!/bin/bash
# Script to push final built clang to my repo
set -e

CURRENT_DIR=$(pwd)
BINUTILS_DIR="$CURRENT_DIR/binutils-gdb"
LLVM_DIR="$CURRENT_DIR/llvm-project"
NEUTRON_DIR="$CURRENT_DIR/neutron-clang"
INSTALL_DIR="$CURRENT_DIR/install"

release_date="$(date "+%B %-d, %Y")" # "Month day, year" format

neutron_clone() {
	if ! git clone git@gitlab.com:dakkshesh07/neutron-clang.git; then
		exit 1
	fi
}

neutron_pull() {
	if ! git pull git@gitlab.com:dakkshesh07/neutron-clang.git; then
		exit 1
	fi
}

# Binutils Info
cd $BINUTILS_DIR
binutils_commit="$(git rev-parse HEAD)"
binutils_commit_url="https://sourceware.org/git/?p=binutils-gdb.git;a=commit;h=$binutils_commit"
binutils_ver="$(git rev-parse --abbrev-ref HEAD | sed "s/-branch//g" | sed "s/binutils-//g" | sed "s/_/./g")"

#LLVM Info
cd $LLVM_DIR
llvm_commit="$(git rev-parse HEAD)"
llvm_commit_url="https://github.com/llvm/llvm-project/commit/$llvm_commit"

# Clang Info
cd $CURRENT_DIR
clang_version="$(install/bin/clang --version | head -n1 | cut -d' ' -f4)"

# Builder Info
cd $CURRENT_DIR
builder_commit="$(git rev-parse HEAD)"

if [ -d "$NEUTRON_DIR"/ ]; then
	cd $NEUTRON_DIR/
	if ! git status; then
		cd $CURRENT_DIR
		neutron_clone
	else
		neutron_pull
		cd $CURRENT_DIR
	fi
else
	neutron_clone
fi

cd $NEUTRON_DIR
rm -rf *

cd $CURRENT_DIR
cp -r $INSTALL_DIR/* $NEUTRON_DIR

cd $NEUTRON_DIR
git checkout README.md # keep this as it's not part of the toolchain itself
git add -A

git commit -asm "Import Neutron Clang Build Of $release_date

Build completed on: $release_date
LLVM commit: $llvm_commit_url
Clang Version: $clang_version
Binutils version: $binutils_ver
Binutils commit: $binutils_commit_url
Builder commit: https://github.com/Neutron-Toolchains/clang-build/commit/$builder_commit"
git push -f
