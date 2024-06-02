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
#     (or another CoW filesystem that supports `cp --reflink=always`, however
#     the script currently checks specifically for BTRFS since it's not clear
#     how to check for reflink support in a more general way for XFS, APFS, etc.)
# ------------------------------------------------------------------------------
# Overview:
#
# 1. Backs up a local mirror of your SD card to `sdcards/<card_name>/`
# 2. Makes 2 reflinked[1] copies of this backup:
#    - A dated snapshot under `sdcards/archives/<card_name>.<YYYYMMDD>/`
#    - A directory to stage local changes under `sdcards/staging/<card_name>/`
#
# ------------------------------------------------------------------------------
# Notes:
#
# - It is *STRONGLY* recommended to run this on a BTRFS filesystem, or
#   something else that supports `cp --reflink=always`, otherwise those dated
#   archives are going to eat up a lot of disk space!
#
# - The script can manage backups for multiple cards
#   - Each card's backup directory is named after its volume label
#   - So make sure each card uses a different volume label ;P
#
# - The "staging" directory is a safe workspace for making local changes
#   to the SD's contents before copying them back to the card
#   - It's a reflinked mirror of the latest successful backup
#   After making the changes you want, you can then use a command like
#      `rsync -avc --delete staging/<card_name>/ /run/media/$USER/M8/` to copy those staged changes back to the SD card.
#
# - There is a detailed guide to interpreting the rsync transfer status messages
#   (which at --info=progress2 are both very informative and cryptic) at:
#
#     https://unix.stackexchange.com/a/261139
#
# ------------------------------------------------------------------------------
#
#
# ------------------------------------------------------------------------------
# Changelog:
# 1.4
#   - Removed very slow -c from rsync now that M8 FW 3.3.0+ updates files' mtimes
#   - Added env var `M8_SD_BACKUP_STAGING_PATH` to change staging path
# 1.3
#   - Added env var `OKAY_TO_FAIL_RSYNC=yes` to stage/archive after SD failure
#   - Fix: exclude patterns are more precise excluding dot files vs extensions
# 1.2
#   - Added a fallback path to SD card
# 1.1
#   - Unswapped day/month in archive folder name
#   - Update archive directory with current date
# 1.0 - initial version

set -e -u -o pipefail

sdcard_backup_dir="${M8_SDCARD_BACKUP_DIR:-$HOME/Documents/m8/sdcards}"


# A default for anyone who hasn't customized $preferred_sdcard_volume_label or set any env vars

# Set the default (or env var M8_SDCARD_VOLUME_LABEL) to your normal SD card volume label
default_preferred_sdcard_volume_label="${M8_SDCARD_VOLUME_LABEL:-M8_256}"
default_sdmounts_parent_path="${M8_SDMOUNTS_PARENT_PATH:-/run/media/$USER}"
default_sdpath="${M8_SDMOUNT_DEFAULT_PATH:-$default_sdmounts_parent_path/M8/}"
default_preferred_sdpath="${M8_SDMOUNT_PATH:-$default_sdmounts_parent_path/$default_preferred_sdcard_volume_label/}"

# Locate SD
# --------------------------------------
if [[ $# -lt 1 ]]; then
  echo "No argument provided for mounted SD path; attempting to locate M8 SD card..."
  if [ ! -d "$default_sdmounts_parent_path" ]; then
    echo "ERROR: The expected parent directory under which SD cards are mounted was not found at '$default_sdmounts_parent_path' (change with M8_SDMOUNTS_PARENT_PATH)"
    echo "ERROR: Cannot automatically locate M8 SD card(s) to back up!"
    exit 1
  fi

  echo "Looking for M8 SD cards under '$default_sdmounts_parent_path' (change with M8_SDMOUNTS_PARENT_PATH):"
  for path in "$default_preferred_sdpath" "$default_sdpath"; do
    if [ -d "$path" ]; then
      echo "  ++ Found mounted SD card at '$path'"
      break
    else
      echo "  -- No SD card found at '$path'"
    fi
  done
  if [ -d "$default_preferred_sdpath" ]; then
    echo "Found sd card at preferred default path '$default_preferred_sdpath' (change with M8_SDMOUNT_PATH)"
    sdpath="$default_preferred_sdpath"
  elif [ -d "$default_sdpath" ]; then
    echo "  Found sd card with default volume label '$default_preferred_sdcard_volume_label'"
    echo "  (change with M8_SDCARD_VOLUME_LABEL) at '$default_sdpath' (change with M8_SDMOUNT_DEFAULT_PATH)"
    sdpath="$default_sdpath"
  else
    echo "ERROR: must include SD card path to backup (e.g., '$0 $default_sdpath')"
    echo "       or set environment variables to enable automatic SD card detection (see script comments for details)"
    exit 1
  fi
fi

sdpath="$(realpath -e "${sdpath:-$1}")"
sdpath="${sdpath/\/$/}"


# Locate backup/archive paths
# --------------------------------------
backup_path="$sdcard_backup_dir/$(basename "$sdpath")"
backup_reflink_path="$(dirname "$backup_path")/archives/$(basename "$backup_path").$(date +%Y%m%d)"
staging_reflink_path="${M8_SD_BACKUP_STAGING_PATH:-"$(dirname "$backup_path")/staging}/$(basename "$backup_path")"}"
if [ -n "${M8_SD_BACKUP_STAGING_PATH:-}" ]; then
  if [[ ! $M8_SD_BACKUP_STAGING_PATH =~ /staging/ ]]; then
		staging_reflink_path="${M8_SD_BACKUP_STAGING_PATH}/$(basename "$sdpath").staging"
  fi
fi

backup_sdcard()
{
  local sdpath="$1"
  local backup_path="$2"

  echo
  echo
  printf "\n\n== Backing up SD card '%s' to '%s'\n\n" "$sdpath"  "$backup_path"
  rsync -av \
    --delete \
    --exclude=\*.{reapeaks,asd,bak,sw\?,orig,~} \
    --exclude=.{_,fseventsd,Trashes,Trash-1000,DS_Store}\* \
    --exclude="FOUND.???" \
    --exclude="System Volume Information" \
		--exclude=Backup \
    --info=,progress1,progress2,backup1,skip1 \
    --stats \
    "$sdpath/" "$backup_path/"
}

make_dated_reflink_copy()
{
  local backup_path="$1"
  local backup_reflink_path="$2"
  local staging_reflink_path="$3"
  local fstype

  mkdir -p "$backup_path"
  fstype="$(findmnt -T "$backup_path" -o FSTYPE -n)"

  if [ "$fstype" != btrfs ]; then
    printf "\n\nWARNING: filesystem containing backup (%s) is not BTRFS; skipping dated reflink copy\n" "$fstype"
    echo "WARNING: skipping dated reflink copy"
    return
  fi

  printf "\n== Making BTRS reflinked archive copy of backup at '%s'\n" "$backup_reflink_path"

  mkdir -p "$(dirname "$backup_reflink_path")"
  cp --archive --update --no-clobber --reflink=always  "$backup_path" "$backup_reflink_path"
  realpath -e "$(dirname "$backup_reflink_path")" > /dev/null
  touch "$backup_reflink_path"

	if [ $SKIP_STAGING == yes ]; then
		return
	fi

  printf "\n== Making BTRS reflinked staging copy of backup at '%s'\n" "$staging_reflink_path"

  mkdir -p "$(dirname "$staging_reflink_path")"
  realpath -e "$(dirname "$staging_reflink_path")" > /dev/null
  rm -rf "$staging_reflink_path"
  cp --archive --update --no-clobber --reflink=always  "$backup_path" "$staging_reflink_path"
}


okay_to_fail_rsync="${OKAY_TO_FAIL_RSYNC:-no}"
if [[ "$okay_to_fail_rsync" == "yes" ]]; then
  backup_sdcard "$sdpath" "$backup_path" || cat 1>&2 <<WARNING

  ------------------------------------------------------------------------------
  WARNING: rsync exited with an error code ($?)!

    Despite this, we are STILL CREATING a dated reflink archive/ & staging/ directory
    because OKAY_TO_FAIL_RSYNC=yes

    To prevent this behavior, unset OKAY_TO_FAIL_RSYNC or set it to 'no'
  -------------------------------------------------------------------------------
WARNING

else
  backup_sdcard "$sdpath" "$backup_path" || { cat 1>&2 <<WARNING

  ------------------------------------------------------------------------------
  ERROR: rsync exited with an error code ($?)!!!

    As a precaution, we are NOT CREATING a reflinked copy of this backup
    under archives/ or staging/.

    If you are comfortable with the errors rsync encountered above, and
    want to force making a dated archive and staging directory, re-run
    this script with the following environment var: OKAY_TO_FAIL_RSYNC=yes
  -------------------------------------------------------------------------------

WARNING
  false
}
fi

make_dated_reflink_copy "$backup_path" "$backup_reflink_path" "$staging_reflink_path"


# vim:noexpandtab tabstop=2 shiftwidth=2:
