#!/bin/bash
#
# Camera Photo Import Script
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

# This script imports photos directly from your camera or memory card into your photo directory, it copies and renames the photos after the date they were taken.
# The format is: yyyymmdd/img-yyyymmdd-hhmmss-widthxheight.ext
# Photos with the same date, time, size and type are numbered: yyyymmdd/img-yyyymmdd-hhmmss-xxx-widthxheight.ext

devices="/dev/sdd1 /dev/sde1 /dev/sdf1 /dev/sdg1 /dev/sdh1 /dev/sdi1 /dev/mmcblk0p1 /dev/mmcblk1p1"
folders="DCIM"
destdir="$HOME/Photos/New"
logfile=""
logging=1
autorotate=1
createmd5sum=0

script=$(basename "$0")
sourcedir=""
device=""
automounted=0
tempdir=""
status=0
imported=0
existing=0
sources=()

usage() {
  cat <<USAGE
Usage: $script [options]

Options:
  -h, --help            Show this help and exit
  -s, --source <dir>    Import everything in a directory instead of scanning devices
  -b, --device <dev>    Only scan this device (default: $devices)
  -d, --dest <dir>      Photo directory (default: $destdir)
  -f, --folders <list>  Space separated folders to import from on devices (default: $folders)
  -l, --logfile <file>  Logfile (default: pimport.log in the photo directory)
  -L, --no-log          Don't write a logfile
  -R, --no-rotate       Don't rotate portrait JPEG's
  -m, --md5sum          Create a MD5 checksum file in each directory
USAGE
}

# Log to file, the log can't be written until the photo directory exists. A problem with the log doesn't stop the import.

log() {
  if [ "$logging" -eq 1 ] && [ -d "$destdir" ] && ! echo "$(date) *** $1" >> "$logfile"; then
    echo "ERROR: Cannot write to logfile: $logfile" >&2
    logging=0
    status=1
  fi
}

info() {
  echo "$1"
  log "$1"
}

error() {
  echo "ERROR: $1" >&2
  log "ERROR: $1"
  status=1
}

cleanup() {
  if [ -n "$tempdir" ]; then
    rm -rf -- "$tempdir"
    tempdir=""
  fi
  if [ "$automounted" -eq 1 ]; then
    automounted=0
    if ! udisksctl unmount -b "$device"; then
      echo "ERROR: Cannot unmount $device, unmount it before removing it." >&2
      status=1
    fi
  fi
}

# Clean up and wait for a keypress when there is someone to press it, so a window opened by a launcher stays open.

finish() {
  cleanup
  if [ -t 0 ]; then
    read -r -s -n 1 -p "Press any key to exit. " _
    echo
  fi
  exit "$status"
}

# Ask a question, end of input counts as no.

ask() {
  local answer
  while true; do
    read -e -r -n 1 -p "$1 (Y/N) " answer || return 1
    case "$answer" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo "Invalid answer. Press Y or N." ;;
    esac
  done
}

# Rotate a portrait JPEG losslessly and reset the orientation tag, working on a copy so a failure leaves the photo as it was. The photo keeps its orientation tag when it can't be rotated, so it still displays correctly.

rotate_photo() {

  local photo="$1" orientation="$2" name="$3" degrees=90 rotated="$tempdir/rotated.jpg"

  if [ "$orientation" = "8" ]; then
    degrees=270
  fi

  echo "Rotating \"$name\" $degrees degrees."

  # Only JPEG's with a size in whole blocks can be rotated perfectly, otherwise up to 15 pixels are trimmed from an edge instead of leaving a strip of noise there.
  if ! jpegtran -copy all -rotate "$degrees" -perfect < "$photo" > "$rotated" 2>/dev/null; then
    echo "Trimming \"$name\" since it can't be rotated perfectly."
    if ! jpegtran -copy all -rotate "$degrees" -trim < "$photo" > "$rotated"; then
      error "Cannot rotate image, importing it with its orientation tag: \"$name\"."
      return
    fi
  fi

  if ! [ -s "$rotated" ] || ! exiv2 -M'set Exif.Image.Orientation 1' mo "$rotated" >/dev/null; then
    error "Cannot set orientation, importing the image with its orientation tag: \"$name\"."
    return
  fi

  touch -r "$photo" -- "$rotated"

  if ! mv -f -- "$rotated" "$photo"; then
    error "Cannot rotate image: \"$name\"."
  fi

}

# Copy a photo to the temporary directory, rotate it, and move it to the photo directory unless it's already there. Rotation has to be done first since it's the rotated photo that is compared with existing photos.

import_photo() {

  local file="$1" name extension photo format width height orientation exifdate datetime day prefix suffix target old number candidate unnumbered=""
  local unnumbered_regex numbered_regex

  name="${file##*/}"
  extension="${name##*.}"
  extension="${extension,,}"
  photo="$tempdir/photo.$extension"

  if ! cp --preserve=timestamps -- "$file" "$photo"; then
    error "Cannot copy image: \"$file\"."
    return
  fi

  format=""
  IFS='|' read -r format width height orientation < <(magick identify -quiet -ping -format '%m|%w|%h|%[exif:orientation]\n' "$photo" 2>/dev/null)
  if [ -z "$format" ] || ! [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]]; then
    error "Cannot determine format and geometry for image: \"$file\"."
    return
  fi

  # The date is not touched by rotating, and photos without one are not worth rotating.
  exifdate=$(LC_ALL=C exiv2 "$photo" 2>/dev/null | grep -a '^Image timestamp *:' | head -n 1)
  exifdate="${exifdate#*: }"
  if ! [[ $exifdate =~ ^[0-9]{4}:[0-9]{2}:[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]] || [[ $exifdate == 0000:00:00* ]]; then
    error "Cannot determine date for image: \"$file\"."
    return
  fi
  datetime="${exifdate:0:19}"
  datetime="${datetime//:/}"
  datetime="${datetime/ /-}"
  day="${datetime%-*}"

  # The format decides the extension when it is known, RAW formats are reported differently depending on the system so they keep their extension.
  case "$format" in
    JPEG) extension="jpg" ;;
    PNG) extension="png" ;;
    *) ;;
  esac

  if [ "$autorotate" -eq 1 ] && [ "$format" = "JPEG" ] && { [ "$orientation" = "6" ] || [ "$orientation" = "8" ]; }; then
    rotate_photo "$photo" "$orientation" "$file"
    IFS='|' read -r format width height orientation < <(magick identify -quiet -ping -format '%m|%w|%h|%[exif:orientation]\n' "$photo" 2>/dev/null)
    if ! [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]]; then
      error "Cannot determine geometry for image: \"$file\"."
      return
    fi
  fi

  prefix="img-$datetime"
  suffix="${width}x${height}.$extension"
  unnumbered_regex="^$prefix-$suffix$"
  numbered_regex="^$prefix-[0-9]{3,}-$suffix$"

  # Look for the photo among all numbered and unnumbered names, numbers can change when photos are renamed.

  for old in "$destdir/$day/$prefix-"*"$suffix"; do
    candidate="${old##*/}"
    if ! [ -f "$old" ]; then
      continue
    fi
    if [[ $candidate =~ $unnumbered_regex ]]; then
      unnumbered="$old"
    elif ! [[ $candidate =~ $numbered_regex ]]; then
      continue
    fi
    if cmp -s -- "$photo" "$old"; then
      info "Image \"$file\" already exists as \"$old\"."
      existing=$(( existing + 1 ))
      return
    fi
  done

  # Find the name, a photo that gets company in the same second is numbered as well.

  if ! mkdir -p -- "$destdir/$day"; then
    error "Cannot create directory: \"$destdir/$day\"."
    return
  fi

  target="$destdir/$day/$prefix-$suffix"
  if [ -e "$target" ] || [ -L "$target" ]; then
    number=1
    while :; do
      target=$(printf '%s/%s/%s-%03d-%s' "$destdir" "$day" "$prefix" "$number" "$suffix")
      if ! [ -e "$target" ] && ! [ -L "$target" ]; then
        break
      fi
      number=$(( number + 1 ))
    done
    if [ -n "$unnumbered" ]; then
      if ! mv -n -T -- "$unnumbered" "$target" || [ -e "$unnumbered" ]; then
        error "Cannot rename \"$unnumbered\" to \"$target\"."
        return
      fi
      info "Renamed \"$unnumbered\" to \"$target\"."
      while :; do
        number=$(( number + 1 ))
        target=$(printf '%s/%s/%s-%03d-%s' "$destdir" "$day" "$prefix" "$number" "$suffix")
        if ! [ -e "$target" ] && ! [ -L "$target" ]; then
          break
        fi
      done
    fi
  fi

  if ! mv -n -T -- "$photo" "$target" || [ -e "$photo" ]; then
    error "Cannot move image to: \"$target\"."
    return
  fi

  info "Imported \"$file\" as \"$target\"."
  imported=$(( imported + 1 ))

  if [ "$createmd5sum" -eq 1 ] && ! md5sum -- "$target" >> "$destdir/$day/$day.md5"; then
    error "Cannot write checksum for image: \"$target\"."
  fi

}

trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Parse the parameters.

arguments="$*"
parsedargs=$(getopt -o hs:b:d:f:l:LRm -l help,source:,device:,dest:,folders:,logfile:,no-log,no-rotate,md5sum -n "$script" -- "$@") || {
  echo "ERROR: Invalid option" >&2
  exit 1
}
eval set -- "$parsedargs"

while true; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -s|--source) sourcedir="$2"; shift 2 ;;
    -b|--device) devices="$2"; deviceset=1; shift 2 ;;
    -d|--dest) destdir="$2"; shift 2 ;;
    -f|--folders) folders="$2"; shift 2 ;;
    -l|--logfile) logfile="$2"; shift 2 ;;
    -L|--no-log) logging=0; shift ;;
    -R|--no-rotate) autorotate=0; shift ;;
    -m|--md5sum) createmd5sum=1; shift ;;
    --) shift; break ;;
  esac
done

if [ $# -ne 0 ]; then
  echo "ERROR: Unexpected argument: $1" >&2
  exit 1
fi

# Check the system and the settings.

if [ -n "$sourcedir" ] && [ -n "${deviceset:-}" ]; then
  echo "ERROR: Use either --source or --device." >&2
  exit 1
fi

commands="basename cat cmp cp date find getopt grep head ls md5sum mkdir mktemp mv realpath rm touch exiv2 jpegtran magick"
if [ -z "$sourcedir" ]; then
  commands="$commands findmnt udisksctl"
fi
for cmd in $commands; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Missing required command: $cmd" >&2
    exit 1
  fi
done

if [ -n "$sourcedir" ] && { ! [ -d "$sourcedir" ] || ! sourcedir=$(realpath -- "$sourcedir"); }; then
  echo "ERROR: Not a directory: $sourcedir" >&2
  exit 1
fi

if ! destdir=$(realpath -m -- "$destdir"); then
  echo "ERROR: Invalid photo directory: $destdir" >&2
  exit 1
fi

if [ -z "$logfile" ]; then
  logfile="$destdir/pimport.log"
fi

# Show the logo.

tput bold 2>/dev/null
tput setaf 7 2>/dev/null
echo "    _
   /.)  ╔═╗┌─┐┌┬┐┌─┐┬─┐┌─┐  ╔═╗┬ ┬┌─┐┌┬┐┌─┐  ╦┌┬┐┌─┐┌─┐┬─┐┌┬┐┌─┐┬─┐
  /)\|  ║  ├─┤│││├┤ ├┬┘├─┤  ╠═╝├─┤│ │ │ │ │  ║│││├─┘│ │├┬┘ │ ├┤ ├┬┘
 // /   ╚═╝┴ ┴┴ ┴└─┘┴└─┴ ┴  ╩  ┴ ┴└─┘ ┴ └─┘  ╩┴ ┴┴  └─┘┴└─ ┴ └─┘┴└─
/'\" \"                                         by Jonas Kvinge
"
tput sgr0 2>/dev/null

# Find a device with photos and mount it.

if [ -n "$sourcedir" ]; then
  sources=("$sourcedir")
else
  devices_found=0
  devices_mounted=0
  devices_photos=0
  read -r -a devicelist <<< "$devices"
  read -r -a folderlist <<< "$folders"
  echo "Scanning devices \"$devices\"..."
  for device in "${devicelist[@]}"; do

    if ! [ -e "$device" ]; then
      continue
    fi
    echo "Found device \"$device\"."
    devices_found=$(( devices_found + 1 ))

    automounted=0
    mountpoint=$(findmnt -n -f -l -o TARGET --source "$device")
    if [ -z "$mountpoint" ]; then
      echo "Mounting \"$device\"."
      if ! udisksctl mount -b "$device"; then
        continue
      fi
      automounted=1
      # udisks may return 0 even when it's not mounted.
      mountpoint=$(findmnt -n -f -l -o TARGET --source "$device")
      if [ -z "$mountpoint" ]; then
        error "Unable to find mountpoint for \"$device\"."
        automounted=0
        continue
      fi
    fi
    echo "Device \"$device\" is mounted on \"$mountpoint\"."
    devices_mounted=$(( devices_mounted + 1 ))

    sources=()
    for folder in "${folderlist[@]}"; do
      if [ -d "$mountpoint/$folder" ]; then
        sources+=("$mountpoint/$folder")
      fi
    done

    if [ ${#sources[@]} -gt 0 ]; then
      devices_photos=$(( devices_photos + 1 ))
      tput bold 2>/dev/null
      echo "Contents: "
      tput setaf 2 2>/dev/null
      ls -- "$mountpoint"
      tput sgr0 2>/dev/null
      if ask "Use $device"; then
        break
      fi
      sources=()
    else
      echo "Device \"$device\" is missing folders $folders, skipping."
    fi

    cleanup

  done
fi

if [ ${#sources[@]} -eq 0 ]; then
  if [ "$devices_found" -eq 0 ]; then
    echo "No valid devices found."
  elif [ "$devices_mounted" -eq 0 ]; then
    echo "Unable to mount any devices."
  elif [ "$devices_photos" -eq 0 ]; then
    echo "Unable to find photos on any devices."
  else
    echo "No more devices with photos."
  fi
  status=1
  finish
fi

# Don't import photos that are being imported.

for source in "${sources[@]}"; do
  case "$destdir/" in
    "$source"/*)
      echo "ERROR: The photo directory \"$destdir\" is inside \"$source\"." >&2
      status=1
      finish
      ;;
  esac
done

# Confirm the import.

if ! ask "Import photos from ${sources[*]} to $destdir"; then
  cleanup
  exit 0
fi

# Create the photo directory and a temporary directory on the same filesystem so photos appear complete in the photo directory.

if ! mkdir -p -- "$destdir" || ! tempdir=$(mktemp -d "$destdir/.pimport.XXXXXX"); then
  tempdir=""
  echo "ERROR: Cannot write to photo directory: $destdir" >&2
  status=1
  finish
fi

log "Script started with: $0 $arguments"
if [ "$logging" -eq 1 ]; then
  echo "Log file stored as $logfile"
fi

# Import the photos.

exec 3< <(find "${sources[@]}" -type f -print0)
findpid=$!

while IFS= read -r -d '' -u 3 file; do

  name="${file##*/}"
  case "${name,,}" in
    *.jpg|*.jpeg|*.cr2) import_photo "$file" ;;
    *) info "Skipping file \"$file\", unknown image format." ;;
  esac

done

exec 3<&-

if ! wait "$findpid"; then
  error "Cannot read all of ${sources[*]}."
fi

# Clean up and exit.

info "Photos imported: $imported, already existed: $existing."
if [ "$status" -ne 0 ]; then
  echo "There were errors, see the messages above."
fi

finish
