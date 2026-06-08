#!/usr/bin/env bash
#
# Copyright (C) 2026 Dakkshesh <beakthoven@gmail.com>. All rights reserved.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

set -euo pipefail

source "$(pwd)/scriptlets/_llvm.sh"
parse_llvm_args "$@"

echo "=> Verifying dependencies"
check_if_exists "${LLVM_INSTALL_DIR}"

# Directories
NEUTRON_DIR="${SRC_DIR}/clang-build-catalogue"

# Release metadata
rel_tag="$(date '+%d%m%Y')"
rel_date="$(date '+%-d %B %Y')"
rel_file="${WORK_DIR}/neutron-clang-${rel_tag}.tar.zst"

CATALOGUE_REPO="https://github.com/Neutron-Toolchains/clang-build-catalogue.git"

neutron_fetch() {
    case "${1}" in
        clone)
            git clone "${CATALOGUE_REPO}" "${NEUTRON_DIR}"
            ;;
        pull)
            (
                cd "${NEUTRON_DIR}"
                git pull --rebase origin main
            )
            ;;
        *)
            die "Unknown neutron_fetch action: ${1}"
            ;;
    esac
}

cd "${LLVM_SRC_DIR}"
llvm_commit="$(git rev-parse HEAD)"
llvm_commit_url="https://github.com/llvm/llvm-project/commit/${llvm_commit}"

cd "${WORK_DIR}"

builder_commit="$(git rev-parse HEAD)"
builder_commit_url="https://github.com/Neutron-Toolchains/llvm-tc-build/commit/${builder_commit}"

h_glibc="$(ldd --version | awk 'NR==1{print $NF}')"
clang_version="$("${LLVM_INSTALL_DIR}/bin/clang" --version | grep -oP '(?<=clang version )\S+')"

if [[ -d "${NEUTRON_DIR}/.git" ]]; then
    echo "=> Updating catalogue repository"
    neutron_fetch pull
else
    echo "=> Cloning catalogue repository"
    rm -rf "${NEUTRON_DIR}"
    neutron_fetch clone
fi

echo "=> Creating release archive"

cd "${LLVM_INSTALL_DIR}"

tar -I "zstd -T$(nproc --all) -19" -cf "${rel_file}" .

rel_shasum="$(sha256sum "${rel_file}" | awk '{print $1}')"

rel_size="$(du -sh "${rel_file}" | awk '{print $1}')"

echo "=> Generating metadata"

cd "${NEUTRON_DIR}"
printf "[tag]\n%s\n" "${rel_tag}" >latest.txt

cat >"${rel_tag}-info.txt" <<EOF
[date]
${rel_date}

[clang-ver]
${clang_version}

[llvm-commit]
${llvm_commit_url}

[host-glibc]
${h_glibc}

[size]
${rel_size}

[shasum]
${rel_shasum}
EOF

echo "=> Pushing catalogue updates"

git add -A

if ! git diff --cached --quiet; then
    git commit -m "catalogue: Add Neutron Clang build ${rel_tag}

Clang Version: ${clang_version}
LLVM commit: ${llvm_commit_url}
Builder commit: ${builder_commit_url}
Release: https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/tag/${rel_tag}"
fi

git gc
git push origin main -f

echo "=> Publishing GitHub release"

if gh release view "${rel_tag}" >/dev/null 2>&1; then
    echo "Uploading build archive to '${rel_tag}'..."
    gh release upload --clobber "${rel_tag}" "${rel_file}"
    echo "Version ${rel_tag} updated!"
else
    echo "Creating release '${rel_tag}'..."
    gh release create "${rel_tag}" "${rel_file}" --title "${rel_date}" --notes ""
    echo "Version ${rel_tag} released!"
fi

git push origin main -f

echo "=> Push complete"

end_msg="
<b>Ayo! New Neutron Clang Update!</b>

<b>Toolchain details</b>
clang version: <code>${clang_version}</code>
LLVM commit: <a href='${llvm_commit_url}'>Here</a>
builder commit: <a href='${builder_commit_url}'>Here</a>
build date: <code>$(date '+%Y-%m-%d %H:%M')</code>
build tag: <code>${rel_tag}</code>
glibc version: <code>${h_glibc}</code>

<b>Build Release:</b>
<a href='https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/tag/${rel_tag}'>github.com</a>
"

tgsend "${end_msg}"
rm -rf "${rel_file}"
