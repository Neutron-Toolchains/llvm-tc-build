#!/bin/bash
# A custom Multi-Stage LLVM Toolchain builder.
# PGO optimized clang for building Linux Kernels.
#!/bin/bash
set -e

LINUX_VER=5.16.10
LINUX_TAR_SHA512SUM="2d1527623f96181c4797a8f73cb769e70321e673835113fbddd1374ca891d41b924220b8fdbaa46e2af7fc49a175e56524291b1816f4f6680128155c110f703e"
BINUTILS_VER="2_38"
BUILDDIR=$(pwd)
CLEAN_BUILD=3

LLVM_DIR="$BUILDDIR/llvm-project"
BINUTILS_DIR="$BUILDDIR/binutils-gdb"
KERNEL_DIR="$BUILDDIR/linux-$LINUX_VER"
LLVM_BUILD="$BUILDDIR/llvm-build"

PERSONAL=0
msg() {
	if [[ "$PERSONAL" -eq 1 ]]; then
		telegram-send "$1"
	else
		echo "==> $1"
	fi
}

msg "Starting LLVM Build"

rm -rf $KERNEL_DIR
if [[ "$CLEAN_BUILD" -eq 3 ]]; then
	rm -rf $LLVM_BUILD
fi

llvm_clone() {
	if ! git clone https://github.com/llvm/llvm-project.git; then
		msg "llvm-project git clone: Failed" >&2
		exit 1
	fi
}

llvm_pull() {
	if ! git pull https://github.com/llvm/llvm-project.git; then
		msg "llvm-project git Pull: Failed" >&2
		exit 1
	fi
}

binutils_clone() {
	if ! git clone https://sourceware.org/git/binutils-gdb.git -b binutils-$BINUTILS_VER-branch; then
		msg "binutils git clone: Failed" >&2
		exit 1
	fi
}

binutils_pull() {
	if ! git pull https://sourceware.org/git/binutils-gdb.git binutils-$BINUTILS_VER-branch; then
		msg "binutils git Pull: Failed" >&2
		exit 1
	fi
}

if [ -d "$LLVM_DIR"/ ]; then
	cd $LLVM_DIR/
	if ! git status; then
		msg "llvm-project dir found but not a git repo, recloning"
		cd $BUILDDIR
		llvm_clone
	else
		msg "Existing llvm repo found, skipping clone"
		msg "Fetching new changes"
		llvm_pull
		cd $BUILDDIR
	fi
else
	msg "cloning llvm project repo"
	llvm_clone
fi

if [ -e linux-$LINUX_VER.tar.xz ]; then
	msg "Existing linux tarball found, skipping download"
else
	msg "Downloading linux tarball"
	wget "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$LINUX_VER.tar.xz"
fi

msg "Checking file integrity of the tarball"
msg "File: linux-$LINUX_VER.tar.xz"
msg "Algorithm: sha512"
if ! echo "$LINUX_TAR_SHA512SUM linux-$LINUX_VER.tar.xz" | sha512sum -c -; then
	msg "File integrity check: Failed" >&2
	exit 1
fi

msg "Extracting Linux tarball with tar"
if ! pv "linux-$LINUX_VER.tar.xz" | tar -xJf-; then
	msg "File Extraction: Failed" >&2
	exit 1
fi

mkdir -p "$BUILDDIR/llvm-build"

if [ -d "$BINUTILS_DIR"/ ]; then
	cd $BINUTILS_DIR/
	if ! git status; then
		msg "GNU binutils dir found but not a git repo, recloning"
		cd $BUILDDIR
		binutils_clone
	else
		msg "Existing binutils repo found, skipping clone"
		msg "Fetching new changes"
		binutils_pull
		cd $BUILDDIR
	fi
else
	msg "cloning GNU binutils repo"
	binutils_clone
fi

LLVM_PROJECT="$LLVM_DIR/llvm"

msg "Starting Stage 1 Build"
cd "$LLVM_BUILD"
OUT="$LLVM_BUILD/stage1"
if [ -d "$OUT" ]; then
	if [[ "$CLEAN_BUILD" -gt 0 ]]; then
		rm -rf "$OUT"
		mkdir "$OUT"
	fi
else
	mkdir "$OUT"
fi
cd "$OUT"
CC=clang CXX=clang++ LD=lld AR=llvm-ar AS=llvm-as NM=llvm-nm STRIP=llvm-strip \
	OBJDUMP=llvm-objdump HOSTCC=clang HOSTLD=lld HOSTAR=llvm-ar OBJCOPY=llvm-objcopy \
	CFLAGS="-march=x86-64 -mtune=generic -ffunction-sections -fdata-sections -falign-functions=32 -flto=thin -fsplit-lto-unit -O3" \
	CXXFLAGS="-march=x86-64 -mtune=generic -ffunction-sections -fdata-sections -falign-functions=32 -flto=thin -fsplit-lto-unit -O3" \
	cmake -G Ninja --log-level=NOTICE \
	-DLLVM_TARGETS_TO_BUILD="X86" \
	-DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt" \
	-DCMAKE_BUILD_TYPE=Release \
	-DLLVM_BINUTILS_INCDIR="$BUILDDIR/binutils-gdb/include" \
	-DLLVM_ENABLE_PLUGINS=ON \
	-DCLANG_ENABLE_ARCMT=OFF \
	-DCLANG_ENABLE_STATIC_ANALYZER=OFF \
	-DCLANG_PLUGIN_SUPPORT=OFF \
	-DLLVM_ENABLE_BINDINGS=OFF \
	-DLLVM_ENABLE_OCAMLDOC=OFF \
	-DLLVM_INCLUDE_EXAMPLES=OFF \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_INCLUDE_DOCS=OFF \
	-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
	-DCOMPILER_RT_BUILD_XRAY=OFF \
	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	-DCLANG_VENDOR="Neutron-Clang" \
	-DLLVM_ENABLE_BACKTRACES=OFF \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-D-DLLVM_ENABLE_LTO=Thin \
	-DLLVM_ENABLE_LLD=ON \
	-DLLVM_TOOL_CLANG_BUILD=ON \
	-DLLVM_TOOL_LLD_BUILD=ON \
	-DLLVM_CCACHE_BUILD=ON \
	-DLLVM_PARALLEL_COMPILE_JOBS=8 \
	-DLLVM_PARALLEL_LINK_JOBS=8 \
	-DCMAKE_C_FLAGS=-O3 \
	-DCMAKE_CXX_FLAGS=-O3 \
	-DCMAKE_INSTALL_PREFIX="$OUT/install" \
	"$LLVM_PROJECT"

msg "Installing to $OUT/install"
ninja install || (
	msg "Could not install project!"
	exit 1
)

STAGE1="$LLVM_BUILD/stage1/install/bin"
msg "Stage 1 Build: End"

# Stage 2 (to enable collecting profiling data)
msg "Stage 2: Build Start"
cd "$LLVM_BUILD"
OUT="$LLVM_BUILD/stage2-prof-gen"

if [ -d "$OUT" ]; then
	if [[ "$CLEAN_BUILD" -gt 1 ]]; then
		rm -rf "$OUT"
		mkdir "$OUT"
	fi
else
	mkdir "$OUT"
fi
cd "$OUT"
export PATH=$STAGE1:$PATH
CFLAGS="-march=x86-64 -mtune=generic -ffunction-sections -fdata-sections -falign-functions=32 -flto=thin -fsplit-lto-unit -O2" \
	CXXFLAGS="-march=x86-64 -mtune=generic -ffunction-sections -fdata-sections -falign-functions=32 -flto=thin -fsplit-lto-unit -O2" \
	cmake -G Ninja --log-level=NOTICE \
	-DCLANG_VENDOR="Neutron-Clang" \
	-DLLVM_TARGETS_TO_BUILD='AArch64;ARM;X86' \
	-DCMAKE_BUILD_TYPE=Release \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-DLLVM_ENABLE_PROJECTS='clang;lld;compiler-rt' \
	-DLLVM_BINUTILS_INCDIR="$BUILDDIR/binutils-gdb/include" \
	-DLLVM_ENABLE_PLUGINS=ON \
	-DCLANG_ENABLE_ARCMT=OFF \
	-DCLANG_ENABLE_STATIC_ANALYZER=OFF \
	-DCLANG_PLUGIN_SUPPORT=OFF \
	-DLLVM_ENABLE_BINDINGS=OFF \
	-DLLVM_ENABLE_OCAMLDOC=OFF \
	-DLLVM_EXTERNAL_CLANG_TOOLS_EXTRA_SOURCE_DIR='' \
	-DLLVM_INCLUDE_DOCS=OFF \
	-DLLVM_INCLUDE_EXAMPLES=OFF \
	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	-DCOMPILER_RT_BUILD_CRT=OFF \
	-DCOMPILER_RT_BUILD_XRAY=OFF \
	-DLLVM_ENABLE_TERMINFO=OFF \
	-DLLVM_ENABLE_LTO=Thin \
	-DLLVM_USE_LINKER="$STAGE1"/ld.lld \
	-DCMAKE_C_COMPILER="$STAGE1"/../../bin/clang \
	-DCMAKE_CXX_COMPILER="$STAGE1"/../../bin/clang++ \
	-DCMAKE_RANLIB="$STAGE1"/../../bin/llvm-ranlib \
	-DCMAKE_AR="$STAGE1"/../../bin/llvm-ar \
	-DCLANG_TABLEGEN="$STAGE1"/../../bin/clang-tblgen \
	-DLLVM_TABLEGEN="$STAGE1"/../../bin/llvm-tblgen \
	-DLLVM_BUILD_INSTRUMENTED=IR \
	-DLLVM_BUILD_RUNTIME=OFF \
	-DLLVM_VP_COUNTERS_PER_SITE=6 \
	-DLLVM_PARALLEL_COMPILE_JOBS=8 \
	-DLLVM_PARALLEL_LINK_JOBS=8 \
	-DCMAKE_INSTALL_PREFIX="$OUT/install" \
	"$LLVM_PROJECT"

msg "Installing to $OUT/install"
ninja install || (
	msg "Could not install project!"
	exit 1
)

STAGE2="$OUT/install/bin"
PROFILES="$OUT/profiles"
rm -rf "$PROFILES"/*
msg "Stage 2: Build End"
msg "Stage 2: PGO Train Start"

# Train PGO
cd "$KERNEL_DIR"

msg "Training x86"
make distclean defconfig \
	LLVM=1 \
	CC="$STAGE2"/clang \
	LD="$STAGE2"/ld.lld \
	AR="$STAGE2"/llvm-ar \
	NM="$STAGE2"/llvm-nm \
	LD="$STAGE2"/ld.lld \
	STRIP="$STAGE2"/llvm-strip \
	OBJCOPY="$STAGE2"/llvm-objcopy \
	OBJDUMP="$STAGE2"/llvm-objdump \
	OBJSIZE="$STAGE2"/llvm-size \
	HOSTCC="$STAGE2"/clang \
	HOSTCXX="$STAGE2"/clang++ \
	HOSTAR="$STAGE2"/llvm-ar \
	HOSTLD="$STAGE2"/ld.lld

time make all -j$(nproc --all) \
	LLVM=1 \
	CC="$STAGE2"/clang \
	LD="$STAGE2"/ld.lld \
	AR="$STAGE2"/llvm-ar \
	NM="$STAGE2"/llvm-nm \
	LD="$STAGE2"/ld.lld \
	STRIP="$STAGE2"/llvm-strip \
	OBJCOPY="$STAGE2"/llvm-objcopy \
	OBJDUMP="$STAGE2"/llvm-objdump \
	OBJSIZE="$STAGE2"/llvm-size \
	HOSTCC="$STAGE2"/clang \
	HOSTCXX="$STAGE2"/clang++ \
	HOSTAR="$STAGE2"/llvm-ar \
	HOSTLD="$STAGE2"/ld.lld || exit ${?}

clear

msg "Training arm64"
make distclean defconfig \
	LLVM=1 \
	ARCH=arm64 \
	CC="$STAGE2"/clang \
	LD="$STAGE2"/ld.lld \
	AR="$STAGE2"/llvm-ar \
	NM="$STAGE2"/llvm-nm \
	LD="$STAGE2"/ld.lld \
	STRIP="$STAGE2"/llvm-strip \
	OBJCOPY="$STAGE2"/llvm-objcopy \
	OBJDUMP="$STAGE2"/llvm-objdump \
	OBJSIZE="$STAGE2"/llvm-size \
	HOSTCC="$STAGE2"/clang \
	HOSTCXX="$STAGE2"/clang++ \
	HOSTAR="$STAGE2"/llvm-ar \
	HOSTLD="$STAGE2"/ld.lld \
	CROSS_COMPILE=aarch64-linux-gnu-

time make all -j$(nproc --all) \
	LLVM=1 \
	ARCH=arm64 \
	CC="$STAGE2"/clang \
	LD="$STAGE2"/ld.lld \
	AR="$STAGE2"/llvm-ar \
	NM="$STAGE2"/llvm-nm \
	LD="$STAGE2"/ld.lld \
	STRIP="$STAGE2"/llvm-strip \
	OBJCOPY="$STAGE2"/llvm-objcopy \
	OBJDUMP="$STAGE2"/llvm-objdump \
	OBJSIZE="$STAGE2"/llvm-size \
	HOSTCC="$STAGE2"/clang \
	HOSTCXX="$STAGE2"/clang++ \
	HOSTAR="$STAGE2"/llvm-ar \
	HOSTLD="$STAGE2"/ld.lld \
	CROSS_COMPILE=aarch64-linux-gnu- || exit ${?}

clear

msg "Training arm"
make distclean defconfig \
	LLVM=1 \
	ARCH=arm \
	CC="$STAGE2"/clang \
	LD="$STAGE2"/ld.lld \
	AR="$STAGE2"/llvm-ar \
	NM="$STAGE2"/llvm-nm \
	LD="$STAGE2"/ld.lld \
	STRIP="$STAGE2"/llvm-strip \
	OBJCOPY="$STAGE2"/llvm-objcopy \
	OBJDUMP="$STAGE2"/llvm-objdump \
	OBJSIZE="$STAGE2"/llvm-size \
	HOSTCC="$STAGE2"/clang \
	HOSTCXX="$STAGE2"/clang++ \
	HOSTAR="$STAGE2"/llvm-ar \
	HOSTLD="$STAGE2"/ld.lld \
	CROSS_COMPILE=arm-linux-gnueabi-

time make all -j$(nproc --all) \
	LLVM=1 \
	ARCH=arm \
	CC="$STAGE2"/clang \
	LD="$STAGE2"/ld.lld \
	AR="$STAGE2"/llvm-ar \
	NM="$STAGE2"/llvm-nm \
	LD="$STAGE2"/ld.lld \
	STRIP="$STAGE2"/llvm-strip \
	OBJCOPY="$STAGE2"/llvm-objcopy \
	OBJDUMP="$STAGE2"/llvm-objdump \
	OBJSIZE="$STAGE2"/llvm-size \
	HOSTCC="$STAGE2"/clang \
	HOSTCXX="$STAGE2"/clang++ \
	HOSTAR="$STAGE2"/llvm-ar \
	HOSTLD="$STAGE2"/ld.lld \
	CROSS_COMPILE=arm-linux-gnueabi- || exit ${?}

# Merge training
cd "$PROFILES"
"$STAGE2"/llvm-profdata merge -output=clang.profdata *

msg "Stage 2: PGO Training End"

# Stage 3 (built with PGO profile data)
msg "Stage 3 Build: Start"
cd "$LLVM_BUILD"
OUT="$LLVM_BUILD/stage3"

if [ -d "$OUT" ]; then
	if [[ "$CLEAN_BUILD" -gt 2 ]]; then
		rm -rf "$OUT"
		mkdir "$OUT"
	fi
else
	mkdir "$OUT"
fi
cd "$OUT"
CFLAGS="-march=x86-64 -mtune=generic -ffunction-sections -fdata-sections -falign-functions=32 -flto=thin -fsplit-lto-unit -O3" \
	CXXFLAGS="-march=x86-64 -mtune=generic -ffunction-sections -fdata-sections -falign-functions=32 -flto=thin -fsplit-lto-unit -O3" \
	cmake -G Ninja --log-level=NOTICE \
	-DCLANG_VENDOR="Neutron-Clang" \
	-DLLVM_TARGETS_TO_BUILD='AArch64;ARM;X86' \
	-DCMAKE_BUILD_TYPE=Release \
	-DLLVM_TOOL_CLANG_BUILD=ON \
	-DLLVM_TOOL_LLD_BUILD=ON \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-DLLVM_ENABLE_PROJECTS='clang;lld;compiler-rt;polly' \
	-DLLVM_BINUTILS_INCDIR="$BUILDDIR/binutils-gdb/include" \
	-DLLVM_ENABLE_PLUGINS=ON \
	-DCLANG_ENABLE_ARCMT=OFF \
	-DCLANG_ENABLE_STATIC_ANALYZER=OFF \
	-DCLANG_PLUGIN_SUPPORT=OFF \
	-DLLVM_ENABLE_BINDINGS=OFF \
	-DLLVM_ENABLE_OCAMLDOC=OFF \
	-DLLVM_EXTERNAL_CLANG_TOOLS_EXTRA_SOURCE_DIR='' \
	-DLLVM_INCLUDE_DOCS=OFF \
	-DLLVM_INCLUDE_EXAMPLES=OFF \
	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	-DCOMPILER_RT_BUILD_CRT=OFF \
	-DCOMPILER_RT_BUILD_XRAY=OFF \
	-DLLVM_ENABLE_TERMINFO=OFF \
	-DLLVM_ENABLE_LTO=Thin \
	-DLLVM_USE_LINKER="$STAGE1"/ld.lld \
	-DCMAKE_C_COMPILER="$STAGE1"/../../bin/clang \
	-DCMAKE_CXX_COMPILER="$STAGE1"/../../bin/clang++ \
	-DCMAKE_RANLIB="$STAGE1"/../../bin/llvm-ranlib \
	-DCMAKE_AR="$STAGE1"/../../bin/llvm-ar \
	-DCLANG_TABLEGEN="$STAGE1"/../../bin/clang-tblgen \
	-DLLVM_TABLEGEN="$STAGE1"/../../bin/llvm-tblgen \
	-DLLVM_PROFDATA_FILE="$PROFILES"/clang.profdata \
	-DLLVM_PARALLEL_COMPILE_JOBS=8 \
	-DLLVM_PARALLEL_LINK_JOBS=8 \
	-DCMAKE_C_FLAGS=-O3 \
	-DCMAKE_CXX_FLAGS=-O3 \
	-DCMAKE_INSTALL_PREFIX="$OUT/install" \
	"$LLVM_PROJECT"

msg "Installing to $OUT/install"
ninja install || (
	msg "Could not install project!"
	exit 1
)

STAGE3="$OUT/install/bin"
msg "Stage 3 Build: End"

msg "Moving stage 3 install dir to build dir"
mv $OUT/install install/
msg "LLVM build finished. Final toolchain installed at:"
msg "$BUILDDIR/install"
