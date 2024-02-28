#!/bin/bash
# ------------------------------------------------------------------------------
# Make versioned, reflinked backups of your M8's SD card
# ------------------------------------------------------------------------------
# Requires:
#   - rsync
#   - findmnt
#
# Strongly recommended:
#   - BTRFS filesystem
#     (or any another CoW filesystem that supports `cp --reflink=always`)
# ------------------------------------------------------------------------------
# Overview:
#
# 1. Backs up a local mirror of your SD card to `sdcards/<card_name>/`
# 2. Makes 2 reflinked[1] copies of this backup:
#    - A dated snapshot under `sdcards/archives/<card_name>.<YYYYMMDD>/`
#    - A directory to stage local changes under `sdcards/staging/<card_name>/`
#
# NOTE: It is *STRONGLY* recommended to run this on a BTRFS filesystem, or
#       something else that supports `cp --reflink=always`, otherwise those
#       dated archives are going to eat up a lot of disk space!
# ------------------------------------------------------------------------------
# Changelog:
#
# 1.2
#   - Added a fallback path to SD card
# 1.1
#   - Unswapped day/month in archive folder name
#   - Update archive directory with current date
# 1.0 - initial version

set -e -u -o pipefail

default_sdpath="${M8_SDMOUNT_DEFAULT_PATH:-/run/media/$USER/M8/}"
fallback_sdpath="${M8_SDMOUNT_FALLBACK_PATH:-/run/media/$USER/M8_256/}"
sdcard_backup_dir="${M8_SDCARD_BACKUP_DIR:-$HOME/Documents/m8/sdcards}"

if [[ $# -lt 1 ]]; then
  if [ -d "$default_sdpath" ]; then
    sdpath="$default_sdpath"
  elif [ -d "$fallback_sdpath" ]; then
    sdpath="$fallback_sdpath"
  else
    echo "ERROR: must include SD card path to backup (e.g., '$0 $default_sdpath')"
    exit 1
  fi
fi

sdpath="$(realpath -e "${sdpath:-$1}")"
sdpath="${sdpath/\/$/}"
backup_path="$sdcard_backup_dir/$(basename "$sdpath")"

backup_sdcard()
{
  local sdpath="$1"
  local backup_path="$2"

  echo
  echo
  printf "\n\n== Backing up SD card '%s' to '%s'\n\n" "$sdpath"  "$backup_path"
  rsync -auvc \
    --delete \
    --exclude=\*.{reapeaks,asd,bak,sw\?,orig,~,fseventsd,Trashes,Trash-1000,DS_Store,_\*} \
    --exclude="FOUND.???" \
    --exclude="System Volume Information" \
    --info=,progress1,progress2,backup1,skip1 \
    --stats \
    "$sdpath/" "$backup_path/"
}

make_dated_reflink_copy()
{
  local backup_path="$1"
  local backup_reflink_path
  local fstype

  mkdir -p "$backup_path"
  fstype="$(findmnt -T "$backup_path" -o FSTYPE -n)"
  backup_reflink_path="$(dirname "$backup_path")/archives/$(basename "$backup_path").$(date +%Y%m%d)"
  staging_reflink_path="$(dirname "$backup_path")/staging/$(basename "$backup_path")"

  if [ "$fstype" != btrfs ]; then
    printf "\n\nWARNING: filesystem containing backup (%s) is not btrfs; skipping dated reflink copy\n" "$fstype"
    echo "WARNING: skipping dated reflink copy"
    return
  fi

  printf "\n== Making BTRS reflinked archive copy of backup at '%s'\n" "$backup_reflink_path"

  mkdir -p "$(dirname "$backup_reflink_path")"
  cp --archive --update --no-clobber --reflink=always  "$backup_path" "$backup_reflink_path"
  touch "$backup_reflink_path"

  printf "\n== Making BTRS reflinked staging copy of backup at '%s'\n" "$staging_reflink_path"
  mkdir -p "$(dirname "$staging_reflink_path")"
  realpath -e "$(dirname "$staging_reflink_path")" > /dev/null
  rm -rf "$staging_reflink_path"
  cp --archive --update --no-clobber --reflink=always  "$backup_path" "$staging_reflink_path"
}

backup_sdcard "$sdpath" "$backup_path"
make_dated_reflink_copy "$backup_path"
