#!/usr/bin/env bash
# shellcheck disable=SC2086
# Script to push final built clang to my repo
set -e

# Specify some variables.
CURRENT_DIR=$(pwd)
BINUTILS_DIR="$CURRENT_DIR/binutils-gdb"
LLVM_DIR="$CURRENT_DIR/llvm-project"
NEUTRON_DIR="$CURRENT_DIR/clang-build-catalogue"
INSTALL_DIR="$CURRENT_DIR/install"

rel_tag="$(date "+%d%m%Y")"      # "{date}{month}{year}" format
rel_date="$(date "+%-d %B, %Y")" # "Day Month, Year" format
rel_file="$CURRENT_DIR/neutron-clang-$rel_tag.tar.zst"

neutron_clone() {

	if ! git clone https://github.com/Neutron-Toolchains/clang-build-catalogue.git; then
		exit 1
	fi
}

neutron_pull() {

	if ! git pull https://github.com/Neutron-Toolchains/clang-build-catalogue.git; then
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
h_glibc="$(ldd --version | head -n1 | grep -oE '[^ ]+$')"

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

cd $INSTALL_DIR
tar --zstd -cf "${rel_file}" .
rel_shasum=$(sha256sum "${rel_file}" | awk '{print $1}')
rel_size=$(du -sh "${rel_file}" | awk '{print $1}')

cd $NEUTRON_DIR
rm -rf latest.txt
touch latest.txt
echo -e "[tag]\n $rel_tag" >>latest.txt

touch "$rel_tag-info.txt"
echo -e "[date]\n $rel_date\n" >>"$rel_tag-info.txt"
echo -e "[clang-ver]\n $clang_version\n" >>"$rel_tag-info.txt"
echo -e "[llvm-commit]\n $llvm_commit_url\n" >>"$rel_tag-info.txt"
echo -e "[binutils-ver]\n $binutils_ver\n" >>"$rel_tag-info.txt"
echo -e "[binutils-commit]\n $binutils_commit_url\n" >>"$rel_tag-info.txt"
echo -e "[host-glibc]\n $h_glibc\n" >>"$rel_tag-info.txt"
echo -e "[size]\n $rel_size\n" >>"$rel_tag-info.txt"
echo -e "[shasum]\n $rel_shasum" >>"$rel_tag-info.txt"

git add -A
git commit -asm "catalogue: Add Neutron Clang build $rel_tag

Build completed on: $rel_date
LLVM commit: $llvm_commit_url
Clang Version: $clang_version
Binutils version: $binutils_ver
Binutils at commit: $binutils_commit_url
Builder at commit: https://github.com/Neutron-Toolchains/clang-build/commit/$builder_commit
Release: https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/tag/$rel_tag"
git gc

if gh release view "${rel_tag}"; then
	echo "Uploading build archive to '${rel_tag}'..."
	gh release upload --clobber "${rel_tag}" "${rel_file}" && {
		echo "Version ${rel_tag} updated!"
	}
else
	echo "Creating release with tag '${rel_tag}'..."
	gh release create "${rel_tag}" "${rel_file}" -t "$rel_date" && {
		echo "Version ${rel_tag} released!"
	}
fi

git push -f
