#!/bin/bash
# A custom Multi-Stage LLVM Toolchain builder.
# PGO optimized clang for building Linux Kernels.
#!/bin/bash
set -e

BUILDDIR=$(pwd)
GLIBC_VER="2.35"
GLIBC_DIR="$BUILDDIR/glibc"
INSTALL_DIR="$BUILDDIR/install"
GLIBC_BUILD="$BUILDDIR/glibc-build"
PERSONAL=0

msg() {
	if [[ $PERSONAL -eq 1 ]]; then
		telegram-send "$1"
	else
		echo "$1"
	fi
}

glibc_clone() {
	if ! git clone https://sourceware.org/git/glibc.git -b release/$GLIBC_VER/master; then
		echo "glibc git clone: Failed" >&2
		exit 1
	fi
}

glibc_pull() {
	if ! git pull https://sourceware.org/git/glibc.git release/$GLIBC_VER/master; then
		echo "glibc git Pull: Failed" >&2
		exit 1
	fi
}

if [ -d "$GLIBC_DIR"/ ]; then
	cd $GLIBC_DIR/
	if ! git status; then
		echo "GNU libc dir found but not a git repo, recloning"
		cd $BUILDDIR
		glibc_clone
	else
		echo "Existing glibc repo found, skipping clone"
		echo "Fetching new changes"
		glibc_pull
		cd $BUILDDIR
	fi
else
	echo "cloning GNU libc repo"
	glibc_clone
fi

mkdir -p $GLIBC_BUILD
cd $GLIBC_BUILD

echo "slibdir=/usr/lib" >>configparms
echo "rtlddir=/usr/lib" >>configparms
echo "sbindir=/usr/bin" >>configparms
echo "rootsbindir=/usr/bin" >>configparms

"$GLIBC_DIR/configure" \
	--prefix=$INSTALL_DIR \
	CFLAGS="-march=x86-64 -mtune=generic -O3 -pipe -fno-plt -fexceptions -Wformat -Werror=format-security -fstack-clash-protection -fcf-protection" \
	CXXFLAGS="-march=x86-64 -mtune=generic -O3 -pipe -fno-plt -fexceptions -Wp,-D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -fstack-clash-protection -fcf-protection -Wp,-D_GLIBCXX_ASSERTIONS" \
	LDFLAGS="-Wl,-O3,--sort-common,--as-needed,-z,relro,-z,now" \
	--libdir=/usr/lib \
	--libexecdir=/usr/lib \
	--with-headers=/usr/include \
	--enable-bind-now \
	--enable-cet \
	--enable-kernel=5.10 \
	--enable-multi-arch \
	--enable-stack-protector=strong \
	--disable-crypt \
	--disable-profile \
	--disable-werror

echo "build-programs=no" >>configparms
make -O -j$(($(nproc --all) + 2))

# re-enable fortify for programs
sed -i "/build-programs=/s#no#yes#" configparms
echo "CFLAGS += -D_FORTIFY_SOURCE=2" >>configparms
make -O -j$(($(nproc --all) + 2))

# build info pages manually for reproducibility
make info -j$(($(nproc --all) + 2))

make -C glibc-build install_root="$INSTALL_DIR" install
rm -f "$INSTALL_DIR"/etc/ld.so.cache
