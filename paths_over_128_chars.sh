#!/bin/sh
# ------------------------------------------------------------------------------
# Identify paths longer than 127 characters on a (mounted) SD card
# ------------------------------------------------------------------------------
# For convenience, place this script under a /.Scripts folder on the M8's SD
# ------------------------------------------------------------------------------
#
# Requirements:
#
#   - bash
#   - find or gfind (mac) command
#
# Usage:
#
#   bash /PATH/TO/M8_SD_MOUNT/.Scripts/paths_over_128_chars.sh
#
# or:
#
#   bash paths_over_128_chars.sh /PATH/TO/M8_SD_MOUNT
#
# ------------------------------------------------------------------------------
# CHANGELOG
#
#   1.0.0  ineffable        initial release
#   1.1.1  oldschoolbuzzer  fix for macs (use gfind instead of find)
#   1.2.0  ineff            auto-detect gfind/find command
#   1.2.1  ineff + osb      '>&2 /dev/null' changed to '>/dev/null 2>&1'
#
# ------------------------------------------------------------------------------
# shellcheck disable=SC3010,SC3011,SC3030,SC3024,SC3045,SC3054,SC21854
#
# from ineff

max_characters_in_path=127

# Auto-detect gfind (mac) or find command
FIND_EXE="${FIND_EXE:-}"
[ -n "$FIND_EXE" ] || FIND_EXE="$(command -v gfind)" >/dev/null 2>&1
[ -n "$FIND_EXE" ] || FIND_EXE="$(command -v find)"
if [ -z "$FIND_EXE" ]; then
  >&2 echo "ERROR: cannot locate a 'find' or 'gfind' command"
  exit 1
fi

# If the script lives under a /.Scripts directory on the M8 card,
# auto-determine the parent's directory path (the SD card's mount location)
# shellcheck disable=SC2164
script_path="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
if [[ "$(basename "$script_path")" == .Scripts ]]; then
  target_path="$(realpath "$script_path/..")"
fi

if [[ $# -gt 0 ]]; then
  if [[ -d "$1" ]]; then
    target_path="$1"
  else
    file "$1"
    >&2 echo "ERROR: '$1' is not a directory!"
    exit 1
  fi
fi

if [[ -z "$target_path" ]]; then
  >&2 echo "ERROR: no target path"
fi

env  | egrep 'SHELL|BASH|VERSION'
find_long_paths()
{
  cd "$1" || { >&2 echo "ERROR: couldn't change directory to '$1'"; exit 1; }
  printf "Checking for paths longer than 128 characters under '%s'...\n" "$1"
  bad_paths=()
  "$FIND_EXE" -type f -regextype sed -regex "^.\{$max_characters_in_path,\}" -print0 | {
    # piped into command grouping to avoid subshells (keeps $bad_paths in scope)
    while read -rd '' path; do
      bad_paths+=("$path")
    done

    for i in "${bad_paths[@]}"; do
      echo "$(wc -c <<< "$i")  $i"
    done | sort -nk1,1
    printf "\nFound %s files with paths longer than 128 characters under '%s'\n" "${#bad_paths[@]}" "$1"
  }
}

find_long_paths "$target_path"
