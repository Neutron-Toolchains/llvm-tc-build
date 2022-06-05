#!/bin/bash
# A custom Multi-Stage LLVM Toolchain builder.
# PGO optimized clang for building Linux Kernels.
#!/bin/bash
set -e

LINUX_VER=5.18
LINUX_TAR_SHA512SUM="dbbc9d1395898a498fa4947fceda1781344fa5d360240f753810daa4fa88e519833e2186c4e582a8f1836e6413e9e85f6563c7770523b704e8702d67622f98b5"

# Extended PGO profiling
LINUX_4_9_VER=4.9.316
LINUX_4_9_TAR_SHA512SUM="6e3d19b7325ff12b01fc704c2b74de5c6afefe26c64341114ee73ca49395a8d5ab20c68ec16ab6798e71eb6dc85297e436fd447c2020b302803f65b029be6531"

LINUX_4_14_VER=4.14.281
LINUX_4_14_TAR_SHA512SUM="7313a2ed1e592ab8bb1248d0511d80aa7d3fdf8e94b3ac36103eeaf140f242efe31a5b6ae7f9d577d57568c3875193844b4266d6c9bd46a9cdbb8e0978bfc2e4"

LINUX_4_19_VER=4.19.245
LINUX_4_19_TAR_SHA512SUM="76d94dd656c7eb71b24ebbdee97e90cceccbb07d0cba3f831bc5bd3c10289549ec0e6f6a240fcba8f0d02de296990db615d7211654bf5ea070b58270fb9e28d4"

LINUX_5_4_VER=5.4.196
LINUX_5_4_TAR_SHA512SUM="d3b5393e929c5686b394bf66b21e92baa82999185259e198c2cb8a49a257d36268468c30a513ec00b08bf1fa885772ea149dd3e67c4e6c1474097735ea074b0a"

LINUX_5_10_VER=5.10.118
LINUX_5_10_TAR_SHA512SUM="5ce0746c3b519abe9e20d1c80264a6a8e49bc18907cc0712fd0520f8e74806028a1b3929da636d6ab88b195895f1873122122b1506b7047c37ba30ed22b357f1"

BINUTILS_VER="2_38"
BUILDDIR=$(pwd)
CLEAN_BUILD=3
EXTENDED_PGO=1
POLLY_OPT=1

# DO NOT CHANGE
USE_SYSTEM_BINUTILS_64=1
USE_SYSTEM_BINUTILS_32=1

if [[ $POLLY_OPT -eq 1 ]]; then
	POLLY_OPT_FLAGS="-mllvm -polly -mllvm -polly-run-dce -mllvm -polly-run-inliner -mllvm -polly-ast-use-context -mllvm -polly-detect-keep-going -mllvm -polly-vectorizer=stripmine -mllvm -polly-invariant-load-hoisting -mllvm -polly-loopfusion-greedy=1 -mllvm -polly-reschedule=1 -mllvm -polly-postopts=1 -mllvm -polly-num-threads=0 -mllvm -polly-omp-backend=LLVM -mllvm -polly-scheduling=dynamic -mllvm -polly-scheduling-chunksize=1"
fi

LLVM_DIR="$BUILDDIR/llvm-project"
BINUTILS_DIR="$BUILDDIR/binutils-gdb"
TEMP_BINTUILS_BUILD="$BUILDDIR/temp-binutils-build"
TEMP_BINTUILS_INSTALL="$BUILDDIR/temp-binutils"
KERNEL_DIR="$BUILDDIR/linux-$LINUX_VER"

KERNEL_4_9_DIR="$BUILDDIR/linux-$LINUX_4_9_VER"
KERNEL_4_14_DIR="$BUILDDIR/linux-$LINUX_4_14_VER"
KERNEL_4_19_DIR="$BUILDDIR/linux-$LINUX_4_19_VER"
KERNEL_5_4_DIR="$BUILDDIR/linux-$LINUX_5_4_VER"
KERNEL_5_10_DIR="$BUILDDIR/linux-$LINUX_5_10_VER"

LLVM_BUILD="$BUILDDIR/llvm-build"

if [[ $CI -eq 1 ]]; then
	telegram-send --format html "\
		<b>🔨 Neutron Clang Build Started</b>
		Build Date: <code>$(date +"%Y-%m-%d %H:%M")</code>"
fi

echo "Starting LLVM Build"

rm -rf $KERNEL_DIR

if [[ $EXTENDED_PGO -eq 1 ]]; then
	rm -rf $KERNEL_4_9_DIR
	rm -rf $KERNEL_4_14_DIR
	rm -rf $KERNEL_4_19_DIR
	rm -rf $KERNEL_5_4_DIR
	rm -rf $KERNEL_5_10_DIR
fi

if [[ $CLEAN_BUILD -eq 3 ]]; then
	rm -rf $LLVM_BUILD
fi

llvm_clone() {
	if ! git clone https://github.com/llvm/llvm-project.git; then
		echo "llvm-project git clone: Failed" >&2
		exit 1
	fi
}

llvm_pull() {
	if ! git pull https://github.com/llvm/llvm-project.git; then
		echo "llvm-project git Pull: Failed" >&2
		exit 1
	fi
}

binutils_clone() {
	if ! git clone https://sourceware.org/git/binutils-gdb.git -b binutils-$BINUTILS_VER-branch; then
		echo "binutils git clone: Failed" >&2
		exit 1
	fi
}

binutils_pull() {
	if ! git pull https://sourceware.org/git/binutils-gdb.git binutils-$BINUTILS_VER-branch; then
		echo "binutils git Pull: Failed" >&2
		exit 1
	fi
}

get_linux_5_tarball() {
	if [ -e linux-$1.tar.xz ]; then
		echo "Existing linux-$1 tarball found, skipping download"
	else
		echo "Downloading linux-$1 tarball"
		wget "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$1.tar.xz"
	fi
}

get_linux_4_tarball() {
	if [ -e linux-$1.tar.xz ]; then
		echo "Existing linux-$1 tarball found, skipping download"
	else
		echo "Downloading linux-$1 tarball"
		wget "https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-$1.tar.xz"
	fi
}

verify_and_extract_linux_tarball() {
	echo "Checking file integrity of the tarball"
	echo "File: linux-$1.tar.xz"
	echo "Algorithm: sha512"
	if ! echo "$2 linux-$1.tar.xz" | sha512sum -c -; then
		echo "File integrity check: Failed" >&2
		exit 1
	fi

	echo "Extracting Linux tarball with tar"
	if ! pv "linux-$1.tar.xz" | tar -xJf-; then
		echo "File Extraction: Failed" >&2
		exit 1
	fi
}

extended_pgo_kramel_compile() {
	clear
	echo "Training Kernel Version=$1 Arch=$2"
	make distclean defconfig \
		LLVM=1 \
		ARCH=$2 \
		CC="$STAGE2"/clang \
		AR="$STAGE2"/llvm-ar \
		NM="$STAGE2"/llvm-nm \
		LD=$3 \
		STRIP="$STAGE2"/llvm-strip \
		OBJCOPY="$STAGE2"/llvm-objcopy \
		OBJDUMP="$STAGE2"/llvm-objdump \
		OBJSIZE="$STAGE2"/llvm-size \
		HOSTCC="$STAGE2"/clang \
		HOSTCXX="$STAGE2"/clang++ \
		HOSTAR="$STAGE2"/llvm-ar \
		HOSTLD="$STAGE2"/ld.lld \
		CROSS_COMPILE=$4

	time make all -j$(nproc --all) \
		LLVM=1 \
		ARCH=$2 \
		CC="$STAGE2"/clang \
		AR="$STAGE2"/llvm-ar \
		NM="$STAGE2"/llvm-nm \
		LD=$3 \
		STRIP="$STAGE2"/llvm-strip \
		OBJCOPY="$STAGE2"/llvm-objcopy \
		OBJDUMP="$STAGE2"/llvm-objdump \
		OBJSIZE="$STAGE2"/llvm-size \
		HOSTCC="$STAGE2"/clang \
		HOSTCXX="$STAGE2"/clang++ \
		HOSTAR="$STAGE2"/llvm-ar \
		HOSTLD="$STAGE2"/ld.lld \
		CROSS_COMPILE=$4 || exit ${?}
}

if [ -d "$LLVM_DIR"/ ]; then
	cd $LLVM_DIR/
	if ! git status; then
		echo "llvm-project dir found but not a git repo, recloning"
		cd $BUILDDIR
		llvm_clone
	else
		echo "Existing llvm repo found, skipping clone"
		echo "Fetching new changes"
		llvm_pull
		cd $BUILDDIR
	fi
else
	echo "cloning llvm project repo"
	llvm_clone
fi

get_linux_5_tarball $LINUX_VER

if [[ $EXTENDED_PGO -eq 1 ]]; then
	echo "Extended PGO profiling enabled!"
	echo "Downloading needed linux tar balls"
	get_linux_5_tarball $LINUX_5_10_VER
	get_linux_5_tarball $LINUX_5_4_VER
	get_linux_4_tarball $LINUX_4_19_VER
	get_linux_4_tarball $LINUX_4_14_VER
	get_linux_4_tarball $LINUX_4_9_VER
fi

verify_and_extract_linux_tarball $LINUX_VER $LINUX_TAR_SHA512SUM

if [[ $EXTENDED_PGO -eq 1 ]]; then
	echo "Extended PGO profiling enabled!"
	echo "extracting tar balls for extended PGO profiling"
	verify_and_extract_linux_tarball $LINUX_5_10_VER $LINUX_5_10_TAR_SHA512SUM
	verify_and_extract_linux_tarball $LINUX_5_4_VER $LINUX_5_4_TAR_SHA512SUM
	verify_and_extract_linux_tarball $LINUX_4_19_VER $LINUX_4_19_TAR_SHA512SUM
	verify_and_extract_linux_tarball $LINUX_4_14_VER $LINUX_4_14_TAR_SHA512SUM
	verify_and_extract_linux_tarball $LINUX_4_9_VER $LINUX_4_9_TAR_SHA512SUM
fi

mkdir -p "$BUILDDIR/llvm-build"

mkdir -p "$TEMP_BINTUILS_BUILD"
mkdir -p "$TEMP_BINTUILS_INSTALL"

if [ -d "$BINUTILS_DIR"/ ]; then
	cd $BINUTILS_DIR/
	if ! git status; then
		echo "GNU binutils dir found but not a git repo, recloning"
		cd $BUILDDIR
		binutils_clone
	else
		echo "Existing binutils repo found, skipping clone"
		echo "Fetching new changes"
		binutils_pull
		cd $BUILDDIR
	fi
else
	echo "cloning GNU binutils repo"
	binutils_clone
fi

build_temp_binutils() {
	rm -rf $TEMP_BINTUILS_BUILD
	mkdir -p $TEMP_BINTUILS_BUILD
	if [ "$1" = "aarch64-linux-gnu" ]; then
		USE_SYSTEM_BINUTILS_64=0
	else
		USE_SYSTEM_BINUTILS_32=0
	fi
	cd $TEMP_BINTUILS_BUILD
	"$BINUTILS_DIR"/configure \
		CC="gcc" \
		CXX="g++" \
		CFLAGS="-march=x86-64 -mtune=generic -flto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections -ffat-lto-objects" \
		CXXFLAGS="-march=x86-64 -mtune=generic -flto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections -ffat-lto-objects" \
		LDFLAGS="-O3" \
		--target=$1 \
		--prefix=$TEMP_BINTUILS_INSTALL \
		--disable-compressed-debug-sections \
		--disable-gdb \
		--disable-gdbserver \
		--disable-docs \
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
		--with-system-zlib \
		--enable-ld=default \
		--quiet \
		--with-pkgversion="Neutron Binutils"

	make -j$(($(nproc --all) + 2))
	make install -j$(($(nproc --all) + 2))
}

LLVM_PROJECT="$LLVM_DIR/llvm"

echo "Starting Stage 1 Build"
cd "$LLVM_BUILD"
OUT="$LLVM_BUILD/stage1"
if [ -d "$OUT" ]; then
	if [[ $CLEAN_BUILD -gt 0 ]]; then
		rm -rf "$OUT"
		mkdir "$OUT"
	fi
else
	mkdir "$OUT"
fi
cd "$OUT"

LLVM_BIN_DIR=$(readlink -f $(which clang) | rev | cut -d'/' -f2- | rev)

OPT_FLAGS="-march=x86-64 -mtune=generic -ffunction-sections -fdata-sections -flto=thin -fsplit-lto-unit -O3"
OPT_FLAGS_LD="-Wl,-O3 -Wl,--lto-O3 -fuse-ld=$LLVM_BIN_DIR/ld.lld"

if [[ $POLLY_OPT -eq 1 ]]; then
	STAGE1_PROJS="clang;lld;compiler-rt;polly"
else
	STAGE1_PROJS="clang;lld;compiler-rt"
fi

cmake -G Ninja -Wno-dev --log-level=NOTICE \
	-DLLVM_TARGETS_TO_BUILD="X86" \
	-DLLVM_ENABLE_PROJECTS="$STAGE1_PROJS" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCLANG_ENABLE_ARCMT=OFF \
	-DCLANG_ENABLE_STATIC_ANALYZER=OFF \
	-DCLANG_PLUGIN_SUPPORT=OFF \
	-DLLVM_ENABLE_BINDINGS=OFF \
	-DLLVM_ENABLE_OCAMLDOC=OFF \
	-DLLVM_INCLUDE_EXAMPLES=OFF \
	-DLLVM_EXTERNAL_CLANG_TOOLS_EXTRA_SOURCE_DIR= \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_INCLUDE_DOCS=OFF \
	-DLLVM_ENABLE_TERMINFO=OFF \
	-DCOMPILER_RT_BUILD_CRT=OFF \
	-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
	-DCOMPILER_RT_BUILD_XRAY=OFF \
	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	-DCLANG_VENDOR="Neutron" \
	-DLLVM_ENABLE_BACKTRACES=OFF \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-DLLVM_ENABLE_LTO=Thin \
	-DCMAKE_C_COMPILER=$LLVM_BIN_DIR/clang \
	-DCMAKE_CXX_COMPILER=$LLVM_BIN_DIR/clang++ \
	-DCMAKE_AR=$LLVM_BIN_DIR/llvm-ar \
	-DCMAKE_NM=$LLVM_BIN_DIR/llvm-nm \
	-DCMAKE_STRIP=$LLVM_BIN_DIR/llvm-strip \
	-DLLVM_USE_LINKER=$LLVM_BIN_DIR/ld.lld \
	-DCMAKE_LINKER=$LLVM_BIN_DIR/ld.lld \
	-DCMAKE_OBJCOPY=$LLVM_BIN_DIR/llvm-objcopy \
	-DCMAKE_OBJDUMP=$LLVM_BIN_DIR/llvm-objdump \
	-DCMAKE_RANLIB=$LLVM_BIN_DIR/llvm-ranlib \
	-DCMAKE_READELF=$LLVM_BIN_DIR/llvm-readelf \
	-DCMAKE_ADDR2LINE=$LLVM_BIN_DIR/llvm-addr2line \
	-DLLVM_TOOL_CLANG_BUILD=ON \
	-DLLVM_TOOL_LLD_BUILD=ON \
	-DLLVM_CCACHE_BUILD=ON \
	-DLLVM_PARALLEL_COMPILE_JOBS=$(nproc --all) \
	-DLLVM_PARALLEL_LINK_JOBS=$(nproc --all) \
	-DCMAKE_C_FLAGS="$OPT_FLAGS" \
	-DCMAKE_ASM_FLAGS="$OPT_FLAGS" \
	-DCMAKE_CXX_FLAGS="$OPT_FLAGS" \
	-DCMAKE_EXE_LINKER_FLAGS="$OPT_FLAGS_LD" \
	-DCMAKE_MODULE_LINKER_FLAGS="$OPT_FLAGS_LD" \
	-DCMAKE_SHARED_LINKER_FLAGS="$OPT_FLAGS_LD" \
	"$LLVM_PROJECT"

ninja -j$(nproc --all) || (
	echo "Could not build project!"
	exit 1
)

STAGE1="$LLVM_BUILD/stage1/bin"
echo "Stage 1 Build: End"

# Stage 2 (to enable collecting profiling data)
echo "Stage 2: Build Start"
cd "$LLVM_BUILD"
OUT="$LLVM_BUILD/stage2-prof-gen"

if [ -d "$OUT" ]; then
	if [[ $CLEAN_BUILD -gt 1 ]]; then
		rm -rf "$OUT"
		mkdir "$OUT"
	fi
else
	mkdir "$OUT"
fi
cd "$OUT"
STOCK_PATH=$PATH
MODDED_PATH="$STAGE1/bin:$STAGE1:$PATH"
export PATH="$MODDED_PATH"
if [[ $POLLY_OPT -eq 1 ]]; then
	OPT_FLAGS="$OPT_FLAGS $POLLY_OPT_FLAGS"
fi

OPT_FLAGS_LD="-Wl,-O3 -Wl,--lto-O3 -fuse-ld=$STAGE1/ld.lld"

cmake -G Ninja -Wno-dev --log-level=NOTICE \
	-DCLANG_VENDOR="Neutron" \
	-DLLVM_TARGETS_TO_BUILD='AArch64;ARM;X86' \
	-DCMAKE_BUILD_TYPE=Release \
	-DLLVM_ENABLE_WARNINGS=OFF \
	-DLLVM_ENABLE_PROJECTS='clang;lld' \
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
	-DCMAKE_C_COMPILER=$STAGE1/clang \
	-DCMAKE_CXX_COMPILER=$STAGE1/clang++ \
	-DCMAKE_AR=$STAGE1/llvm-ar \
	-DCMAKE_NM=$STAGE1/llvm-nm \
	-DCMAKE_STRIP=$STAGE1/llvm-strip \
	-DLLVM_USE_LINKER=$STAGE1/ld.lld \
	-DCMAKE_LINKER=$STAGE1/ld.lld \
	-DCMAKE_OBJCOPY=$STAGE1/llvm-objcopy \
	-DCMAKE_OBJDUMP=$STAGE1/llvm-objdump \
	-DCMAKE_RANLIB=$STAGE1/llvm-ranlib \
	-DCMAKE_READELF=$STAGE1/llvm-readelf \
	-DCMAKE_ADDR2LINE=$STAGE1/llvm-addr2line \
	-DCLANG_TABLEGEN=$STAGE1/clang-tblgen \
	-DLLVM_TABLEGEN=$STAGE1/llvm-tblgen \
	-DLLVM_BUILD_INSTRUMENTED=IR \
	-DLLVM_BUILD_RUNTIME=OFF \
	-DLLVM_LINK_LLVM_DYLIB=ON \
	-DLLVM_VP_COUNTERS_PER_SITE=6 \
	-DLLVM_PARALLEL_COMPILE_JOBS=$(nproc --all) \
	-DLLVM_PARALLEL_LINK_JOBS=$(nproc --all) \
	-DCMAKE_C_FLAGS="$OPT_FLAGS" \
	-DCMAKE_ASM_FLAGS="$OPT_FLAGS" \
	-DCMAKE_CXX_FLAGS="$OPT_FLAGS" \
	-DCMAKE_EXE_LINKER_FLAGS="$OPT_FLAGS_LD" \
	-DCMAKE_MODULE_LINKER_FLAGS="$OPT_FLAGS_LD" \
	-DCMAKE_SHARED_LINKER_FLAGS="$OPT_FLAGS_LD" \
	-DCMAKE_INSTALL_PREFIX="$OUT/install" \
	"$LLVM_PROJECT"

echo "Installing to $OUT/install"
ninja install -j$(nproc --all) || (
	echo "Could not install project!"
	exit 1
)

STAGE2="$OUT/install/bin"
PROFILES="$OUT/profiles"
rm -rf "$PROFILES"/*
echo "Stage 2: Build End"
echo "Stage 2: PGO Train Start"

command -v aarch64-linux-gnu-as &>/dev/null || build_temp_binutils aarch64-linux-gnu
command -v arm-linux-gnueabi-as &>/dev/null || build_temp_binutils arm-linux-gnueabi

if [[ $USE_SYSTEM_BINUTILS_64 -eq 1 ]]; then
	BINTUILS_64_BIN_DIR=$(readlink -f $(which aarch64-linux-gnu-as) | rev | cut -d'/' -f2- | rev)
else
	BINTUILS_64_BIN_DIR="$TEMP_BINTUILS_INSTALL/bin"
fi

if [[ $USE_SYSTEM_BINUTILS_32 -eq 1 ]]; then
	BINTUILS_32_BIN_DIR=$(readlink -f $(which arm-linux-gnueabi-as) | rev | cut -d'/' -f2- | rev)
else
	BINTUILS_32_BIN_DIR="$TEMP_BINTUILS_INSTALL/bin"
fi

export PATH="$STAGE2:$BINTUILS_64_BIN_DIR:$BINTUILS_32_BIN_DIR:$STOCK_PATH"

# Train PGO
cd "$KERNEL_DIR"

echo "Training x86"
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

echo "Training arm64"
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

echo "Training arm"
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

if [[ $EXTENDED_PGO -eq 1 ]]; then
	echo "Extended PGO profiling enabled!"
	echo "Starting Extended PGO training"
	cd "$KERNEL_4_9_DIR"
	extended_pgo_kramel_compile "4.9" "arm64" aarch64-linux-gnu-ld aarch64-linux-gnu-
	cd "$KERNEL_4_14_DIR"
	extended_pgo_kramel_compile "4.14" "arm64" "$STAGE2"/ld.lld aarch64-linux-gnu-
	cd "$KERNEL_4_19_DIR"
	extended_pgo_kramel_compile "4.19" "arm64" "$STAGE2"/ld.lld aarch64-linux-gnu-
	cd "$KERNEL_5_4_DIR"
	extended_pgo_kramel_compile "5.4" "arm64" "$STAGE2"/ld.lld aarch64-linux-gnu-
	cd "$KERNEL_5_10_DIR"
	extended_pgo_kramel_compile "5.10" "arm64" "$STAGE2"/ld.lld aarch64-linux-gnu-
fi

# Merge training
cd "$PROFILES"
"$STAGE2"/llvm-profdata merge -output=clang.profdata *

rm -rf "$TEMP_BINTUILS_BUILD"
rm -rf "$TEMP_BINTUILS_INSTALL"

echo "Stage 2: PGO Training End"

# Stage 3 (built with PGO profile data)
echo "Stage 3 Build: Start"

export PATH="$MODDED_PATH"

cd "$LLVM_BUILD"
OUT="$LLVM_BUILD/stage3"

if [ -d "$OUT" ]; then
	if [[ $CLEAN_BUILD -gt 2 ]]; then
		rm -rf "$OUT"
		mkdir "$OUT"
	fi
else
	mkdir "$OUT"
fi
cd "$OUT"
cmake -G Ninja -Wno-dev --log-level=NOTICE \
	-DCLANG_VENDOR="Neutron" \
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
	-DCMAKE_C_COMPILER=$STAGE1/clang \
	-DCMAKE_CXX_COMPILER=$STAGE1/clang++ \
	-DCMAKE_AR=$STAGE1/llvm-ar \
	-DCMAKE_NM=$STAGE1/llvm-nm \
	-DCMAKE_STRIP=$STAGE1/llvm-strip \
	-DLLVM_USE_LINKER=$STAGE1/ld.lld \
	-DCMAKE_LINKER=$STAGE1/ld.lld \
	-DCMAKE_OBJCOPY=$STAGE1/llvm-objcopy \
	-DCMAKE_OBJDUMP=$STAGE1/llvm-objdump \
	-DCMAKE_RANLIB=$STAGE1/llvm-ranlib \
	-DCMAKE_READELF=$STAGE1/llvm-readelf \
	-DCMAKE_ADDR2LINE=$STAGE1/llvm-addr2line \
	-DCLANG_TABLEGEN=$STAGE1/clang-tblgen \
	-DLLVM_TABLEGEN=$STAGE1/llvm-tblgen \
	-DLLVM_PROFDATA_FILE="$PROFILES"/clang.profdata \
	-DLLVM_PARALLEL_COMPILE_JOBS=$(nproc --all) \
	-DLLVM_PARALLEL_LINK_JOBS=$(nproc --all) \
	-DCMAKE_C_FLAGS="$OPT_FLAGS" \
	-DCMAKE_ASM_FLAGS="$OPT_FLAGS" \
	-DCMAKE_CXX_FLAGS="$OPT_FLAGS" \
	-DCMAKE_EXE_LINKER_FLAGS="$OPT_FLAGS_LD" \
	-DCMAKE_MODULE_LINKER_FLAGS="$OPT_FLAGS_LD" \
	-DCMAKE_SHARED_LINKER_FLAGS="$OPT_FLAGS_LD" \
	-DCMAKE_INSTALL_PREFIX="$OUT/install" \
	"$LLVM_PROJECT"

echo "Installing to $OUT/install"
ninja install -j$(nproc --all) || (
	echo "Could not install project!"
	exit 1
)

STAGE3="$OUT/install/bin"
echo "Stage 3 Build: End"

echo "Moving stage 3 install dir to build dir"
mv $OUT/install $BUILDDIR/install/
echo "LLVM build finished. Final toolchain installed at:"
echo "$BUILDDIR/install"
