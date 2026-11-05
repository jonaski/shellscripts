#!/bin/bash
#
# Camera Photo File Rename Script
# Copyright (C) 2006-2026 Jonas Kvinge
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

# This script renames photos in all the subdirectories directly inside the specified directory, using the date and time from the EXIF data.
# Photos directly in the specified directory and in deeper subdirectories are not touched, and photos without an EXIF date are reported and skipped.
#
# The format is: img-yyyymmdd-hhmmss-widthxheight.ext
# Photos with the same date, time, size and type in a directory are numbered: img-yyyymmdd-hhmmss-xxx-widthxheight.ext

renamedirs=0
dryrun=0
logfile=""

script=$(basename "$0")
pdir=""
status=0

usage() {
  cat <<USAGE
Usage: $script -d <dir> [options]

Options:
  -h, --help            Show this help and exit
  -d, --dir <dir>       Directory with a subdirectory for each album (required)
  -n, --dry-run         Show what would be renamed without renaming anything
  -r, --rename-dirs     Remove '_' and '-' from the album directory names
  -l, --logfile <file>  Append all renames and errors to a file
USAGE
}

log() {
  if [ -n "$logfile" ] && ! echo "$(date) *** $1" >> "$logfile"; then
    echo "ERROR: Cannot write to logfile: $logfile" >&2
    exit 1
  fi
}

error() {
  echo "ERROR: $1" >&2
  log "ERROR: $1"
  status=1
}

# Rename the album directory if requested and set album to the directory to use, the old name is kept if it can't be renamed.

rename_album() {

  local name newname newalbum

  if [ "$renamedirs" -eq 0 ]; then
    return
  fi

  name="${album##*/}"
  newname="${name//[_-]/}"
  if [ "$newname" = "$name" ]; then
    return
  fi

  newalbum="$pdir/$newname"
  if [ -z "$newname" ]; then
    error "Cannot rename directory \"$album\", the new name would be empty."
  elif [ -e "$newalbum" ] || [ -L "$newalbum" ]; then
    error "Cannot rename directory \"$album\", \"$newalbum\" already exists."
  elif [ "$dryrun" -eq 1 ]; then
    echo "Would rename directory \"$album\" to \"$newalbum\"."
  elif mv -n -T -- "$album" "$newalbum"; then
    echo "Renamed directory \"$album\" to \"$newalbum\"."
    log "Renamed directory \"$album\" to \"$newalbum\"."
    album="$newalbum"
  else
    error "Cannot rename directory \"$album\"."
  fi

}

# Returns true if a filename in the album is in use, taking the renames of a dry run into account.

name_in_use() {
  local path="$album/$1"
  if [ -n "${taken[$1]:-}" ]; then
    return 0
  fi
  if [ -n "${freed[$1]:-}" ]; then
    return 1
  fi
  [ -e "$path" ] || [ -L "$path" ]
}

rename_photo() {

  local name="$1" newname="$2"

  if [ "$name" = "$newname" ]; then
    echo "No need to rename file \"$album/$name\"."
    return
  fi

  if [ "$dryrun" -eq 1 ]; then
    echo "Would rename \"$album/$name\" to \"$album/$newname\"."
    taken[$newname]=1
    freed[$name]=1
  elif mv -n -T -- "$album/$name" "$album/$newname" && ! [ -e "$album/$name" ]; then
    echo "Renamed \"$album/$name\" to \"$album/$newname\"."
    log "Renamed \"$album/$name\" to \"$album/$newname\"."
  else
    error "Cannot rename \"$album/$name\" to \"$album/$newname\"."
  fi

}

# Rename the photos in an album. All photos are read first so photos with the same date, time, size and type are known and can be numbered, photos that already have a valid number keep it so names stay stable.

process_album() {

  local file name extension format width height exifdate datetime number newname i
  local -a names=() prefixes=() suffixes=() done_names=()
  local -A groupsize=()
  taken=()
  freed=()

  for file in "$album"/*; do

    if ! [ -f "$file" ]; then
      continue
    fi

    name="${file##*/}"
    extension="${name##*.}"
    extension="${extension,,}"
    case "$extension" in
      bmp|jpg|jpeg|gif|png|cr2|raw) ;;
      *)
        echo "Skipping file \"$file\", unknown image format."
        continue
        ;;
    esac

    format=""
    read -r format width height exifdate < <(magick identify -quiet -ping -format '%m %w %h %[exif:DateTimeOriginal]\n' "$file" 2>/dev/null)
    if [ -z "$format" ] || ! [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]]; then
      error "Cannot determine format and geometry for image: \"$file\"."
      continue
    fi

    if ! [[ $exifdate =~ ^[0-9]{4}:[0-9]{2}:[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]] || [[ $exifdate == 0000:00:00* ]]; then
      error "Cannot determine date for image: \"$file\"."
      continue
    fi
    datetime="${exifdate:0:19}"
    datetime="${datetime//:/}"
    datetime="${datetime/ /-}"

    # The format decides the extension when it is known, RAW formats are reported differently depending on the system so they keep their extension.
    case "$format" in
      JPEG) extension="jpg" ;;
      PNG) extension="png" ;;
      GIF|GIF87) extension="gif" ;;
      BMP|BMP2|BMP3) extension="bmp" ;;
      *) ;;
    esac

    names+=("$name")
    prefixes+=("img-$datetime")
    suffixes+=("${width}x${height}.$extension")
    groupsize["img-$datetime ${width}x${height}.$extension"]=$(( ${groupsize["img-$datetime ${width}x${height}.$extension"]:-0} + 1 ))

  done

  if [ ${#names[@]} -eq 0 ]; then
    echo "No images to rename in directory \"$album\"."
    return
  fi

  # Reserve the names that are already correct.

  for i in "${!names[@]}"; do
    done_names[i]=""
    if [ "${groupsize["${prefixes[i]} ${suffixes[i]}"]}" -gt 1 ]; then
      if [[ ${names[i]} =~ ^"${prefixes[i]}"-[0-9]{3,}-"${suffixes[i]}"$ ]]; then
        done_names[i]="${names[i]}"
      fi
    elif [ "${names[i]}" = "${prefixes[i]}-${suffixes[i]}" ]; then
      done_names[i]="${names[i]}"
    fi
    if [ -n "${done_names[i]}" ]; then
      taken[${names[i]}]=1
    fi
  done

  # Find a name for the rest and rename all.

  for i in "${!names[@]}"; do

    newname="${done_names[i]}"

    if [ -z "$newname" ] && [ "${groupsize["${prefixes[i]} ${suffixes[i]}"]}" -eq 1 ]; then
      if ! name_in_use "${prefixes[i]}-${suffixes[i]}"; then
        newname="${prefixes[i]}-${suffixes[i]}"
      elif [[ ${names[i]} =~ ^"${prefixes[i]}"-[0-9]{3,}-"${suffixes[i]}"$ ]]; then
        newname="${names[i]}"
      fi
    fi

    if [ -z "$newname" ]; then
      number=1
      while :; do
        newname=$(printf '%s-%03d-%s' "${prefixes[i]}" "$number" "${suffixes[i]}")
        if ! name_in_use "$newname"; then
          break
        fi
        number=$(( number + 1 ))
      done
    fi

    rename_photo "${names[i]}" "$newname"

  done

}

# Parse the parameters.

arguments="$*"
parsedargs=$(getopt -o hd:nrl: -l help,dir:,dry-run,rename-dirs,logfile: -n "$script" -- "$@") || {
  echo "ERROR: Invalid option" >&2
  exit 1
}
eval set -- "$parsedargs"

while true; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -d|--dir) pdir="$2"; shift 2 ;;
    -n|--dry-run) dryrun=1; shift ;;
    -r|--rename-dirs) renamedirs=1; shift ;;
    -l|--logfile) logfile="$2"; shift 2 ;;
    --) shift; break ;;
  esac
done

if [ $# -ne 0 ]; then
  echo "ERROR: Unexpected argument: $1" >&2
  exit 1
fi

# Check the system and the settings.

if [ -z "$pdir" ]; then
  echo "ERROR: Missing required option: --dir" >&2
  usage >&2
  exit 1
fi

for cmd in basename date getopt magick mv realpath; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Missing required command: $cmd" >&2
    exit 1
  fi
done

if ! [ -d "$pdir" ] || ! pdir=$(realpath -- "$pdir"); then
  echo "ERROR: Not a directory: $pdir" >&2
  exit 1
fi

# Rename the photos in each album.

shopt -s nullglob
declare -A taken=() freed=()

log "Script started with: $0 $arguments"

for album in "$pdir"/*; do

  if ! [ -d "$album" ]; then
    continue
  fi

  echo "Entering directory \"$album\"."
  rename_album
  process_album

done

exit "$status"
