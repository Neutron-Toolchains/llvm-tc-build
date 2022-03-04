#!/bin/bash
# A custom Multi-Stage LLVM Toolchain builder.
# PGO optimized clang for building Linux Kernels.
#!/bin/bash
set -e

LINUX_VER=5.16.11
LINUX_TAR_SHA512SUM="d877304a868cf29bb32d059544806314c2cd975be6132eee645d1dd54ed6e1281c4ea4a18ce30c9b59a8d2b5cd9a0bcf9933a36d4754201fb04e06dee2717e7a"

# Extended PGO profiling
LINUX_4_9_VER=4.9.303
LINUX_4_9_TAR_SHA512SUM="7e4724ca91be16d937ac9546d544e59afc2425adefbd86ff9b25683706323630d70a6e67400a88ba7e148072d16a68842786643b70b5a64e22f389005d148221"

LINUX_4_14_VER=4.14.268
LINUX_4_14_TAR_SHA512SUM="cfc2a0df98336752e936444c3212066227acc4eb2523bff186c3fc70e0e6210b9550c9a80446ad637a0e2b1cbe38becfd6191bc27891eb4cf5e78c1d8af2e5b6"

LINUX_4_19_VER=4.19.231
LINUX_4_19_TAR_SHA512SUM="adf889a67a1f8ccd364bc20d97aa6ad9946b5024e35b3b5fb65027a194af5c020e0831fba51b9369d6f86376354adca0f713cdd7e2d9cee1efaaaa816834c446"

LINUX_5_4_VER=5.4.181
LINUX_5_4_TAR_SHA512SUM="10fba413fe8da1b569d1366bf99d18ad3b5765abedb81931f4d00b40daacb8797e122bb2fbc1a739f1d9999e01e0b920faa58be41e2010a625c1d58f1b54e288"

LINUX_5_10_VER=5.10.102
LINUX_5_10_TAR_SHA512SUM="08f5a50cb48e0a58745a4825bbff49df68c4989c241eb1b0e281c69996355fcc84f8aa384069ef2323c07741240733c56a2abb8e85d25e122773ea465af5c57f"

BINUTILS_VER="2_38"
BUILDDIR=$(pwd)
CLEAN_BUILD=3
EXTENDED_PGO=0

LLVM_DIR="$BUILDDIR/llvm-project"
BINUTILS_DIR="$BUILDDIR/binutils-gdb"
KERNEL_DIR="$BUILDDIR/linux-$LINUX_VER"

KERNEL_4_9_DIR="$BUILDDIR/linux-$LINUX_4_9_VER"
KERNEL_4_14_DIR="$BUILDDIR/linux-$LINUX_4_14_VER"
KERNEL_4_19_DIR="$BUILDDIR/linux-$LINUX_4_19_VER"
KERNEL_5_4_DIR="$BUILDDIR/linux-$LINUX_5_4_VER"
KERNEL_5_10_DIR="$BUILDDIR/linux-$LINUX_5_10_VER"

LLVM_BUILD="$BUILDDIR/llvm-build"

PERSONAL=0
msg() {
	if [[ $PERSONAL -eq 1 ]]; then
		telegram-send "$1"
	else
		echo "==> $1"
	fi
}

msg "Starting LLVM Build"

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

get_linux_5_tarball() {
	if [ -e linux-$1.tar.xz ]; then
		msg "Existing linux-$1 tarball found, skipping download"
	else
		msg "Downloading linux-$1 tarball"
		wget "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$1.tar.xz"
	fi
}

get_linux_4_tarball() {
	if [ -e linux-$1.tar.xz ]; then
		msg "Existing linux-$1 tarball found, skipping download"
	else
		msg "Downloading linux-$1 tarball"
		wget "https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-$1.tar.xz"
	fi
}

verify_and_extract_linux_tarball() {
	msg "Checking file integrity of the tarball"
	msg "File: linux-$1.tar.xz"
	msg "Algorithm: sha512"
	if ! echo "$2 linux-$1.tar.xz" | sha512sum -c -; then
		msg "File integrity check: Failed" >&2
		exit 1
	fi

	msg "Extracting Linux tarball with tar"
	if ! pv "linux-$1.tar.xz" | tar -xJf-; then
		msg "File Extraction: Failed" >&2
		exit 1
	fi
}

extended_pgo_kramel_compile() {
	clear
	msg "Training Kernel Version=$1 Arch=$2"
	make distclean defconfig \
		LLVM=1 \
		ARCH=$2 \
		CC="$STAGE2"/clang \
		LD="$STAGE2"/ld.lld \
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
		LD="$STAGE2"/ld.lld \
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

get_linux_5_tarball $LINUX_VER

if [[ $EXTENDED_PGO -eq 1 ]]; then
	msg "Extended PGO profiling enabled!"
	msg "Downloading needed linux tar balls"
	get_linux_5_tarball $LINUX_5_10_VER
	get_linux_5_tarball $LINUX_5_4_VER
	get_linux_4_tarball $LINUX_4_19_VER
	get_linux_4_tarball $LINUX_4_14_VER
	get_linux_4_tarball $LINUX_4_9_VER
fi

verify_and_extract_linux_tarball $LINUX_VER $LINUX_TAR_SHA512SUM

if [[ $EXTENDED_PGO -eq 1 ]]; then
	msg "Extended PGO profiling enabled!"
	msg "extracting tar balls for extended PGO profiling"
	verify_and_extract_linux_tarball $LINUX_5_10_VER $LINUX_5_10_TAR_SHA512SUM
	verify_and_extract_linux_tarball $LINUX_5_4_VER $LINUX_5_4_TAR_SHA512SUM
	verify_and_extract_linux_tarball $LINUX_4_19_VER $LINUX_4_19_TAR_SHA512SUM
	verify_and_extract_linux_tarball $LINUX_4_14_VER $LINUX_4_14_TAR_SHA512SUM
	verify_and_extract_linux_tarball $LINUX_4_9_VER $LINUX_4_9_TAR_SHA512SUM
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
	if [[ $CLEAN_BUILD -gt 0 ]]; then
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
	-DLLVM_PARALLEL_COMPILE_JOBS=$(nproc --all) \
	-DLLVM_PARALLEL_LINK_JOBS=$(nproc --all) \
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
	if [[ $CLEAN_BUILD -gt 1 ]]; then
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
	-DLLVM_PARALLEL_COMPILE_JOBS=$(nproc --all) \
	-DLLVM_PARALLEL_LINK_JOBS=$(nproc --all) \
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

if [[ $EXTENDED_PGO -eq 1 ]]; then
	msg "Extended PGO profiling enabled!"
	msg "Starting Extended PGO training"
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

	# There are still some 32 bit qcom socs running 4.9 or lower
	# So yeah
	cd "$KERNEL_4_9_DIR"
	extended_pgo_kramel_compile "4.9" "arm" arm-linux-gnueabi-ld arm-linux-gnueabi-gnu-
fi

# Merge training
cd "$PROFILES"
"$STAGE2"/llvm-profdata merge -output=clang.profdata *

msg "Stage 2: PGO Training End"

# Stage 3 (built with PGO profile data)
msg "Stage 3 Build: Start"
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
	-DLLVM_PARALLEL_COMPILE_JOBS=$(nproc --all) \
	-DLLVM_PARALLEL_LINK_JOBS=$(nproc --all) \
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
mv $OUT/install $BUILDDIR/install/
msg "LLVM build finished. Final toolchain installed at:"
msg "$BUILDDIR/install"
