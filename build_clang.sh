#!/usr/bin/env bash
# shellcheck disable=SC2086
# A custom Multi-Stage LLVM Toolchain builder.
# PGO optimized clang for building Linux Kernels.
set -e

# Specify some variables.
LINUX_VER="5.19.12"
BINUTILS_VER="2_39"
BUILDDIR=$(pwd)
CLEAN_BUILD=3
POLLY_OPT=1
BOLT_OPT=1

# DO NOT CHANGE
USE_SYSTEM_BINUTILS_64=1
USE_SYSTEM_BINUTILS_32=1

if [[ $POLLY_OPT -eq 1 ]]; then
	POLLY_OPT_FLAGS="-mllvm -polly"
fi

LLVM_DIR="$BUILDDIR/llvm-project"
BINUTILS_DIR="$BUILDDIR/binutils-gdb"
TEMP_BINTUILS_BUILD="$BUILDDIR/temp-binutils-build"
TEMP_BINTUILS_INSTALL="$BUILDDIR/temp-binutils"
KERNEL_DIR="$BUILDDIR/linux-$LINUX_VER"

LLVM_BUILD="$BUILDDIR/llvm-build"

if [[ $CI -eq 1 ]]; then
	telegram-send --format html "\
		<b>🔨 Neutron Clang Build Started</b>
		Build Date: <code>$(date +"%Y-%m-%d %H:%M")</code>"
fi

echo "Starting LLVM Build"

rm -rf $KERNEL_DIR
rm -rf $TEMP_BINTUILS_BUILD && mkdir -p $TEMP_BINTUILS_BUILD
rm -rf $TEMP_BINTUILS_INSTALL && mkdir -p $TEMP_BINTUILS_INSTALL

if [[ $CLEAN_BUILD -eq 3 ]]; then
	rm -rf $LLVM_BUILD
fi

# Where all relevant build-related repositories are cloned.
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
		tar xf linux-$1.tar.xz
	else
		echo "Downloading linux-$1 tarball"
		wget "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$1.tar.xz"
		tar xf linux-$1.tar.xz
	fi
}

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
		CFLAGS="-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections" \
		CXXFLAGS="-march=x86-64 -mtune=generic -flto=auto -flto-compression-level=10 -O3 -pipe -ffunction-sections -fdata-sections" \
		LDFLAGS="-Wl,-O3,--sort-common,--as-needed,-z,now" \
		--target=$1 \
		--prefix=$TEMP_BINTUILS_INSTALL \
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

	make -s -j$(nproc --all) >/dev/null
	make install -s -j$(nproc --all) >/dev/null
	echo "temp binutils build done, removing build dir"
	rm -rf $TEMP_BINTUILS_BUILD
}

bolt_profile_gen() {

	if [ "$1" = "perf" ]; then
		echo "Training arm64"
		cd "$KERNEL_DIR"
		make distclean defconfig \
			LLVM=1 \
			LLVM_IAS=1 \
			ARCH=arm64 \
			CC="$STAGE3"/clang \
			LD="$STAGE3"/ld.lld \
			AR="$STAGE3"/llvm-ar \
			NM="$STAGE3"/llvm-nm \
			LD="$STAGE3"/ld.lld \
			STRIP="$STAGE3"/llvm-strip \
			OBJCOPY="$STAGE3"/llvm-objcopy \
			OBJDUMP="$STAGE3"/llvm-objdump \
			OBJSIZE="$STAGE3"/llvm-size \
			HOSTCC="$STAGE3"/clang \
			HOSTCXX="$STAGE3"/clang++ \
			HOSTAR="$STAGE3"/llvm-ar \
			HOSTLD="$STAGE3"/ld.lld \
			CROSS_COMPILE=aarch64-linux-gnu-

		perf record --output ${BOLT_PROFILES}/perf.data --event cycles:u --branch-filter any,u -- make all -s -j$(nproc --all) \
			LLVM=1 \
			LLVM_IAS=1 \
			ARCH=arm64 \
			CC="$STAGE3"/clang \
			LD="$STAGE3"/ld.lld \
			AR="$STAGE3"/llvm-ar \
			NM="$STAGE3"/llvm-nm \
			LD="$STAGE3"/ld.lld \
			STRIP="$STAGE3"/llvm-strip \
			OBJCOPY="$STAGE3"/llvm-objcopy \
			OBJDUMP="$STAGE3"/llvm-objdump \
			OBJSIZE="$STAGE3"/llvm-size \
			HOSTCC="$STAGE3"/clang \
			HOSTCXX="$STAGE3"/clang++ \
			HOSTAR="$STAGE3"/llvm-ar \
			HOSTLD="$STAGE3"/ld.lld \
			CROSS_COMPILE=aarch64-linux-gnu- || (
			echo "Kernel Build failed!"
			exit 1
		)
		cd "$OUT"

		"$STAGE1"/perf2bolt "$STAGE3"/clang-16 \
			-p ${BOLT_PROFILES}/perf.data \
			-o ${BOLT_PROFILES}/clang-16.fdata || (
			echo "Failed to convert perf data"
			exit 1
		)

		"$STAGE1"/llvm-bolt "$STAGE3"/clang-16 \
			-o "$STAGE3"/clang-16.bolt \
			--data ${BOLT_PROFILES}/clang-16.fdata \
			-relocs \
			-split-functions \
			-split-all-cold \
			-icf=1 \
			-lite=1 \
			-split-eh \
			-use-gnu-stack \
			-jump-tables=move \
			-dyno-stats \
			-reorder-functions=hfsort \
			-reorder-blocks=ext-tsp \
			-tail-duplication=cache || (
			echo "Could not optimize clang with BOLT"
			exit 1
		)

		mv "$STAGE3"/clang-16 "$STAGE3"/clang-16.org
		mv "$STAGE3"/clang-16.bolt "$STAGE3"/clang-16
	else
		"$STAGE1"/llvm-bolt \
			--instrument \
			--instrumentation-file-append-pid \
			--instrumentation-file=${BOLT_PROFILES}/clang-16.fdata \
			"$STAGE3"/clang-16 \
			-o "$STAGE3"/clang-16.inst

		mv "$STAGE3"/clang-16 "$STAGE3"/clang-16.org
		mv "$STAGE3"/clang-16.inst "$STAGE3"/clang-16

		echo "Training arm64"
		cd "$KERNEL_DIR"
		make distclean defconfig \
			LLVM=1 \
			LLVM_IAS=1 \
			ARCH=arm64 \
			CC="$STAGE3"/clang \
			LD="$STAGE3"/ld.lld \
			AR="$STAGE3"/llvm-ar \
			NM="$STAGE3"/llvm-nm \
			LD="$STAGE3"/ld.lld \
			STRIP="$STAGE3"/llvm-strip \
			OBJCOPY="$STAGE3"/llvm-objcopy \
			OBJDUMP="$STAGE3"/llvm-objdump \
			OBJSIZE="$STAGE3"/llvm-size \
			HOSTCC="$STAGE3"/clang \
			HOSTCXX="$STAGE3"/clang++ \
			HOSTAR="$STAGE3"/llvm-ar \
			HOSTLD="$STAGE3"/ld.lld \
			CROSS_COMPILE=aarch64-linux-gnu-

		make all -s -j$(nproc --all) \
			LLVM=1 \
			LLVM_IAS=1 \
			ARCH=arm64 \
			CC="$STAGE3"/clang \
			LD="$STAGE3"/ld.lld \
			AR="$STAGE3"/llvm-ar \
			NM="$STAGE3"/llvm-nm \
			LD="$STAGE3"/ld.lld \
			STRIP="$STAGE3"/llvm-strip \
			OBJCOPY="$STAGE3"/llvm-objcopy \
			OBJDUMP="$STAGE3"/llvm-objdump \
			OBJSIZE="$STAGE3"/llvm-size \
			HOSTCC="$STAGE3"/clang \
			HOSTCXX="$STAGE3"/clang++ \
			HOSTAR="$STAGE3"/llvm-ar \
			HOSTLD="$STAGE3"/ld.lld \
			CROSS_COMPILE=aarch64-linux-gnu- || (
			echo "Kernel Build failed!"
			exit 1
		)
		cd "$OUT"

		cd $BOLT_PROFILES
		"$STAGE1"/merge-fdata *.fdata >combined.fdata

		"$STAGE1"/llvm-bolt "$STAGE3"/clang-16.org \
			--data combined.fdata \
			-o "$STAGE3"/clang-16 \
			-relocs \
			-split-functions \
			-split-all-cold \
			-icf=1 \
			-lite=1 \
			-split-eh \
			-use-gnu-stack \
			-jump-tables=move \
			-dyno-stats \
			-reorder-functions=hfsort \
			-reorder-blocks=ext-tsp \
			-tail-duplication=cache || (
			echo "Could not optimize clang with BOLT"
			exit 1
		)
	fi
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

mkdir -p "$BUILDDIR/llvm-build"

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

get_linux_5_tarball $LINUX_VER

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

OPT_FLAGS="-O3 -march=native -mtune=native -ffunction-sections -fdata-sections"
OPT_FLAGS_LD="-Wl,-O3,--sort-common,--as-needed,-z,now -fuse-ld=$LLVM_BIN_DIR/ld.lld"

if [[ $POLLY_OPT -eq 1 ]]; then
	if [[ $BOLT_OPT -eq 1 ]]; then
		STAGE1_PROJS="clang;lld;compiler-rt;bolt;polly"
	else
		STAGE1_PROJS="clang;lld;compiler-rt;polly"
	fi
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

ninja -j$(nproc --all) >/dev/null || (
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

OPT_FLAGS="-march=x86-64 -mtune=generic -ffunction-sections -fdata-sections -flto=thin -fsplit-lto-unit -O3"
OPT_FLAGS_LD="-Wl,-O3,--sort-common,--as-needed,-z,now -Wl,--lto-O3 -fuse-ld=$STAGE1/ld.lld"

if [[ $POLLY_OPT -eq 1 ]]; then
	OPT_FLAGS="$OPT_FLAGS $POLLY_OPT_FLAGS"
fi

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
ninja install -j$(nproc --all) >/dev/null || (
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
	LLVM_IAS=1 \
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

time make all -s -j$(nproc --all) \
	LLVM=1 \
	LLVM_IAS=1 \
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

echo "Training arm64"
make distclean defconfig \
	LLVM=1 \
	LLVM_IAS=1 \
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

time make all -s -j$(nproc --all) \
	LLVM=1 \
	LLVM_IAS=1 \
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

# Merge training
cd "$PROFILES"
"$STAGE2"/llvm-profdata merge -output=clang.profdata *

if [[ $BOLT_OPT -eq 0 ]]; then
	rm -rf "$TEMP_BINTUILS_INSTALL"
fi

echo "Stage 2: PGO Training End"

# Stage 3 (built with PGO profile data)
echo "Stage 3 Build: Start"

export PATH="$MODDED_PATH"

OPT_FLAGS="-march=x86-64 -mtune=generic -ffunction-sections -fdata-sections -flto=full -O3"

if [[ $POLLY_OPT -eq 1 ]]; then
	OPT_FLAGS="$OPT_FLAGS $POLLY_OPT_FLAGS"
fi

if [[ $BOLT_OPT -eq 1 ]]; then
	OPT_FLAGS_LD_EXE="$OPT_FLAGS_LD -Wl,--emit-relocs"
else
	OPT_FLAGS_LD_EXE="$OPT_FLAGS_LD"
fi

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
	-DCMAKE_EXE_LINKER_FLAGS="$OPT_FLAGS_LD_EXE" \
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

if [[ $BOLT_OPT -eq 1 ]]; then
	# Optimize final built clang with BOLT
	BOLT_PROFILES="$OUT/bolt-prof"
	rm -rf $BOLT_PROFILES
	mkdir -p "$BOLT_PROFILES"
	export PATH="$STAGE3:$BINTUILS_64_BIN_DIR:$BINTUILS_32_BIN_DIR:$STOCK_PATH"
	if [[ $CI -eq 1 ]]; then
		echo "Performing BOLT with instrumenting!"
		bolt_profile_gen "instrumenting" || (
			echo "Optimizing with BOLT failed!"
			exit 1
		)
	else
		perf record -e cycles:u -j any,u -- sleep 1 &>/dev/null
		if [[ $? == "0" ]]; then
			echo "Performing BOLT with sampling!"
			bolt_profile_gen "perf" || (
				echo "Optimizing with BOLT failed!"
				exit 1
			)
		else
			echo "Performing BOLT with instrumenting!"
			bolt_profile_gen "instrumenting" || (
				echo "Optimizing with BOLT failed!"
				exit 1
			)
		fi
	fi
	rm -rf "$TEMP_BINTUILS_INSTALL"
fi

echo "Moving stage 3 install dir to build dir"
mv $OUT/install $BUILDDIR/install/
echo "LLVM build finished. Final toolchain installed at:"
echo "$BUILDDIR/install"
