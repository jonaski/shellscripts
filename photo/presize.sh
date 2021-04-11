#!/bin/sh
#
# presize.sh
# Copyright (C) 2019 Jonas Kvinge
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

# Resize all JPEG's in the specific directory.
# Always convert to progressive when progressive is set to 1.

sourcedir="/run/media/jonas/MUSIC/"
maxsize=1000
progressive=1
#92666.220695

which sed awk convert identify >/dev/null || exit 1

IFS_DEFAULT=$IFS
IFS=$'\n'
for fullfile in $(find $sourcedir)
do

  IFS=$IFS_DEFAULT

  if [ -d "$fullfile" ] ; then
    continue
  fi

  dir=$(dirname "$fullfile")
  #diresc=$(echo "$dir" | sed 's/ /\\\ /g')
  imagename=$(echo "$fullfile" | awk -F/ '{print $NF}')
  #imagenameesc=$(echo "$imagename" | sed 's/ /\\\ /g')

  image=0
  imagenamelow=$(echo "$imagename" | tr '[:upper:]' '[:lower:]')
  case "$imagenamelow" in
    *.jpg ) image=1;;
    *.jpeg ) image=1;;
    * ) image=0;;
  esac

  if ! [ "$image" = 1 ] ; then
    continue
  fi

  geometry=$(identify "${dir}/${imagename}" | sed 's/.*JPEG //g' | awk '{print $1}') || exit 1
  if [ "$geometry" = "" ] ; then
    echo "ERROR: Cannot determine format and geometry for image: \"$imagename\"."
    exit 1
  fi

  # Geometry can be 563x144+0+0 or 75x98
  # we need to get rid of the plus (+) and the x characters:
  width=$(echo "$geometry" | sed 's/[^0-9]/ /g' | awk '{print $1}') || exit 1
  if [ "$width" = "" ] ; then
    echo "ERROR: Cannot determine width for image: \"$imagename\"."
    exit 1
  fi
  height=$(echo "$geometry" | sed 's/[^0-9]/ /g' | awk '{print $2}') || exit 1
  if [ "$height" = "" ] ; then
    echo "ERROR: Cannot determine height for image: \"$imagename\"."
    exit 1
  fi
  #echo "$imagename ${width}x${height}"
  if [ "$height" -gt "$maxsize" ] || [ "$width" -gt "$maxsize" ]; then
    echo "Resizing $imagename ${width}x${height}"
    convert "$fullfile" -resize ${maxsize}x${maxsize} "$fullfile" || exit 1
  fi
  
  file "$fullfile"  | grep 'progressive' >/dev/null 2>&1
  if ! [ $? -eq 0 ] && [ "$progressive" -eq 1 ]; then
    echo "Converting $imagename to progressive."
    convert "$fullfile" -interlace plane "$fullfile" || exit 1
  fi

done
