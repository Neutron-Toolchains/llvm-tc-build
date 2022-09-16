#!/usr/bin/env bash
# shellcheck disable=SC2086
# A Script to build GNU binutils
set -e

# Specify some variables.
BUILDDIR=$(pwd)
BINUTILS_DIR="$BUILDDIR/binutils-gdb"
INSTALL_DIR="$BUILDDIR/install"
BINUTILS_BUILD="$BUILDDIR/binutils-build"

# The main build function that builds GNU binutils.
build() {

	if [ -d $BINUTILS_BUILD ]; then
		rm -rf $BINUTILS_BUILD
	fi
	mkdir -p $BINUTILS_BUILD
	cd $BINUTILS_BUILD
	case $1 in
	"X86")
		"$BINUTILS_DIR"/configure \
			CC="gcc" \
			CXX="g++" \
			CFLAGS="-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections" \
			CXXFLAGS="-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections" \
			LDFLAGS="-Wl,-O3,--sort-common,--as-needed,-z,now,--strip-debug" \
			--target=x86_64-pc-linux-gnu \
			--prefix=$INSTALL_DIR \
			--disable-compressed-debug-sections \
			--disable-gdb \
			--disable-gdbserver \
			--disable-docs \
			--disable-libdecnumber \
			--disable-readline \
			--disable-sim \
			--disable-werror \
			--enable-lto \
			--enable-relro \
			--with-pic \
			--enable-deterministic-archives \
			--enable-new-dtags \
			--enable-plugins \
			--enable-gold \
			--enable-threads \
			--enable-targets=x86_64-pep \
			--enable-ld=default \
			--quiet \
			--with-pkgversion="Neutron Binutils"
		;;
	"ARM64")
		"$BINUTILS_DIR"/configure \
			CC="gcc" \
			CXX="g++" \
			CFLAGS="-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections" \
			CXXFLAGS="-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections" \
			LDFLAGS="-Wl,-O3,--sort-common,--as-needed,-z,now,--strip-debug" \
			--target=aarch64-linux-gnu \
			--prefix=$INSTALL_DIR \
			--disable-compressed-debug-sections \
			--disable-gdb \
			--disable-gdbserver \
			--disable-docs \
			--disable-libdecnumber \
			--disable-readline \
			--disable-sim \
			--disable-multilib \
			--disable-werror \
			--disable-nls \
			--with-gnu-as \
			--with-gnu-ld \
			--enable-lto \
			--enable-deterministic-archives \
			--enable-new-dtags \
			--enable-plugins \
			--enable-gold \
			--enable-threads \
			--enable-ld=default \
			--quiet \
			--with-pkgversion="Neutron Binutils"
		;;
	"ARM")
		"$BINUTILS_DIR"/configure \
			CC="gcc" \
			CXX="g++" \
			CFLAGS="-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections" \
			CXXFLAGS="-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections" \
			LDFLAGS="-Wl,-O3,--sort-common,--as-needed,-z,now,--strip-debug" \
			--target=arm-linux-gnueabi \
			--prefix=$INSTALL_DIR \
			--disable-compressed-debug-sections \
			--disable-gdb \
			--disable-gdbserver \
			--disable-docs \
			--disable-libdecnumber \
			--disable-readline \
			--disable-sim \
			--disable-multilib \
			--disable-werror \
			--disable-nls \
			--with-gnu-as \
			--with-gnu-ld \
			--enable-lto \
			--enable-deterministic-archives \
			--enable-new-dtags \
			--enable-plugins \
			--enable-gold \
			--enable-threads \
			--enable-ld=default \
			--quiet \
			--with-pkgversion="Neutron Binutils"
		;;
	*)
		echo "You have specified a wrong architecture type or one that we do not support! Do specify the correct one or feel free to make a PR with the relevant changes to add support to the architecture that you are trying to build this toolchain for."
		exit 1
		;;
	esac

	make -j$(($(nproc --all) + 2)) >/dev/null
	make install -j$(($(nproc --all) + 2)) >/dev/null
}

# This is where the build starts.
echo "Starting Binutils Build"
echo "Starting Binutils Build for x86-64"
build "X86" || (
	echo "x86-64 Build failed!"
	exit 1
)
echo "Starting Binutils Build for arm"
build "ARM" || (
	echo "arm Build failed!"
	exit 1
)
echo "Starting Binutils Build for arm64"
build "ARM64" || (
	echo "arm64 Build failed!"
	exit 1
)
