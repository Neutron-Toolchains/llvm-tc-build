#!/usr/bin/env bash
source utils.sh
# A custom Multi-Stage LLVM Toolchain builder.
# PGO optimized clang for building Linux Kernels.
set -e

# Specify some variables.
BUILDDIR=$(pwd)

# 1. Linux kernel
LINUX_VER=$(curl -sL "https://www.kernel.org" | grep -A 1 "latest_link" | tail -n +2 | sed 's|.*">||' | sed 's|</a>||')
KERNEL_DIR="$BUILDDIR/linux-$LINUX_VER"

# 2. LLVM
LLVM_DIR="$BUILDDIR/llvm-project"
LLVM_BUILD="$BUILDDIR/llvm-build"
LLVM_PROJECT="$LLVM_DIR/llvm"

# 3. GNU Binutils
BINUTILS_DIR="$BUILDDIR/binutils-gdb"
TEMP_BINTUILS_BUILD="$BUILDDIR/temp-binutils-build"
TEMP_BINTUILS_INSTALL="$BUILDDIR/temp-binutils"

# Do clean build (Range: 0-3)
# 0: Dirty build
# 1: Clean build
CLEAN_BUILD=1

# Optimize final toolchain with Polly
# 0: Disable
# 1: Enable
POLLY_OPT=1

#Optimize final toolchain with BOLT
# 0: Disable
# 1: Enable
BOLT_OPT=1

# Optimize final toolchain with LLVM's transformation passes
# 0: Disable
# 1: Enable
LLVM_OPT=0

# Use mold linker
# 0: Disable
# 1: Enable
USE_MOLD=0

# DO NOT CHANGE
USE_SYSTEM_BINUTILS_64=1
USE_SYSTEM_BINUTILS_32=1

# Clear some variables if unused
clear_if_unused "POLLY_OPT" "POLLY_OPT_FLAGS"
clear_if_unused "LLVM_OPT" "LLVM_OPT_FLAGS"
clear_if_unused "BOLT_OPT" "BOLT_OPT_FLAGS"

# Send a notification if building on CI
if [[ $CI -eq 1 ]]; then
    telegram-send --format html "\
		<b>🔨 Neutron Clang Build Started</b>
		Build Date: <code>$(date +"%Y-%m-%d %H:%M")</code>"
fi

# Function build temporary binutils for kernel profiling
build_temp_binutils() {

    rm -rf "$TEMP_BINTUILS_BUILD" && mkdir -p "$TEMP_BINTUILS_BUILD"
    if [[ $1 == "aarch64-linux-gnu" ]]; then
        USE_SYSTEM_BINUTILS_64=0
    else
        USE_SYSTEM_BINUTILS_32=0
    fi
    cd "$TEMP_BINTUILS_BUILD"
    "$BINUTILS_DIR"/configure \
        --target="$1" \
        --prefix="$TEMP_BINTUILS_INSTALL" \
        --disable-nls \
        --with-gnu-as \
        --with-gnu-ld \
        --disable-multilib \
        "${COMMON_BINUTILS_FLAGS[@]}"

    make -s -j"$(nproc --all)" >/dev/null
    make install -s -j"$(nproc --all)" >/dev/null
    echo "temp binutils build done, removing build dir"
    rm -rf "$TEMP_BINTUILS_BUILD"
}

# Function to BOLT clang and ld.lld
if [[ $BOLT_OPT -eq 1 ]]; then
    bolt_profile_gen() {

        CLANG_SUFFIX=$(basename "$(readlink -f "${STAGE3}"/clang)")

        KMAKEFLAGS=("LLVM=1"
            "LLVM_IAS=1"
            "CC=${STAGE3}/clang"
            "LD=${STAGE3}/ld.lld"
            "AR=${STAGE3}/llvm-ar"
            "NM=${STAGE3}/llvm-nm"
            "STRIP=${STAGE3}/llvm-strip"
            "OBJCOPY=${STAGE3}/llvm-objcopy"
            "OBJDUMP=${STAGE3}/llvm-objdump"
            "READELF=${STAGE3}/llvm-readelf"
            "HOSTCC=${STAGE3}/clang"
            "HOSTCXX=${STAGE3}/clang++"
            "HOSTAR=${STAGE3}/llvm-ar"
            "HOSTLD=${STAGE3}/ld.lld")

        if [[ $1 == "perf" ]]; then
            echo "Training arm64"
            cd "$KERNEL_DIR"
            perf record --output "${BOLT_PROFILES}"/perf.data --event cycles:u --branch-filter any,u -- make distclean defconfig all -sj"$(nproc --all)" \
                "${KMAKEFLAGS[@]}" \
                ARCH=arm64 \
                CROSS_COMPILE=aarch64-linux-gnu- || (
                echo "Kernel Build failed!"
                exit 1
            )
            cd "$OUT"

            echo "Training x86"
            cd "$KERNEL_DIR"
            perf record --output "${BOLT_PROFILES}"/perf.data --event cycles:u --branch-filter any,u -- make distclean defconfig all -sj"$(nproc --all)" \
                "${KMAKEFLAGS[@]}" || (
                echo "Kernel Build failed!"
                exit 1
            )
            cd "$OUT"

            "$STAGE1"/perf2bolt "${STAGE3}/${CLANG_SUFFIX}" \
                -p "${BOLT_PROFILES}/perf.data" \
                -o "${BOLT_PROFILES}/${CLANG_SUFFIX}.fdata" || (
                echo "Failed to convert perf data"
                exit 1
            )

            "$STAGE1"/llvm-bolt "${STAGE3}/${CLANG_SUFFIX}" \
                -o "${STAGE3}/${CLANG_SUFFIX}.bolt" \
                --data "${BOLT_PROFILES}/${CLANG_SUFFIX}.fdata" \
                "${BOLT_OPT_FLAGS[@]}" || (
                echo "Could not optimize clang with BOLT"
                exit 1
            )

            mv "${STAGE3}/${CLANG_SUFFIX}" "${STAGE3}/${CLANG_SUFFIX}.org"
            mv "${STAGE3}/${CLANG_SUFFIX}.bolt" "${STAGE3}/${CLANG_SUFFIX}"
        else
            "$STAGE1"/llvm-bolt \
                --instrument \
                --instrumentation-file-append-pid \
                --instrumentation-file="${BOLT_PROFILES}/${CLANG_SUFFIX}.fdata" \
                "${STAGE3}/${CLANG_SUFFIX}" \
                -o "${STAGE3}/${CLANG_SUFFIX}.inst"

            mv "${STAGE3}/${CLANG_SUFFIX}" "${STAGE3}/${CLANG_SUFFIX}.org"
            mv "${STAGE3}/${CLANG_SUFFIX}.inst" "${STAGE3}/${CLANG_SUFFIX}"

            "$STAGE1"/llvm-bolt \
                --instrument \
                --instrumentation-file-append-pid \
                --instrumentation-file="${BOLT_PROFILES_LLD}/lld.fdata" \
                "${STAGE3}/lld" \
                -o "${STAGE3}/lld.inst"

            mv "${STAGE3}/lld" "${STAGE3}/lld.org"
            mv "${STAGE3}/lld.inst" "${STAGE3}/lld"

            # As a speedup, lld invokes _Exit, which stops it from writing the BOLT profiles.
            export LLD_IN_TEST=1

            echo "Training arm64"
            cd "$KERNEL_DIR"
            make distclean defconfig all -sj"$(nproc --all)" \
                "${KMAKEFLAGS[@]}" \
                ARCH=arm64 \
                CROSS_COMPILE=aarch64-linux-gnu- || (
                echo "Kernel Build failed!"
                exit 1
            )
            cd "$OUT"

            echo "Training x86"
            cd "$KERNEL_DIR"
            make distclean defconfig all -sj"$(nproc --all)" \
                "${KMAKEFLAGS[@]}" || (
                echo "Kernel Build failed!"
                exit 1
            )
            cd "$OUT"

            cd "$BOLT_PROFILES"
            "$STAGE1"/merge-fdata -q ./*.fdata >combined.fdata
            rm -rf "${STAGE3}/${CLANG_SUFFIX:?}"
            "$STAGE1"/llvm-bolt "${STAGE3}/${CLANG_SUFFIX}.org" \
                --data "${BOLT_PROFILES}/combined.fdata" \
                -o "${STAGE3}/${CLANG_SUFFIX}" \
                "${BOLT_OPT_FLAGS[@]}" || (
                echo "Could not optimize clang with BOLT"
                exit 1
            )

            cd "$BOLT_PROFILES_LLD"
            "$STAGE1"/merge-fdata -q ./*.fdata >combined.fdata
            rm -rf "${STAGE3}/lld"
            "$STAGE1"/llvm-bolt "${STAGE3}/lld.org" \
                --data "${BOLT_PROFILES_LLD}/combined.fdata" \
                -o "${STAGE3}/lld" \
                "${BOLT_OPT_FLAGS[@]}" || (
                echo "Could not optimize lld with BOLT"
                exit 1
            )
            unset LLD_IN_TEST
        fi
    }
fi

echo "Starting LLVM Build"
# Where all relevant build-related repositories are cloned.
if [[ -d $LLVM_DIR ]]; then
    cd "$LLVM_DIR"/
    if ! git status; then
        echo "llvm-project dir found but not a git repo, recloning"
        cd "$BUILDDIR"
        llvm_clone
    else
        echo "Existing llvm repo found, skipping clone"
        echo "Fetching new changes"
        llvm_pull
        cd "$BUILDDIR"
    fi
else
    echo "cloning llvm project repo"
    llvm_clone
fi

if [[ -d $BINUTILS_DIR ]]; then
    cd "$BINUTILS_DIR"/
    if ! git status; then
        echo "GNU binutils dir found but not a git repo, recloning"
        cd "$BUILDDIR"
        binutils_clone
    else
        echo "Existing binutils repo found, skipping clone"
        echo "Fetching new changes"
        binutils_pull
        cd "$BUILDDIR"
    fi
else
    echo "cloning GNU binutils repo"
    binutils_clone
fi

if [[ $CLEAN_BUILD -eq 1 ]]; then
    rm -rf "$LLVM_BUILD"
fi
mkdir -p "$LLVM_BUILD"

rm -rf "$KERNEL_DIR" && get_linux_tarball "$LINUX_VER"

echo "Starting Stage 1 Build"
cd "$LLVM_BUILD"
OUT="$LLVM_BUILD/stage1"
if [[ -d $OUT ]]; then
    if [[ $CLEAN_BUILD -eq 1 ]]; then
        rm -rf "$OUT"
        mkdir "$OUT"
    fi
else
    mkdir "$OUT"
fi
cd "$OUT"

LLVM_BIN_DIR=$(readlink -f "$(which clang)" | rev | cut -d'/' -f2- | rev)

if [[ $USE_MOLD -eq 1 ]]; then
    LINKER="mold"
    LINKER_DIR=$(readlink -f "$(which mold)" | rev | cut -d'/' -f2- | rev)
else
    LINKER="ld.lld"
    LINKER_DIR="$LLVM_BIN_DIR"
fi

OPT_FLAGS="-O3 -march=native -mtune=native -ffunction-sections -fdata-sections"
OPT_FLAGS_LD="-Wl,-O3,--sort-common,--as-needed,-z,now -fuse-ld=$LINKER_DIR/$LINKER"

STAGE1_PROJS="clang;lld"
STAGE1_RTS="compiler-rt"

if [[ $BOLT_OPT -eq 1 ]]; then
    STAGE1_PROJS="$STAGE1_PROJS;bolt"
fi

if [[ $POLLY_OPT -eq 1 ]]; then
    STAGE1_PROJS="$STAGE1_PROJS;polly"
    STAGE1_RTS="$STAGE1_RTS;openmp"
fi

cmake -G Ninja -Wno-dev --log-level=NOTICE \
    -DLLVM_TARGETS_TO_BUILD="X86" \
    -DLLVM_ENABLE_PROJECTS="$STAGE1_PROJS" \
    -DLLVM_ENABLE_RUNTIMES="$STAGE1_RTS" \
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
    -DLLVM_CCACHE_BUILD=ON \
    -DCMAKE_C_COMPILER="$LLVM_BIN_DIR"/clang \
    -DCMAKE_CXX_COMPILER="$LLVM_BIN_DIR"/clang++ \
    -DCMAKE_AR="$LLVM_BIN_DIR"/llvm-ar \
    -DCMAKE_NM="$LLVM_BIN_DIR"/llvm-nm \
    -DCMAKE_STRIP="$LLVM_BIN_DIR"/llvm-strip \
    -DLLVM_USE_LINKER="$LINKER_DIR/$LINKER" \
    -DCMAKE_LINKER="$LINKER_DIR/$LINKER" \
    -DCMAKE_OBJCOPY="$LLVM_BIN_DIR"/llvm-objcopy \
    -DCMAKE_OBJDUMP="$LLVM_BIN_DIR"/llvm-objdump \
    -DCMAKE_RANLIB="$LLVM_BIN_DIR"/llvm-ranlib \
    -DCMAKE_READELF="$LLVM_BIN_DIR"/llvm-readelf \
    -DCMAKE_ADDR2LINE="$LLVM_BIN_DIR"/llvm-addr2line \
    -DLLVM_PARALLEL_COMPILE_JOBS="$(nproc --all)" \
    -DLLVM_PARALLEL_LINK_JOBS="$(nproc --all)" \
    -DCMAKE_C_FLAGS="$OPT_FLAGS" \
    -DCMAKE_ASM_FLAGS="$OPT_FLAGS" \
    -DCMAKE_CXX_FLAGS="$OPT_FLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$OPT_FLAGS_LD" \
    -DCMAKE_MODULE_LINKER_FLAGS="$OPT_FLAGS_LD" \
    -DCMAKE_SHARED_LINKER_FLAGS="$OPT_FLAGS_LD" \
    "$LLVM_PROJECT"

ninja -j"$(nproc --all)" >/dev/null || (
    echo "Could not build project!"
    exit 1
)

STAGE1="$LLVM_BUILD/stage1/bin"
echo "Stage 1 Build: End"

# Stage 2 (to enable collecting profiling data)
echo "Stage 2: Build Start"
cd "$LLVM_BUILD"
OUT="$LLVM_BUILD/stage2-prof-gen"

if [[ -d $OUT ]]; then
    if [[ $CLEAN_BUILD -eq 1 ]]; then
        rm -rf "$OUT"
        mkdir "$OUT"
    fi
else
    mkdir "$OUT"
fi
cd "$OUT"
STOCK_PATH=$PATH
MODDED_PATH="$STAGE1:$PATH"
export PATH="$MODDED_PATH"
export LD_LIBRARY_PATH="$STAGE1/../lib"

if [[ $USE_MOLD -eq 1 ]]; then
    LINKER="mold"
    LINKER_DIR=$(readlink -f "$(which mold)" | rev | cut -d'/' -f2- | rev)
else
    LINKER="ld.lld"
    LINKER_DIR="$STAGE1"
fi

OPT_FLAGS="-march=x86-64 -mtune=generic -ffunction-sections -fdata-sections -flto=thin -fsplit-lto-unit -O3"
OPT_FLAGS_LD="-Wl,-O3,--sort-common,--as-needed,-z,now,--lto-O3 -fuse-ld=$LINKER_DIR/$LINKER"

if [[ $POLLY_OPT -eq 1 ]]; then
    OPT_FLAGS="$OPT_FLAGS ${POLLY_OPT_FLAGS[*]}"
fi

if [[ $LLVM_OPT -eq 1 ]]; then
    OPT_FLAGS="$OPT_FLAGS ${LLVM_OPT_FLAGS[*]}"
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
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_LTO=Thin \
    -DCMAKE_C_COMPILER="$STAGE1"/clang \
    -DCMAKE_CXX_COMPILER="$STAGE1"/clang++ \
    -DCMAKE_AR="$STAGE1"/llvm-ar \
    -DCMAKE_NM="$STAGE1"/llvm-nm \
    -DCMAKE_STRIP="$STAGE1"/llvm-strip \
    -DLLVM_USE_LINKER="$LINKER_DIR/$LINKER" \
    -DCMAKE_LINKER="$LINKER_DIR/$LINKER" \
    -DCMAKE_OBJCOPY="$STAGE1"/llvm-objcopy \
    -DCMAKE_OBJDUMP="$STAGE1"/llvm-objdump \
    -DCMAKE_RANLIB="$STAGE1"/llvm-ranlib \
    -DCMAKE_READELF="$STAGE1"/llvm-readelf \
    -DCMAKE_ADDR2LINE="$STAGE1"/llvm-addr2line \
    -DCLANG_TABLEGEN="$STAGE1"/clang-tblgen \
    -DLLVM_TABLEGEN="$STAGE1"/llvm-tblgen \
    -DLLVM_BUILD_INSTRUMENTED=IR \
    -DLLVM_BUILD_RUNTIME=OFF \
    -DLLVM_LINK_LLVM_DYLIB=ON \
    -DLLVM_VP_COUNTERS_PER_SITE=6 \
    -DLLVM_PARALLEL_COMPILE_JOBS="$(nproc --all)" \
    -DLLVM_PARALLEL_LINK_JOBS="$(nproc --all)" \
    -DCMAKE_C_FLAGS="$OPT_FLAGS" \
    -DCMAKE_ASM_FLAGS="$OPT_FLAGS" \
    -DCMAKE_CXX_FLAGS="$OPT_FLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$OPT_FLAGS_LD" \
    -DCMAKE_MODULE_LINKER_FLAGS="$OPT_FLAGS_LD" \
    -DCMAKE_SHARED_LINKER_FLAGS="$OPT_FLAGS_LD" \
    -DCMAKE_INSTALL_PREFIX="$OUT/install" \
    "$LLVM_PROJECT"

echo "Installing to $OUT/install"
ninja install -j"$(nproc --all)" >/dev/null || (
    echo "Could not install project!"
    exit 1
)

STAGE2="$OUT/install/bin"
PROFILES="$OUT/profiles"
rm -rf "${PROFILES:?}/"*
echo "Stage 2: Build End"
echo "Stage 2: PGO Train Start"

rm -rf "$TEMP_BINTUILS_INSTALL" && mkdir -p "$TEMP_BINTUILS_INSTALL"
command -v aarch64-linux-gnu-as &>/dev/null || build_temp_binutils aarch64-linux-gnu
command -v arm-linux-gnueabi-as &>/dev/null || build_temp_binutils arm-linux-gnueabi

if [[ $USE_SYSTEM_BINUTILS_64 -eq 1 ]]; then
    BINTUILS_64_BIN_DIR=$(readlink -f "$(which aarch64-linux-gnu-as)" | rev | cut -d'/' -f2- | rev)
else
    BINTUILS_64_BIN_DIR="$TEMP_BINTUILS_INSTALL/bin"
fi

if [[ $USE_SYSTEM_BINUTILS_32 -eq 1 ]]; then
    BINTUILS_32_BIN_DIR=$(readlink -f "$(which arm-linux-gnueabi-as)" | rev | cut -d'/' -f2- | rev)
else
    BINTUILS_32_BIN_DIR="$TEMP_BINTUILS_INSTALL/bin"
fi

if [[ $USE_SYSTEM_BINUTILS_64 -eq 1 ]] && [[ $USE_SYSTEM_BINUTILS_64 -eq 1 ]]; then
    rm -rf "$TEMP_BINTUILS_INSTALL"
    rm -rf "$TEMP_BINTUILS_BUILD"
fi

export PATH="$STAGE2:$BINTUILS_64_BIN_DIR:$BINTUILS_32_BIN_DIR:$STOCK_PATH"
export LD_LIBRARY_PATH="$STAGE2/../lib"

# Train PGO
cd "$KERNEL_DIR"

# Patches
if [[ -d "$BUILDDIR/patches/linux/$LINUX_VER" ]]; then
    for pfile in "$BUILDDIR/patches/linux/$LINUX_VER"/*; do
        echo "Applying: $pfile"
        patch -Np1 <"$pfile" || echo "Skipping: $pfile"
    done
fi

# Force profiling using O3
sed -i 's|-Os|-O3|g' Makefile
sed -i 's|-O2|-O3|g' Makefile

# As a speedup, lld invokes _Exit, which stops it from writing the PGO profiles.
export LLD_IN_TEST=1

KMAKEFLAGS=("LLVM=1"
    "LLVM_IAS=1"
    "CC=${STAGE2}/clang"
    "LD=${STAGE2}/ld.lld"
    "AR=${STAGE2}/llvm-ar"
    "NM=${STAGE2}/llvm-nm"
    "STRIP=${STAGE2}/llvm-strip"
    "OBJCOPY=${STAGE2}/llvm-objcopy"
    "OBJDUMP=${STAGE2}/llvm-objdump"
    "READELF=${STAGE2}/llvm-readelf"
    "HOSTCC=${STAGE2}/clang"
    "HOSTCXX=${STAGE2}/clang++"
    "HOSTAR=${STAGE2}/llvm-ar"
    "HOSTLD=${STAGE2}/ld.lld")

echo "Training x86"
time make distclean defconfig all -sj"$(nproc --all)" "${KMAKEFLAGS[@]}" || exit ${?}

echo "Training arm64"
time make distclean defconfig all -sj"$(nproc --all)" ARCH=arm64 "${KMAKEFLAGS[@]}" \
    CROSS_COMPILE=aarch64-linux-gnu- || exit ${?}

unset LLD_IN_TEST

# Merge training
cd "$PROFILES"
"$STAGE2"/llvm-profdata merge -output=clang.profdata ./*

if [[ $BOLT_OPT -eq 0 ]]; then
    rm -rf "$TEMP_BINTUILS_INSTALL"
fi
echo "Stage 2: PGO Training End"

# Stage 3 (built with PGO profile data)
echo "Stage 3 Build: Start"

export PATH="$MODDED_PATH"
export LD_LIBRARY_PATH="$STAGE1/../lib"

OPT_FLAGS="-O3 -march=x86-64 -mtune=generic -ffunction-sections -fdata-sections -flto=full -falign-functions=32"
if [[ $POLLY_OPT -eq 1 ]]; then
    OPT_FLAGS="$OPT_FLAGS ${POLLY_OPT_FLAGS[*]}"
fi

if [[ $LLVM_OPT -eq 1 ]]; then
    OPT_FLAGS="$OPT_FLAGS ${LLVM_OPT_FLAGS[*]} -mllvm -enable-chr"
fi

if [[ $BOLT_OPT -eq 1 ]]; then
    OPT_FLAGS_LD_EXE="$OPT_FLAGS_LD -Wl,-znow -Wl,--emit-relocs"
else
    OPT_FLAGS_LD_EXE="$OPT_FLAGS_LD"
fi

cd "$LLVM_BUILD"
OUT="$LLVM_BUILD/stage3"

if [[ -d $OUT ]]; then
    if [[ $CLEAN_BUILD -eq 1 ]]; then
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
    -DLLVM_ENABLE_WARNINGS=OFF \
    -DLLVM_ENABLE_PROJECTS='clang;lld;polly' \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt;openmp" \
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
    -DLLVM_ENABLE_LTO=Full \
    -DCMAKE_C_COMPILER="$STAGE1"/clang \
    -DCMAKE_CXX_COMPILER="$STAGE1"/clang++ \
    -DCMAKE_AR="$STAGE1"/llvm-ar \
    -DCMAKE_NM="$STAGE1"/llvm-nm \
    -DCMAKE_STRIP="$STAGE1"/llvm-strip \
    -DLLVM_USE_LINKER="$LINKER_DIR/$LINKER" \
    -DCMAKE_LINKER="$LINKER_DIR/$LINKER" \
    -DCMAKE_OBJCOPY="$STAGE1"/llvm-objcopy \
    -DCMAKE_OBJDUMP="$STAGE1"/llvm-objdump \
    -DCMAKE_RANLIB="$STAGE1"/llvm-ranlib \
    -DCMAKE_READELF="$STAGE1"/llvm-readelf \
    -DCMAKE_ADDR2LINE="$STAGE1"/llvm-addr2line \
    -DCLANG_TABLEGEN="$STAGE1"/clang-tblgen \
    -DLLVM_TABLEGEN="$STAGE1"/llvm-tblgen \
    -DLLVM_PROFDATA_FILE="$PROFILES"/clang.profdata \
    -DLLVM_PARALLEL_COMPILE_JOBS="$(nproc --all)" \
    -DLLVM_PARALLEL_LINK_JOBS="$(nproc --all)" \
    -DCMAKE_C_FLAGS="$OPT_FLAGS" \
    -DCMAKE_ASM_FLAGS="$OPT_FLAGS" \
    -DCMAKE_CXX_FLAGS="$OPT_FLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$OPT_FLAGS_LD_EXE" \
    -DCMAKE_MODULE_LINKER_FLAGS="$OPT_FLAGS_LD" \
    -DCMAKE_SHARED_LINKER_FLAGS="$OPT_FLAGS_LD" \
    -DCMAKE_INSTALL_PREFIX="$OUT/install" \
    "$LLVM_PROJECT"

echo "Installing to $OUT/install"
ninja install -j"$(nproc --all)" || (
    echo "Could not install project!"
    exit 1
)

STAGE3="$OUT/install/bin"
echo "Stage 3 Build: End"

if [[ $BOLT_OPT -eq 1 ]]; then
    # Optimize final built clang with BOLT
    BOLT_PROFILES="$OUT/bolt-prof"
    BOLT_PROFILES_LLD="$OUT/bolt-prof-lld"
    rm -rf "$BOLT_PROFILES" && rm -rf "$BOLT_PROFILES_LLD"
    mkdir -p "$BOLT_PROFILES" && mkdir -p "$BOLT_PROFILES_LLD"
    export PATH="$STAGE3:$BINTUILS_64_BIN_DIR:$BINTUILS_32_BIN_DIR:$STOCK_PATH"
    export LD_LIBRARY_PATH="$STAGE3/../lib"
    if [[ $CI -eq 1 ]]; then
        echo "Performing BOLT with instrumenting!"
        bolt_profile_gen "instrumenting" || (
            echo "Optimizing with BOLT failed!"
            exit 1
        )
    else
        if ! perf record -e cycles:u -j any,u -- sleep 1 &>/dev/null; then
            echo "Performing BOLT with instrumenting!"
            bolt_profile_gen "instrumenting" || (
                echo "Optimizing with BOLT failed!"
                exit 1
            )
        else
            echo "Performing BOLT with sampling!"
            bolt_profile_gen "perf" || (
                echo "Optimizing with BOLT failed!"
                exit 1
            )
        fi
    fi
    rm -rf "$TEMP_BINTUILS_INSTALL"
fi

echo "Moving stage 3 install dir to build dir"
mv "$OUT"/install "$BUILDDIR"/install/
echo "LLVM build finished. Final toolchain installed at:"
echo "$BUILDDIR/install"
