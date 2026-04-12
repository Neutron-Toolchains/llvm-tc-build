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

set -eou pipefail

####################
# Global variables #
####################
WORK_DIR="$(pwd)"
export WORK_DIR
export SRC_DIR="${WORK_DIR}/sources"
export BUILD_DIR="${WORK_DIR}/build"
export STOCK_PATH="${PATH}"

export USE_POLLY=1

tgsend() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="@NeutronTC_Updates" -d "disable_web_page_preview=true" -d "parse_mode=html" -d text="$1"
}

clear_if_unused() {
    if [[ $1 -eq 0 ]]; then
        unset "$2"
    fi
}

check_if_exists() {
    if [ -d "$1" ] && [ "$(ls -A "$1")" ]; then
        ok "dir: $1 exists."
    else
        die "dir: $1 does not exist."
    fi
}

git_get() {
    local repo="$1"
    local branch="$2"
    local dir="$3"

    if [[ -d $dir ]]; then
        info "Directory $dir already exists, checking for updates..."
        cd "$dir" || die "Could not cd into $dir"
        git pull origin "$branch"
    else
        info "Cloning $repo into $dir"
        git clone "$repo" "$dir" -b "$branch"
    fi

}

download_and_extract() {
    local target_dir="$1"
    local url="$2"
    local archive_name
    archive_name=$(basename "$url")

    if [ -d "$target_dir" ] && [ "$(ls -A "$target_dir")" ]; then
        info "Skipping download: $target_dir already exists and is not empty"
    else
        info "Downloading and extracting $archive_name into $target_dir"
        mkdir -p "$target_dir"
        cd "$target_dir" || die "Could not cd into $target_dir"
        wget -q "$url"
        case "$archive_name" in
            *.zip)
                unzip -q "$archive_name"
                ;;
            *)
                tar -xf "$archive_name"
                ;;
        esac
        rm -f "$archive_name"
    fi
}

# Logging helpers
log() { echo -e "\n\033[1;36m[$(date '+%H:%M:%S')] >>> $*\033[0m"; }
info() { echo -e "\033[0;33m    $*\033[0m"; }
ok() { echo -e "\033[0;32m      $*\033[0m"; }
warn() { echo -e "\033[0;35m    $*\033[0m"; }
die() {
    echo -e "\033[0;31m[FATAL] $*\033[0m" >&2
    exit 1
}

require_tool() { command -v "$1" &>/dev/null || die "Required tool not found: $1"; }
