#!/usr/bin/env bash
source utils.sh
# Post Build script
set -e

# Remove unused products
echo "Removing unused products..."
rm -fr install/include
rm -f install/lib/*.a install/lib/*.la

# Strip remaining products
echo "Stripping remaining products..."
for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
    f="${f::-1}"
    echo "Stripping: ${f}"
    "${LLVM_BUILD}"/stage1/bin/llvm-strip --strip-debug "${f}"
done

# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
echo "Setting library load paths for portability..."
for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
    # Remove last character from file output (':')
    bin="${bin::-1}"
    echo "${bin}"
    patchelf --set-rpath '$ORIGIN/../lib' "${bin}"
done
