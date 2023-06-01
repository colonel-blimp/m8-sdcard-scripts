#!/bin/bash
# ------------------------------------------------------------------------------
# Deduplicate files under a directory tree on a BTRFS filesystem
# ------------------------------------------------------------------------------
# Usage:
#
#   bash $0 [DIRECTORY_TO_DEDUPE]
#
#
# If DIRECTORY_TO_DEDUPE is not given, the current directory will be deduped
# ------------------------------------------------------------------------------
# Requirements:
#
#   - a BTRFS filesystem
#   - `duperemove` (https://github.com/markfasheh/duperemove)
#   - `findmnt`
#
# ------------------------------------------------------------------------------
# Notes:
#
#   - Builds a `duperemove.hashfile` file in the current directory.
#     - This file will be re-used on subsequence runs.
#   - Refuses to run on non-BTRFS filesystems
#     - It _should_ be safe to run on XFS filesystems created with the
#     `reflink` option, but I haven't been using XFS to test it out


duperemove_hashfile="${DUPEREMOVE_HASHFILE:-duperemove.hashfile}"
target_dir="$PWD"

if [[ $# -gt 0 ]]; then
  [ -e "$1" ] || { >&2 echo "ERROR: '$1' not found!"; exit 1; }
  if [[ -d "$1" ]]; then
    target_dir="$1"
  else
    >&2 echo "ERROR: '$1' is not a directory!  ($(file --brief "$1"))"
    exit 1
  fi
fi


fstype="$(findmnt -T "$target_dir" -o FSTYPE -n)"
if [[ "$fstype" != btrfs ]]; then
  echo "ERROR: This script only dedupes btrfs, not '$fstype' at '$target_dir'"
  exit 1
fi


duperemove \
  -d -A -h -r -v \
  --dedupe-options=noblock,same \
  --lookup-extents=yes  \
  --hashfile "$duperemove_hashfile" \
  "$target_dir"


