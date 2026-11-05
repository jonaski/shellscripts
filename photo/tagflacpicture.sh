#!/bin/bash
#
# Tag FLAC Picture Script
# Copyright (C) 2023-2026 Jonas Kvinge
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

# Embed a front cover in all FLAC files in the specific directory that don't already have one, using an image from the same directory as the FLAC file.
# JPEG is preferred over PNG, and the filenames "cover" and "front" are preferred over other filenames.

sourcedir=""
picture_size=2000

script=$(basename "$0")
status=0
tmpdir=""
picture=""
picture_source=""
picture_dir=""
picture_ok=0

usage() {
  cat <<USAGE
Usage: $script -d <dir> [options]

Options:
  -h, --help         Show this help and exit
  -d, --dir <dir>    Directory with FLAC files (required)
  -s, --size <size>  Maximum picture width and height in pixels (default: $picture_size)
USAGE
}

error() {
  echo "ERROR: $*" >&2
  status=1
}

# Find the image to use in a directory, and set picture_source to it. PNG is only considered when there are no JPEG's.

select_picture() {

  local dir="$1"
  local format candidates file name preferred

  picture_source=""

  for format in jpeg png; do

    if [ "$format" = "jpeg" ]; then
      mapfile -d '' candidates < <(find "$dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print0 | LC_ALL=C sort -z)
    else
      mapfile -d '' candidates < <(find "$dir" -maxdepth 1 -type f -iname '*.png' -print0 | LC_ALL=C sort -z)
    fi

    for preferred in cover front; do
      for file in "${candidates[@]}"; do
        name=$(basename "$file")
        name="${name%.*}"
        if [ "${name,,}" = "$preferred" ]; then
          picture_source="$file"
          return 0
        fi
      done
    done

    if [ ${#candidates[@]} -eq 1 ]; then
      picture_source="${candidates[0]}"
      return 0
    fi

    if [ ${#candidates[@]} -gt 1 ]; then
      error "Several images and none named cover or front in \"$dir\"."
      return 1
    fi

  done

  error "Missing image in \"$dir\"."
  return 1

}

# Prepare the picture for a directory as a temporary file. It always gets a safe name since metaflac and ImageMagick interpret characters in filenames, images are passed through stdin for the same reason.

prepare_picture() {

  local format="" width height extension

  select_picture "$1" || return 1

  read -r format width height < <(magick identify -ping -format '%m %w %h\n' - < "$picture_source")
  if [ -z "$format" ] || ! [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]]; then
    error "Cannot determine format and geometry for image: \"$picture_source\"."
    return 1
  fi

  case "$format" in
    JPEG) extension="jpg" ;;
    PNG) extension="png" ;;
    *)
      error "Unsupported format $format for image: \"$picture_source\"."
      return 1
      ;;
  esac

  picture="$tmpdir/cover.$extension"

  if [ "$width" -gt "$picture_size" ] || [ "$height" -gt "$picture_size" ]; then
    if ! magick "$extension:-" -resize "${picture_size}x${picture_size}>" "$extension:-" < "$picture_source" > "$picture"; then
      error "Cannot resize image: \"$picture_source\"."
      return 1
    fi
  elif ! cp -- "$picture_source" "$picture"; then
    error "Cannot copy image: \"$picture_source\"."
    return 1
  fi

  return 0

}

trap 'rm -rf -- "$tmpdir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Parse the parameters.

parsedargs=$(getopt -o hd:s: -l help,dir:,size: -n "$script" -- "$@") || {
  echo "ERROR: Invalid option" >&2
  exit 1
}
eval set -- "$parsedargs"

while true; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -d|--dir) sourcedir="$2"; shift 2 ;;
    -s|--size) picture_size="$2"; shift 2 ;;
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

for cmd in find sort grep cp rm realpath getopt mktemp dirname basename magick metaflac; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Missing required command: $cmd" >&2
    exit 1
  fi
done

if ! [ -d "$sourcedir" ] || ! sourcedir=$(realpath -- "$sourcedir"); then
  echo "ERROR: Not a directory: $sourcedir" >&2
  exit 1
fi

if ! [[ $picture_size =~ ^[1-9][0-9]{0,8}$ ]]; then
  echo "ERROR: Picture size must be a positive number of pixels: $picture_size" >&2
  exit 1
fi

if ! tmpdir=$(mktemp -d); then
  tmpdir=""
  echo "ERROR: Cannot create temporary directory." >&2
  exit 1
fi

# Add the covers. The picture is reused for all FLAC files in a directory, and a directory without a usable picture is only reported once.

exec 3< <(find "$sourcedir" -type f -iname '*.flac' -print0)
findpid=$!

while IFS= read -r -d '' -u 3 flacfile; do

  if ! pictures=$(metaflac --list --block-type=PICTURE "$flacfile"); then
    error "Cannot read FLAC file: \"$flacfile\"."
    continue
  fi

  if grep -q '^ *type: 3 ' <<< "$pictures"; then
    echo "File $flacfile already has embedded cover."
    continue
  fi

  dir=$(dirname "$flacfile")

  if [ "$dir" != "$picture_dir" ]; then
    picture_dir="$dir"
    picture_ok=0
    rm -f -- "$tmpdir"/cover.*
    if prepare_picture "$dir"; then
      picture_ok=1
    fi
  fi

  if [ "$picture_ok" -eq 0 ]; then
    continue
  fi

  echo "Adding embedded cover to file $flacfile from $picture_source."
  if ! metaflac --import-picture-from="$picture" "$flacfile"; then
    error "Cannot add embedded cover to file: \"$flacfile\"."
  fi

done

exec 3<&-

if ! wait "$findpid"; then
  error "Cannot read all of $sourcedir."
fi

exit "$status"
