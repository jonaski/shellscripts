#!/bin/bash
#
# Photo Resize Script
# Copyright (C) 2019-2026 Jonas Kvinge
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

# Resize all JPEG's in the specific directory.
# Always convert to progressive unless --no-progressive is set.

sourcedir=""
maxsize=1000
progressive=1

script=$(basename "$0")
status=0
tmp=""

usage() {
  cat <<USAGE
Usage: $script -d <dir> [options]

Options:
  -h, --help            Show this help and exit
  -d, --dir <dir>       Directory with JPEG's (required)
  -m, --maxsize <size>  Maximum width and height in pixels (default: $maxsize)
  -n, --no-progressive  Don't convert JPEG's to progressive
USAGE
}

error() {
  echo "ERROR: $*" >&2
  status=1
}

cleanup() {
  if [ -n "$tmp" ]; then
    rm -f -- "$tmp"
  fi
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Parse the parameters.

parsedargs=$(getopt -o hd:m:n -l help,dir:,maxsize:,no-progressive -n "$script" -- "$@") || {
  echo "ERROR: Invalid option" >&2
  exit 1
}
eval set -- "$parsedargs"

while true; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -d|--dir) sourcedir="$2"; shift 2 ;;
    -m|--maxsize) maxsize="$2"; shift 2 ;;
    -n|--no-progressive) progressive=0; shift ;;
    --) shift; break ;;
  esac
done

if [ $# -ne 0 ]; then
  echo "ERROR: Unexpected argument: $1" >&2
  exit 1
fi

# Check the system and the settings.

if [ -z "$sourcedir" ]; then
  echo "ERROR: Missing required option: --dir" >&2
  usage >&2
  exit 1
fi

for cmd in find realpath getopt mktemp dirname chmod mv rm magick jpegtran; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Missing required command: $cmd" >&2
    exit 1
  fi
done

if ! [ -d "$sourcedir" ] || ! sourcedir=$(realpath -- "$sourcedir"); then
  echo "ERROR: Not a directory: $sourcedir" >&2
  exit 1
fi

if ! [[ $maxsize =~ ^[1-9][0-9]{0,8}$ ]]; then
  echo "ERROR: Maximum size must be a positive number of pixels: $maxsize" >&2
  exit 1
fi

# Resize and convert the images. Images are passed through stdin and stdout so ImageMagick doesn't interpret characters in the filenames,
# and written to a temporary file first so a failure doesn't damage the original.

exec 3< <(find "$sourcedir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print0)
findpid=$!

while IFS= read -r -d '' -u 3 file; do

  format=""
  read -r format width height interlace < <(magick identify -ping -format '%m %w %h %[interlace]\n' - < "$file")
  if [ -z "$format" ] || ! [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]]; then
    error "Cannot determine format and geometry for image: \"$file\"."
    continue
  fi

  if [ "$format" != "JPEG" ]; then
    echo "WARNING: Skipping \"$file\", it is $format and not JPEG." >&2
    continue
  fi

  echo "$file ${width}x${height}"

  resize=0
  if [ "$height" -gt "$maxsize" ] || [ "$width" -gt "$maxsize" ]; then
    resize=1
  fi

  convert=0
  if [ "$progressive" -eq 1 ] && [ "$interlace" = "None" ]; then
    convert=1
  fi

  if [ "$resize" -eq 0 ] && [ "$convert" -eq 0 ]; then
    continue
  fi

  if ! tmp=$(mktemp "$(dirname "$file")/.presize.XXXXXX"); then
    tmp=""
    error "Cannot create temporary file for image: \"$file\"."
    continue
  fi

  if [ "$resize" -eq 1 ]; then
    echo "Resizing $file ${width}x${height}"
    args=(-resize "${maxsize}x${maxsize}>")
    if [ "$progressive" -eq 1 ]; then
      args+=(-interlace plane)
    fi
    magick jpg:- "${args[@]}" jpg:- < "$file" > "$tmp"
  else
    echo "Converting $file to progressive."
    jpegtran -copy all -progressive < "$file" > "$tmp"
  fi
  result=$?

  if [ "$result" -eq 0 ] && [ -s "$tmp" ]; then
    chmod --reference="$file" -- "$tmp" 2>/dev/null
    if ! mv -f -- "$tmp" "$file"; then
      error "Cannot replace image: \"$file\"."
    fi
  else
    error "Cannot process image: \"$file\"."
  fi
  cleanup
  tmp=""

done

exec 3<&-

if ! wait "$findpid"; then
  error "Cannot read all of $sourcedir."
fi

exit "$status"
