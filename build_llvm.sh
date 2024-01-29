#!/usr/bin/env bash
source utils.sh
# A custom Multi-Stage LLVM Toolchain builder.
# PGO optimized clang for building Linux Kernels.
set -e

# Specify some variables.

# 1. Linux kernel
LINUX_VER=$(curl -sL "https://www.kernel.org" | grep -A 1 "latest_link" | tail -n +2 | sed 's|.*">||' | sed 's|</a>||')
KERNEL_DIR="${BUILDDIR}/linux-${LINUX_VER}"

# 2. LLVM
LLVM_DIR="${BUILDDIR}/llvm-project"
LLVM_BUILD="${BUILDDIR}/llvm-build"
LLVM_PROJECT="${LLVM_DIR}/llvm"

LLVM_AVX_FLAGS="${NO_AVX_FLAGS}"

for arg in "$@"; do
    case "${arg}" in
        "--all-opts")
            POLLY_OPT=1
            BOLT_OPT=1
            LLVM_OPT=1
            AVX_OPT=1
            ;;
        "--incremental")
            CLEAN_BUILD=0
            ;;
        "--shallow-clone")
            SHALLOW_CLONE=1
            ;;
        "--polly-opt")
            POLLY_OPT=1
            ;;
        "--bolt-opt")
            BOLT_OPT=1
            ;;
        "--llvm-opt")
            LLVM_OPT=1
            ;;
        "--use-mold")
            USE_MOLD=1
            ;;
        "--use-jemalloc")
            USE_JEMALLOC=1
            ;;
        "--install-dir"*)
            FINAL_INSTALL_DIR="${arg#*--install-dir}"
            FINAL_INSTALL_DIR=${FINAL_INSTALL_DIR:1}
            ;;
        "--ci-run")
            CI=1
            LLVM_LD_JOBS="$(getconf _NPROCESSORS_ONLN)"
            ;;
        "--avx2")
            AVX_OPT=1
            ;;
        *)
            echo "Invalid argument passed: ${arg}"
            exit 1
            ;;
    esac
done

# Set AVX2 optimization flags
if [[ ${AVX_OPT} -eq 1 ]]; then
    LLVM_AVX_FLAGS="${AVX_FLAGS}"
fi

# Clear some variables if unused
clear_if_unused "POLLY_OPT" "POLLY_OPT_FLAGS"
clear_if_unused "LLVM_OPT" "LLVM_OPT_FLAGS"
clear_if_unused "BOLT_OPT" "BOLT_OPT_FLAGS"

# Send a notification if building on CI
if [[ ${CI} -eq 1 ]]; then
    tgsend "\
        <b>🔨 Neutron Clang Build Started</b>
		Build Date: <code>$(date +"%Y-%m-%d %H:%M")</code>"
fi

if [[ ${USE_JEMALLOC} -eq 1 ]]; then
    build_jemalloc() {
        cd "${BUILDDIR}"
        jemalloc_fetch_vars
        if [[ ${NO_JEMALLOC} -eq 1 ]]; then
            if [[ ${AVX_OPT} -eq 1 ]]; then
                bash "${BUILDDIR}/build_jemalloc.sh" --shallow-clone --avx2
            else
                bash "${BUILDDIR}/build_jemalloc.sh" --shallow-clone
            fi
        fi
    }
fi

# Function to BOLT clang and ld.lld
if [[ ${BOLT_OPT} -eq 1 ]]; then
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
            cd "${KERNEL_DIR}"
            perf record --output "${BOLT_PROFILES}"/perf.data --event cycles:u --branch-filter any,u -- make distclean defconfig all -sj"$(getconf _NPROCESSORS_ONLN)" \
                ARCH=arm64 KCFLAGS="-mllvm -regalloc-enable-advisor=release" KLDFLAGS="-mllvm -regalloc-enable-advisor=release" \
                "${KMAKEFLAGS[@]}" || (
                echo "Kernel Build failed!"
                exit 1
            )
            cd "${OUT}"

            echo "Training x86"
            cd "${KERNEL_DIR}"
            perf record --output "${BOLT_PROFILES}"/perf.data --event cycles:u --branch-filter any,u -- make distclean defconfig all -sj"$(getconf _NPROCESSORS_ONLN)" \
                "${KMAKEFLAGS[@]}" || (
                echo "Kernel Build failed!"
                exit 1
            )
            cd "${OUT}"

            "${STAGE1}"/perf2bolt "${STAGE3}/${CLANG_SUFFIX}" \
                -p "${BOLT_PROFILES}/perf.data" \
                -o "${BOLT_PROFILES}/${CLANG_SUFFIX}.fdata" || (
                echo "Failed to convert perf data"
                exit 1
            )

            "${STAGE1}"/llvm-bolt "${STAGE3}/${CLANG_SUFFIX}" \
                -o "${STAGE3}/${CLANG_SUFFIX}.bolt" \
                --data "${BOLT_PROFILES}/${CLANG_SUFFIX}.fdata" \
                "${BOLT_OPT_FLAGS[@]}" || (
                echo "Could not optimize clang with BOLT"
                exit 1
            )

            mv "${STAGE3}/${CLANG_SUFFIX}" "${STAGE3}/${CLANG_SUFFIX}.org"
            mv "${STAGE3}/${CLANG_SUFFIX}.bolt" "${STAGE3}/${CLANG_SUFFIX}"
        else
            "${STAGE1}"/llvm-bolt \
                --instrument \
                --instrumentation-file-append-pid \
                --instrumentation-file="${BOLT_PROFILES}/${CLANG_SUFFIX}.fdata" \
                "${STAGE3}/${CLANG_SUFFIX}" \
                -o "${STAGE3}/${CLANG_SUFFIX}.inst"

            mv "${STAGE3}/${CLANG_SUFFIX}" "${STAGE3}/${CLANG_SUFFIX}.org"
            mv "${STAGE3}/${CLANG_SUFFIX}.inst" "${STAGE3}/${CLANG_SUFFIX}"

            "${STAGE1}"/llvm-bolt \
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
            cd "${KERNEL_DIR}"
            make distclean defconfig all -sj"$(getconf _NPROCESSORS_ONLN)" \
                "${KMAKEFLAGS[@]}" \
                ARCH=arm64 \
                CROSS_COMPILE=aarch64-linux-gnu- || (
                echo "Kernel Build failed!"
                exit 1
            )
            cd "${OUT}"

            echo "Training x86"
            cd "${KERNEL_DIR}"
            make distclean defconfig all -sj"$(getconf _NPROCESSORS_ONLN)" \
                "${KMAKEFLAGS[@]}" || (
                echo "Kernel Build failed!"
                exit 1
            )
            cd "${OUT}"

            cd "${BOLT_PROFILES}"
            echo "Merging .fdata files..."
            "${STAGE1}"/merge-fdata -q ./*.fdata 2>merge-fdata.log 1>combined.fdata
            rm -rf "${STAGE3}/${CLANG_SUFFIX:?}"
            "${STAGE1}"/llvm-bolt "${STAGE3}/${CLANG_SUFFIX}.org" \
                --data "${BOLT_PROFILES}/combined.fdata" \
                -o "${STAGE3}/${CLANG_SUFFIX}" \
                "${BOLT_OPT_FLAGS[@]}" || (
                echo "Could not optimize clang with BOLT"
                exit 1
            )

            cd "${BOLT_PROFILES_LLD}"
            echo "Merging .fdata files..."
            "${STAGE1}"/merge-fdata -q ./*.fdata 2>merge-fdata.log 1>combined.fdata
            rm -rf "${STAGE3}/lld"
            "${STAGE1}"/llvm-bolt "${STAGE3}/lld.org" \
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

if [[ ${USE_JEMALLOC} -eq 1 ]]; then
    echo "Building jemalloc libs if not built already"
    build_jemalloc
fi

echo "Starting LLVM Build"
# Where all relevant build-related repositories are cloned.
if [[ -d ${LLVM_DIR} ]]; then
    echo "Existing llvm source found. Fetching new changes"
    cd "${LLVM_DIR}"
    if [[ ${SHALLOW_CLONE} -eq 1 ]]; then
        llvm_fetch "fetch" "--depth=1"
        git reset --hard FETCH_HEAD
        git clean -dfx
    else
        is_shallow=$(git rev-parse --is-shallow-repository 2>/dev/null)
        if [ "$is_shallow" = "true" ]; then
            llvm_fetch "fetch" "--depth=1"
            git reset --hard FETCH_HEAD
            git clean -dfx
        else
            llvm_fetch "pull"
        fi
    fi
    cd "${BUILDDIR}"
else
    echo "Cloning llvm project repo"
    if [[ ${SHALLOW_CLONE} -eq 1 ]]; then
        llvm_fetch "clone" "--depth=1"
    else
        llvm_fetch "clone"
    fi
fi

if [[ ${CLEAN_BUILD} -eq 1 ]]; then
    rm -rf "${LLVM_BUILD}"
fi
mkdir -p "${LLVM_BUILD}"

rm -rf "${KERNEL_DIR}" && get_linux_tarball "${LINUX_VER}"

rm -rf "${BUILDDIR}/mlgo-models/"

mkdir -p "${BUILDDIR}/mlgo-models/x86/regalloc"
cd "${BUILDDIR}/mlgo-models/x86/regalloc"
wget "https://github.com/google/ml-compiler-opt/releases/download/regalloc-evict-v1.0/regalloc-evict-e67430c-v1.0.tar.gz"
tar -xf "regalloc-evict-e67430c-v1.0.tar.gz"
rm -rf "regalloc-evict-e67430c-v1.0.tar.gz"

mkdir -p "${BUILDDIR}/mlgo-models/x86/inline"
cd "${BUILDDIR}/mlgo-models/x86/inline"
wget "https://github.com/google/ml-compiler-opt/releases/download/inlining-Oz-v1.1/inlining-Oz-99f0063-v1.1.tar.gz"
tar -xf "inlining-Oz-99f0063-v1.1.tar.gz"
rm -rf "inlining-Oz-99f0063-v1.1.tar.gz"

mkdir -p "${BUILDDIR}/mlgo-models/arm64/regalloc"
cd "${BUILDDIR}/mlgo-models/arm64/regalloc"
wget "https://github.com/dakkshesh07/mlgo-linux-kernel/releases/download/regalloc-evict-v6.6.8-arm64-1/regalloc-evict-linux-v6.6.8-arm64-1.tar.zst"
tar -xf "regalloc-evict-linux-v6.6.8-arm64-1.tar.zst"
rm -rf "regalloc-evict-linux-v6.6.8-arm64-1.tar.zst"

mkdir -p "${BUILDDIR}/mlgo-models/arm64/inline/model"
cd "${BUILDDIR}/mlgo-models/arm64/inline/model"
wget "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/mlgo-models/arm64/inlining-Oz-chromium.tar.gz"
tar -xf "inlining-Oz-chromium.tar.gz"
rm -rf "inlining-Oz-chromium.tar.gz"


echo "Patching LLVM"
# Patches
if [[ -d "${BUILDDIR}/patches/llvm" ]]; then
    cd "${LLVM_DIR}"
    for pfile in "${BUILDDIR}/patches/llvm"/*; do
        echo "Applying: ${pfile}"
        patch -Np1 <"${pfile}" || echo "Skipping: ${pfile}"
    done
fi

echo "Starting Stage 1 Build"
cd "${LLVM_BUILD}"
OUT="${LLVM_BUILD}/stage1"
if [[ -d ${OUT} ]]; then
    if [[ ${CLEAN_BUILD} -eq 1 ]]; then
        rm -rf "${OUT}"
        mkdir "${OUT}"
    fi
else
    mkdir "${OUT}"
fi
cd "${OUT}"

LLVM_BIN_DIR=$(readlink -f "$(which clang)" | rev | cut -d'/' -f2- | rev)

if [[ ${USE_MOLD} -eq 1 ]]; then
    LINKER="mold"
    LINKER_DIR=$(readlink -f "$(which mold)" | rev | cut -d'/' -f2- | rev)
else
    LINKER="ld.lld"
    LINKER_DIR="${LLVM_BIN_DIR}"
fi

OPT_FLAGS="-march=native -mtune=native ${BARE_AVX_FLAGS} ${COMMON_OPT_FLAGS[*]}"
OPT_FLAGS_LD="${COMMON_OPT_FLAGS_LD} -fuse-ld=${LINKER_DIR}/${LINKER}"

if [[ ${USE_JEMALLOC} -eq 1 ]]; then
    OPT_FLAGS_LD_EXE="${OPT_FLAGS_LD} ${JEMALLOC_FLAGS}"
else
    OPT_FLAGS_LD_EXE="${OPT_FLAGS_LD}"
fi

STAGE1_PROJS="clang;lld;compiler-rt"

if [[ ${BOLT_OPT} -eq 1 ]]; then
    STAGE1_PROJS="${STAGE1_PROJS};bolt"
fi

if [[ ${POLLY_OPT} -eq 1 ]]; then
    STAGE1_PROJS="${STAGE1_PROJS};polly;openmp"
fi

export TF_CPP_MIN_LOG_LEVEL=3
cmake -G Ninja -Wno-dev --log-level=NOTICE \
    -DLLVM_TARGETS_TO_BUILD="X86" \
    -DLLVM_ENABLE_PROJECTS="${STAGE1_PROJS}" \
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
    -DLLD_VENDOR="Neutron" \
    -DLLVM_ENABLE_BACKTRACES=OFF \
    -DLLVM_ENABLE_WARNINGS=OFF \
    -DLLVM_ENABLE_LTO=Thin \
    -DTENSORFLOW_AOT_PATH="$(python3 -c "import tensorflow; import os; print(os.path.dirname(tensorflow.__file__))")" \
    -DLLVM_RAEVICT_MODEL_PATH="${BUILDDIR}/mlgo-models/x86/regalloc/model" \
    -DLLVM_INLINER_MODEL_PATH="${BUILDDIR}/mlgo-models/x86/inline/model" \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DCMAKE_C_COMPILER="${LLVM_BIN_DIR}"/clang \
    -DCMAKE_CXX_COMPILER="${LLVM_BIN_DIR}"/clang++ \
    -DCMAKE_AR="${LLVM_BIN_DIR}"/llvm-ar \
    -DCMAKE_NM="${LLVM_BIN_DIR}"/llvm-nm \
    -DCMAKE_STRIP="${LLVM_BIN_DIR}"/llvm-strip \
    -DLLVM_USE_LINKER="${LINKER_DIR}/${LINKER}" \
    -DCMAKE_LINKER="${LINKER_DIR}/${LINKER}" \
    -DCMAKE_OBJCOPY="${LLVM_BIN_DIR}"/llvm-objcopy \
    -DCMAKE_OBJDUMP="${LLVM_BIN_DIR}"/llvm-objdump \
    -DCMAKE_RANLIB="${LLVM_BIN_DIR}"/llvm-ranlib \
    -DCMAKE_READELF="${LLVM_BIN_DIR}"/llvm-readelf \
    -DCMAKE_ADDR2LINE="${LLVM_BIN_DIR}"/llvm-addr2line \
    -DLLVM_PARALLEL_COMPILE_JOBS="$(getconf _NPROCESSORS_ONLN)" \
    -DLLVM_PARALLEL_LINK_JOBS="$LLVM_LD_JOBS" \
    -DCMAKE_C_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_ASM_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${OPT_FLAGS_LD_EXE}" \
    -DCMAKE_MODULE_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    "${LLVM_PROJECT}"

ninja -j"$(getconf _NPROCESSORS_ONLN)" || (
    echo "Could not build project!"
    exit 1
)

STAGE1="${LLVM_BUILD}/stage1/bin"
echo "Stage 1 Build: End"

# Stage 2 (to enable collecting profiling data)
echo "Stage 2: Build Start"
cd "${LLVM_BUILD}"
OUT="${LLVM_BUILD}/stage2-prof-gen"

if [[ -d ${OUT} ]]; then
    if [[ ${CLEAN_BUILD} -eq 1 ]]; then
        rm -rf "${OUT}"
        mkdir "${OUT}"
    fi
else
    mkdir "${OUT}"
fi
cd "${OUT}"
STOCK_PATH=${PATH}
MODDED_PATH="${STAGE1}:${PATH}"
export PATH="${MODDED_PATH}"
export LD_LIBRARY_PATH="${STAGE1}/../lib"

if [[ ${USE_MOLD} -eq 1 ]]; then
    LINKER="mold"
    LINKER_DIR=$(readlink -f "$(which mold)" | rev | cut -d'/' -f2- | rev)
else
    LINKER="ld.lld"
    LINKER_DIR="${STAGE1}"
fi

OPT_FLAGS="-march=x86-64 ${LLVM_AVX_FLAGS} ${COMMON_OPT_FLAGS[*]} -mllvm -regalloc-enable-advisor=release"
OPT_FLAGS_LD="${COMMON_OPT_FLAGS_LD} -Wl,-mllvm,-regalloc-enable-advisor=release -fuse-ld=${LINKER_DIR}/${LINKER}"

if [[ ${USE_JEMALLOC} -eq 1 ]]; then
    OPT_FLAGS_LD_EXE="${OPT_FLAGS_LD} ${JEMALLOC_FLAGS}"
else
    OPT_FLAGS_LD_EXE="${OPT_FLAGS_LD}"
fi

if [[ ${POLLY_OPT} -eq 1 ]]; then
    OPT_FLAGS="${OPT_FLAGS} ${POLLY_OPT_FLAGS[*]}"
fi

if [[ ${LLVM_OPT} -eq 1 ]]; then
    OPT_FLAGS="${OPT_FLAGS} ${LLVM_OPT_FLAGS[*]}"
fi

cmake -G Ninja -Wno-dev --log-level=ERROR \
    -DCLANG_VENDOR="Neutron" \
    -DLLD_VENDOR="Neutron" \
    -DLLVM_TARGETS_TO_BUILD='AArch64;ARM;X86' \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_WARNINGS=OFF \
    -DLLVM_ENABLE_PROJECTS='clang;lld' \
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
    -DTENSORFLOW_AOT_PATH="$(python3 -c "import tensorflow; import os; print(os.path.dirname(tensorflow.__file__))")" \
    -DLLVM_RAEVICT_MODEL_PATH="${BUILDDIR}/mlgo-models/arm64/regalloc/model" \
    -DLLVM_INLINER_MODEL_PATH="${BUILDDIR}/mlgo-models/arm64/inline/model" \
    -DCMAKE_C_COMPILER="${STAGE1}"/clang \
    -DCMAKE_CXX_COMPILER="${STAGE1}"/clang++ \
    -DCMAKE_AR="${STAGE1}"/llvm-ar \
    -DCMAKE_NM="${STAGE1}"/llvm-nm \
    -DCMAKE_STRIP="${STAGE1}"/llvm-strip \
    -DLLVM_USE_LINKER="${LINKER_DIR}/${LINKER}" \
    -DCMAKE_LINKER="${LINKER_DIR}/${LINKER}" \
    -DCMAKE_OBJCOPY="${STAGE1}"/llvm-objcopy \
    -DCMAKE_OBJDUMP="${STAGE1}"/llvm-objdump \
    -DCMAKE_RANLIB="${STAGE1}"/llvm-ranlib \
    -DCMAKE_READELF="${STAGE1}"/llvm-readelf \
    -DCMAKE_ADDR2LINE="${STAGE1}"/llvm-addr2line \
    -DCLANG_TABLEGEN="${STAGE1}"/clang-tblgen \
    -DLLVM_TABLEGEN="${STAGE1}"/llvm-tblgen \
    -DLLVM_BUILD_INSTRUMENTED=IR \
    -DLLVM_BUILD_RUNTIME=OFF \
    -DLLVM_LINK_LLVM_DYLIB=ON \
    -DLLVM_VP_COUNTERS_PER_SITE=6 \
    -DLLVM_PARALLEL_COMPILE_JOBS="$(getconf _NPROCESSORS_ONLN)" \
    -DLLVM_PARALLEL_LINK_JOBS="$LLVM_LD_JOBS" \
    -DCMAKE_C_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_ASM_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${OPT_FLAGS_LD_EXE}" \
    -DCMAKE_MODULE_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    -DCMAKE_INSTALL_PREFIX="${OUT}/install" \
    "${LLVM_PROJECT}"

echo "Installing to ${OUT}/install"
ninja install -j"$(getconf _NPROCESSORS_ONLN)" >/dev/null || (
    echo "Could not install project!"
    exit 1
)

STAGE2="${OUT}/install/bin"
PROFILES="${OUT}/profiles"
rm -rf "${PROFILES:?}/"*
echo "Stage 2: Build End"
echo "Stage 2: PGO Train Start"

export PATH="${STAGE2}:${STOCK_PATH}"
export LD_LIBRARY_PATH="${STAGE2}/../lib"

# Train PGO
cd "${KERNEL_DIR}"

# Patches

if [[ -d "${BUILDDIR}/patches/linux/common" ]]; then
    for pfile in "${BUILDDIR}/patches/linux/common"/*; do
        echo "Applying: ${pfile}"
        patch -Np1 <"${pfile}" || echo "Skipping: ${pfile}"
    done
fi

if [[ -d "${BUILDDIR}/patches/linux/${LINUX_VER}" ]]; then
    for pfile in "${BUILDDIR}/patches/linux/${LINUX_VER}"/*; do
        echo "Applying: ${pfile}"
        patch -Np1 <"${pfile}" || echo "Skipping: ${pfile}"
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
time make distclean defconfig all -sj"$(getconf _NPROCESSORS_ONLN)" "${KMAKEFLAGS[@]}" || exit ${?}

echo "Training arm64"
time make distclean defconfig all -sj"$(getconf _NPROCESSORS_ONLN)" ARCH=arm64  KCFLAGS="-mllvm -regalloc-enable-advisor=release" KLDFLAGS="-mllvm -regalloc-enable-advisor=release" \
    "${KMAKEFLAGS[@]}" || exit ${?}

unset LLD_IN_TEST

# Merge training
cd "${PROFILES}"
"${STAGE2}"/llvm-profdata merge -output=clang.profdata ./*

echo "Stage 2: PGO Training End"

# Stage 3 (built with PGO profile data)
echo "Stage 3 Build: Start"

export PATH="${MODDED_PATH}"
export LD_LIBRARY_PATH="${STAGE1}/../lib"

OPT_FLAGS="-march=x86-64 ${LLVM_AVX_FLAGS} ${COMMON_OPT_FLAGS[*]} -mllvm -regalloc-enable-advisor=release"
if [[ ${POLLY_OPT} -eq 1 ]]; then
    OPT_FLAGS="${OPT_FLAGS} ${POLLY_OPT_FLAGS[*]}"
fi

OPT_FLAGS_LD+="-Wl,-mllvm -enable-ext-tsp-block-placement -Wl,-mllvm,-enable-split-machine-functions"

if [[ ${LLVM_OPT} -eq 1 ]]; then
    OPT_FLAGS="${OPT_FLAGS} ${LLVM_OPT_FLAGS[*]} -mllvm -enable-chr"
fi

if [[ ${BOLT_OPT} -eq 1 ]]; then
    OPT_FLAGS_LD_EXE="${OPT_FLAGS_LD} -Wl,-znow -Wl,--emit-relocs"
else
    OPT_FLAGS_LD_EXE="${OPT_FLAGS_LD}"
fi

if [[ ${USE_JEMALLOC} -eq 1 ]]; then
    OPT_FLAGS_LD_EXE+=" ${JEMALLOC_FLAGS}"
fi

cd "${LLVM_BUILD}"
OUT="${LLVM_BUILD}/stage3"

if [[ -d ${OUT} ]]; then
    if [[ ${CLEAN_BUILD} -eq 1 ]]; then
        rm -rf "${OUT}"
        mkdir "${OUT}"
    fi
else
    mkdir "${OUT}"
fi
cd "${OUT}"
cmake -G Ninja -Wno-dev --log-level=ERROR \
    -DCLANG_VENDOR="Neutron" \
    -DLLD_VENDOR="Neutron" \
    -DLLVM_TARGETS_TO_BUILD='AArch64;ARM;X86' \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_WARNINGS=OFF \
    -DLLVM_ENABLE_PROJECTS='clang;lld;compiler-rt;polly;openmp' \
    -DCLANG_ENABLE_ARCMT=OFF \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
    -DCLANG_PLUGIN_SUPPORT=OFF \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_ENABLE_OCAMLDOC=OFF \
    -DLLVM_EXTERNAL_CLANG_TOOLS_EXTRA_SOURCE_DIR='' \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
    -DCOMPILER_RT_BUILD_CRT=ON \
    -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_LTO=Thin \
    -DTENSORFLOW_AOT_PATH="$(python3 -c "import tensorflow; import os; print(os.path.dirname(tensorflow.__file__))")" \
    -DLLVM_RAEVICT_MODEL_PATH="${BUILDDIR}/mlgo-models/arm64/regalloc/model" \
    -DLLVM_INLINER_MODEL_PATH="${BUILDDIR}/mlgo-models/arm64/inline/model" \
    -DCMAKE_C_COMPILER="${STAGE1}"/clang \
    -DCMAKE_CXX_COMPILER="${STAGE1}"/clang++ \
    -DCMAKE_AR="${STAGE1}"/llvm-ar \
    -DCMAKE_NM="${STAGE1}"/llvm-nm \
    -DCMAKE_STRIP="${STAGE1}"/llvm-strip \
    -DLLVM_USE_LINKER="${LINKER_DIR}/${LINKER}" \
    -DCMAKE_LINKER="${LINKER_DIR}/${LINKER}" \
    -DCMAKE_OBJCOPY="${STAGE1}"/llvm-objcopy \
    -DCMAKE_OBJDUMP="${STAGE1}"/llvm-objdump \
    -DCMAKE_RANLIB="${STAGE1}"/llvm-ranlib \
    -DCMAKE_READELF="${STAGE1}"/llvm-readelf \
    -DCMAKE_ADDR2LINE="${STAGE1}"/llvm-addr2line \
    -DCLANG_TABLEGEN="${STAGE1}"/clang-tblgen \
    -DLLVM_TABLEGEN="${STAGE1}"/llvm-tblgen \
    -DLLVM_PROFDATA_FILE="${PROFILES}"/clang.profdata \
    -DLLVM_PARALLEL_COMPILE_JOBS="$(getconf _NPROCESSORS_ONLN)" \
    -DLLVM_PARALLEL_LINK_JOBS="$LLVM_LD_JOBS" \
    -DCMAKE_C_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_ASM_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${OPT_FLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${OPT_FLAGS_LD_EXE}" \
    -DCMAKE_MODULE_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    -DCMAKE_SHARED_LINKER_FLAGS="${OPT_FLAGS_LD}" \
    -DCMAKE_INSTALL_PREFIX="${OUT}/install" \
    "${LLVM_PROJECT}"

echo "Installing to ${OUT}/install"
ninja install -j"$(getconf _NPROCESSORS_ONLN)" || (
    echo "Could not install project!"
    exit 1
)

STAGE3="${OUT}/install/bin"
echo "Stage 3 Build: End"

if [[ ${BOLT_OPT} -eq 1 ]]; then
    # Optimize final built clang with BOLT
    BOLT_PROFILES="${OUT}/bolt-prof"
    BOLT_PROFILES_LLD="${OUT}/bolt-prof-lld"
    rm -rf "${BOLT_PROFILES}" && rm -rf "${BOLT_PROFILES_LLD}"
    mkdir -p "${BOLT_PROFILES}" && mkdir -p "${BOLT_PROFILES_LLD}"
    export PATH="${STAGE3}:${STOCK_PATH}"
    export LD_LIBRARY_PATH="${STAGE3}/../lib"
    if [[ ${CI} -eq 1 ]]; then
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
fi

echo "Moving stage 3 install dir to build dir"
mv "${OUT}"/install "${BUILDDIR}"/"${FINAL_INSTALL_DIR}"/
echo "LLVM build finished. Final toolchain installed at:"
echo "${BUILDDIR}/${FINAL_INSTALL_DIR}"
