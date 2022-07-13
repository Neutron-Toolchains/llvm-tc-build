#!/bin/bash
# A custom Multi-Stage LLVM Toolchain builder.
# PGO optimized clang for building Linux Kernels.
#!/bin/bash
set -e

BINUTILS_VER="2_38"
BUILDDIR=$(pwd)
CLEAN_BUILD=3
POLLY_OPT=1

if [[ $POLLY_OPT -eq 1 ]]; then
	POLLY_OPT_FLAGS="-mllvm -polly -mllvm -polly-run-dce -mllvm -polly-run-inliner -mllvm -polly-ast-use-context -mllvm -polly-detect-keep-going -mllvm -polly-vectorizer=stripmine -mllvm -polly-invariant-load-hoisting -mllvm -polly-loopfusion-greedy=1 -mllvm -polly-reschedule=1 -mllvm -polly-postopts=1 -mllvm -polly-num-threads=0 -mllvm -polly-omp-backend=LLVM -mllvm -polly-scheduling=dynamic -mllvm -polly-scheduling-chunksize=1"
fi

LLVM_DIR="$BUILDDIR/llvm-project"
BINUTILS_DIR="$BUILDDIR/binutils-gdb"

LLVM_BUILD="$BUILDDIR/llvm-build"

if [[ $CI -eq 1 ]]; then
	telegram-send --format html "\
		<b>🔨 Neutron Clang Build Started</b>
		Build Date: <code>$(date +"%Y-%m-%d %H:%M")</code>"
fi

echo "Starting LLVM Build"

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

export PATH="$STAGE1/bin:$STAGE1:$PATH"
if [[ $POLLY_OPT -eq 1 ]]; then
	OPT_FLAGS="$OPT_FLAGS $POLLY_OPT_FLAGS"
fi

OPT_FLAGS_LD="-Wl,-O3 -Wl,--lto-O3 -fuse-ld=$STAGE1/ld.lld"

# Stage 2 (built using newly compiled LLVM binaries with Polly optimization)
echo "Stage 2 Build: Start"

cd "$LLVM_BUILD"
OUT="$LLVM_BUILD/stage2"

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
echo "Stage 2 Build: End"

echo "Moving stage 2 install dir to build dir"
mv $OUT/install $BUILDDIR/install/
echo "LLVM build finished. Final toolchain installed at:"
echo "$BUILDDIR/install"
