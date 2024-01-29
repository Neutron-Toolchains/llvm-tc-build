#!/usr/bin/env bash
source utils.sh
# Script to push final built clang to my repo
set -e

# Specify some variables.
CURRENT_DIR=$(pwd)
LLVM_DIR="${CURRENT_DIR}/llvm-project"
NEUTRON_DIR="${CURRENT_DIR}/clang-build-catalogue"
INSTALL_DIR="${CURRENT_DIR}/install"

rel_tag="$(date "+%d%m%Y")"     # "{date}{month}{year}" format
rel_date="$(date "+%-d %B %Y")" # "Day Month Year" format
rel_file="${CURRENT_DIR}/neutron-clang-${rel_tag}.tar.zst"

neutron_fetch() {

    if ! git "${1}" https://github.com/Neutron-Toolchains/clang-build-catalogue.git; then
        exit 1
    fi
}

#LLVM Info
cd "${LLVM_DIR}"
llvm_commit="$(git rev-parse HEAD)"
llvm_commit_url="https://github.com/llvm/llvm-project/commit/${llvm_commit}"

# Clang Info
cd "${CURRENT_DIR}"
clang_version="$(install/bin/clang --version | head -n1 | cut -d' ' -f4)"
h_glibc="$(ldd --version | head -n1 | grep -oE '[^ ]+$')"

# Builder Info
cd "${CURRENT_DIR}"
builder_commit="$(git rev-parse HEAD)"

if [[ -d "${NEUTRON_DIR}"/ ]]; then
    cd "${NEUTRON_DIR}"/
    if ! git status; then
        cd "${CURRENT_DIR}"
        neutron_fetch "clone"
    else
        neutron_fetch "pull"
        cd "${CURRENT_DIR}"
    fi
else
    neutron_fetch "clone"
fi

cd "${INSTALL_DIR}"
tar -I "zstd -T$(nproc --all) -19" -cf "${rel_file}" .
rel_shasum=$(sha256sum "${rel_file}" | awk '{print $1}')
rel_size=$(du -sh "${rel_file}" | awk '{print $1}')

cd "${NEUTRON_DIR}"
rm -rf latest.txt
touch latest.txt
echo -e "[tag]\n${rel_tag}" >>latest.txt

touch "${rel_tag}-info.txt"
{
    echo -e "[date]\n${rel_date}\n"
    echo -e "[clang-ver]\n${clang_version}\n"
    echo -e "[llvm-commit]\n${llvm_commit_url}\n"
    echo -e "[host-glibc]\n${h_glibc}\n"
    echo -e "[size]\n${rel_size}\n"
    echo -e "[shasum]\n${rel_shasum}"
} >>"${rel_tag}-info.txt"

git add -A
git commit -asm "catalogue: Add Neutron Clang build ${rel_tag}

Clang Version: ${clang_version}
LLVM commit: ${llvm_commit_url}
Builder commit: https://github.com/Neutron-Toolchains/llvm-tc-build/commit/${builder_commit}
Release: https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/tag/${rel_tag}"
git gc
git push "https://dakkshesh07:${GHUB_TOKEN}@github.com/Neutron-Toolchains/clang-build-catalogue.git" main -f

if gh release view "${rel_tag}"; then
    echo "Uploading build archive to '${rel_tag}'..."
    gh release upload --clobber "${rel_tag}" "${rel_file}" && {
        echo "Version ${rel_tag} updated!"
    }
else
    echo "Creating release with tag '${rel_tag}'..."
    gh release create "${rel_tag}" "${rel_file}" -t "${rel_date}" -n "" && {
        echo "Version ${rel_tag} released!"
    }
fi

git push "https://dakkshesh07:${GHUB_TOKEN}@github.com/Neutron-Toolchains/clang-build-catalogue.git" main -f
echo "push complete"

end_msg="
<b>Ayo! New Neutron Clang Update!</b>

<b>Toolchain details</b>
Clang version: <code>${clang_version}</code>
LLVM commit: <a href='${llvm_commit_url}'> Here </a>
Builder commit: <a href='https://github.com/Neutron-Toolchains/clang-build/commit/${builder_commit}'> Here </a>
Build Date: <code>$(date +"%Y-%m-%d %H:%M")</code>
Build Tag: <code>${rel_tag}</code>

<b>Host system details</b>
Distro: <a href='https://github.com/Neutron-Toolchains/docker-image'> ArchLinux(docker) </a>
Clang version: <code>$(clang --version | head -n1 | grep -oE '[^ ]+$')</code>
Glibc version: <code>$(ldd --version | head -n1 | grep -oE '[^ ]+$')</code>

<b>Build Release:</b><a href='https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/tag/${rel_tag}'> github.com </a>
"

tgsend "${end_msg}"
