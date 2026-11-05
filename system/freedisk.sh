#!/bin/bash
#
# freedisk.sh
# Copyright (C) 2017-2026 Jonas Kvinge
#
# This script is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this script.  If not, see <http://www.gnu.org/licenses/>.
#
# Redistributions of this script must retain the above copyright notice.
#

freedir="/tmp"
maxspace=858993459200
filetypes=".mp4"

script=$(basename "$0")

usage() {
  cat <<USAGE
Usage: $script [options]

Delete the oldest matching files directly in a directory until the disk usage
of the whole directory is below the limit.

Options:
  -h, --help             Show this help and exit
  -d, --dir <dir>        Directory to free (default: $freedir)
  -m, --maxspace <bytes> Disk usage limit in bytes (default: $maxspace)
  -t, --types <types>    Space separated file types to delete (default: "$filetypes")
USAGE
}

# Parse the parameters.

parsedargs=$(getopt -o hd:m:t: -l help,dir:,maxspace:,types: -n "$script" -- "$@") || {
  echo "ERROR: Invalid option" >&2
  exit 1
}
eval set -- "$parsedargs"

while true; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -d|--dir) freedir="$2"; shift 2 ;;
    -m|--maxspace) maxspace="$2"; shift 2 ;;
    -t|--types) filetypes="$2"; shift 2 ;;
    --) shift; break ;;
  esac
done

if [ $# -ne 0 ]; then
  echo "ERROR: Unexpected argument: $1" >&2
  exit 1
fi

# Check the system and the settings.

for cmd in du cut find sort rm realpath getopt flock; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Missing required command: $cmd" >&2
    exit 1
  fi
done

if ! [ -d "$freedir" ] || ! freedir=$(realpath -- "$freedir"); then
  echo "ERROR: Not a directory: $freedir" >&2
  exit 1
fi

if ! [[ $maxspace =~ ^[0-9]{1,18}$ ]] || (( 10#$maxspace == 0 )); then
  echo "ERROR: Disk usage limit must be a positive number of bytes: $maxspace" >&2
  exit 1
fi
maxspace=$(( 10#$maxspace ))

# Build the find expression, an empty one would match every file.

read -r -a types <<< "$filetypes"
names=()
for t in "${types[@]}"; do
  t=".${t#.}"
  if [ "$t" = "." ] || [[ $t == *[!A-Za-z0-9._-]* ]]; then
    echo "ERROR: Invalid file type: $t" >&2
    exit 1
  fi
  if [ ${#names[@]} -gt 0 ]; then
    names+=(-o)
  fi
  names+=(-iname "*$t")
done

if [ ${#names[@]} -eq 0 ]; then
  echo "ERROR: No file types specified" >&2
  exit 1
fi

# Only one run per directory, overlapping runs would delete too much.

exec 9<"$freedir"
if ! flock -n 9; then
  echo "ERROR: Already running for $freedir" >&2
  exit 1
fi

# Find the disk usage of the directory.

space=$(du -s -B1 -- "$freedir" | cut -f1)
if ! [[ $space =~ ^[0-9]+$ ]]; then
  echo "ERROR: Unable to determine disk usage of $freedir" >&2
  exit 1
fi

if (( space < maxspace )); then
  exit 0
fi

# Delete the oldest files first. Hard linked files are left alone since deleting them doesn't necessarily free any space.

while IFS=$'\t' read -r -d '' _ blocks file; do
  if (( space < maxspace )); then
    break
  fi
  echo "Deleting ${file}..."
  if rm -f -- "$file"; then
    space=$(( space - blocks * 512 ))
  fi
done < <(find "$freedir" -maxdepth 1 -type f -links 1 \( "${names[@]}" \) -printf '%T@\t%b\t%p\0' | LC_ALL=C sort -z -n)

if (( space < maxspace )); then
  echo "Freed required space."
  exit 0
else
  echo "Unable to free required space."
  exit 1
fi
