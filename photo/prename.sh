#!/bin/sh
###########################################################################
# prename.sh - Camera Photo File Renamer
# Copyright (C) 2006-2010 Jonas Kvinge
###########################################################################
# Redistributions of this source code must retain the above
# copyright notice.
###########################################################################
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
###########################################################################
#
# ABOUT THIS SCRIPT:
#
# This script renames photos in a all the subdirectories inside the
# specified directory.
#
# The format is: img-subdir-xxx-widthxheight.ext
#
# Last modified: 29/12-2007
#
###########################################################################

version="1.3.2"
revision="20070410"

# Basic settings

logging=0					# Log all the changes to a file so you can see what has been done.
logfile="prename.log"				# Filename of the logfile.
renamedirs=1					# Remove '_' and '-' from dirs.
createmd5sum=0					# Create a MD5 checksum file in each directory.


###########################################################################
##################### DONT CHANGE ANYTHING BELOW HERE #####################
###########################################################################

# Find out how to echo without newline

c=''
n=''
if [ "`eval echo -n 'a'`" = "-n a" ] ; then
  c='\c'
else
  n='-n'
fi

# Exit if no directory is specified.

if [ "$1" = "" ] ; then
  echo "Usage: $0 <Photo Directory>"
  exit 1
fi

pdir="$1"

# Check if the root directory is valid.

if [ ! -d "$pdir" ] ; then
  echo "ERROR: \"$pdir\" is not a directory!"
  exit 1
fi

# See if the system has the needed commands to continue.

for cmd in "which" "ls" "mkdir" "mv" "cp" "rm" "sed" "awk" "bc" "tr" "date" "identify" "convert" "mogrify"
do
  which $cmd >/dev/null 2>&1
  if [ $? != 0 ] ; then
    echo "ERROR: Missing the \"${cmd}\" command!"
    exit 1
  fi
done

echo "--------------------------------------------------------"
echo "Camera Photo File Renamer v${version}"
echo "Copyright (C) 2006-2010 Jonas Kvinge"
echo "--------------------------------------------------------"

# Function to log to file and screen

logfile () {

  if [ "$2" = 2 ] ; then
    echo "$1"
  fi

  if [ "$logging" = "1" ] ; then
    echo "`date` *** $1" >>"$pdir/$logfile" || exit 1
  fi

}

logfile "Script started with: $0 $*" 2
if [ "$logging" = "1" ] ; then
  echo "Log file stored as $pdir/$logfile"
fi

# Parse the photo directory.

for ddir in $pdir/*
do

  ddir=`echo $ddir | awk -F/ '{print $NF}'`

  # If this is not a directory, then skip it.
  if [ ! -d "${pdir}/${ddir}" ] ; then
    continue
  fi

  logfile "Entering directory \"$pdir/$ddir\"." 2

  if [ "$renamedirs" = "1" ] ; then
    ddirnew=`echo $ddir | sed -e 's/_//g' -e 's/-//g'`
    if [ ! "$ddirnew" = "$ddir" ] ; then
      echo $n "Renaming \"$pdir/$ddir\" to \"$pdir/$ddirnew\". $c"
      mv "${pdir}/${ddir}" "${pdir}/${ddirnew}" || exit 1
      echo "Done."
      logfile "Renamed directory \"$pdir/$ddir\" to \"$pdir/$ddirnew\"." 1
    fi
    ddir="$ddirnew"
  fi

  image=0
  skip=0
  imagelist=""

  # Parse the files in the album.

  for imagename in ${pdir}/${ddir}/*
  do

    imagename=`echo $imagename | awk -F/ '{print $NF}'`
    imagenamefake=`echo $imagename |  sed 's/ /\:/g'`

    # Create the imagelist and ignore all files except for known images.
    image=0
    imagenamelow=`echo $imagename | tr 'A-Z' 'a-z'`
    case "$imagenamelow" in
      *.bmp ) image=1;;
      *.jpg ) image=1;;
      *.jpeg ) image=1;;
      *.gif ) image=1;;
      *.png ) image=1;;
      *.cr2 ) image=1;;
      *.raw ) image=1;;
      * ) image=0;;
    esac
    if [ "$image" = 1 ] ; then
      if [ "$imagelist" = "" ] ; then
        imagelist="$imagenamefake"
      else
        imagelist="$imagelist $imagenamefake"
      fi
    else
      logfile "Skipping file \"$pdir/$ddir/$imagename\", unknown image format." 2
    fi
  done
  # If Skip is set to 1 then this album is processed, continue to the next directory.
  if [ "$skip" = "1" ] ; then
    continue
  fi
  if [ "$imagelist" = "" ] ; then
    logfile "Skipping directory \"$pdir/$ddir\", no images in directory." 2
    continue
  fi

  # Take image by image and rename
  
  #if [ "$createmd5sum" = "1" ] ; then
  #  rm "$pdir/$ddir/$ddir.md5"
  #fi

  count=0
  for imagenamefake in $imagelist
  do

    # Set the real filename

    imagename=`echo $imagenamefake | sed 's/:/\ /g'`

    # Dermine the image format and geometry for use in the filename.

    #echo $n "Dermining format and geometry for image \"$pdir/$ddir/$imagename\". $c"
    identify=`identify "$pdir/$ddir/$imagename" | sed "s/${pdir}\/${ddir}\/${imagename} //g"` || exit 1
    if [ "$identify" = "" ] ; then
      logfile "ERROR: Cannot dermine format and geometry for image: \"$pdir/$ddir/$imagename\"." 2
      continue
    fi
    format=`echo $identify | awk '{print $1}'` || exit 1
    if [ "$format" = "" ] ; then
      logfile "ERROR: Cannot dermine format for image: \"$pdir/$ddir/$imagename\"." 2
      continue
    fi
    extension=`echo $format | tr 'A-Z' 'a-z'` || exit 1
    if [ "$extension" = "" ] ; then
      logfile "ERROR: Cannot dermine extension for image: \"$pdir/$ddir/$imagename\"." 2
      continue
    fi
    case "$extension" in
      jpeg ) extension=jpg;;
    esac
    geometry=`echo $identify | awk '{print $2}'` || exit 1
    if [ "$geometry" = "" ] ; then
      logfile "ERROR: Cannot dermine geometry for image: \"$pdir/$ddir/$imagename\"." 2
      continue
    fi

    # Geometry can be 563x144+0+0 or 75x98
    # we need to get rid of the plus (+) and the x characters:
    width=`echo $geometry | sed 's/[^0-9]/ /g' | awk '{print $1}'` || exit 1
    if [ "$width" = "" ] ; then
      logfile "ERROR: Cannot dermine width for image: \"$pdir/$ddir/$imagename\"." 2
      continue
    fi
    height=`echo $geometry | sed 's/[^0-9]/ /g' | awk '{print $2}'` || exit 1
    if [ "$height" = "" ] ; then
      logfile "ERROR: Cannot dermine height for image: \"$pdir/$ddir/$imagename\"." 2
      continue
    fi
    #echo "$format $geometry"
    
    # Dermine image date for use in filename
    
    #echo $n "Dermining date for image \"$pdir/$ddir/$imagename\". $c"
    date=`identify -format "%[exif:DateTimeOriginal]" "$pdir/$ddir/$imagename" | sed 's/\://g' | sed 's/ /-/g'` || exit 1
    if [ "$date" = "" ] ; then
      logfile "ERROR: Cannot dermine date for image: \"$pdir/$ddir/$imagename\"." 2
      continue
    fi
    #echo "$date"
    
    # Calculate the image number for use in the filename.

    count=`echo $count + 1 | bc`
    if [ $count -gt 999 ] ; then
      logfile "ERROR: Directory \"$pdir/$ddir/$sdir\" has more then 999 images. Skipping the rest."; 2
      break
    fi
    imagenumber=`echo $count | awk '{printf("%.3d", $1)}'` || exit 1
    if [ "$imagenumber" = "" ] ; then
      logfile "ERROR: Cannot format number for image: \"$pdir/$ddir/$imagename\"."; 2
      exit 1
    fi

    # Rename the filename.

    newname="img-${date}-${imagenumber}-${width}x${height}.${extension}"
    count2=0
    while :
    do
      if [ "$imagename" = "$newname" ] ; then
        logfile "No need to rename file \"$pdir/$ddir/$imagename\"." 2
        break
      fi
      if [ -f "$pdir/$ddir/$newname" ] ; then
        count2=`echo $count2 + 1 | bc`
        imagenumber2=`echo $count2 | awk '{printf("%.3d", $1)}'` || exit 1
        logfile "ERROR: File \"$pdir/$ddir/$newname\" already exist, adding extra number $count2 at the end of the filename." 2
        newname="img-${date}-${imagenumber}-${width}x${height}-${imagenumber2}.${extension}"
        continue
      fi
      #echo $n "Renaming \"$pdir/$ddir/$imagename\" to \"$pdir/$ddir/$newname\". $c"
      mv -vn "$pdir/$ddir/$imagename" "$pdir/$ddir/$newname" || exit 1
      #echo "Done."
      logfile "Renamed \"$pdir/$ddir/$imagename\" to \"$pdir/$ddir/$newname\"." 1
      imagename="$newname"
      break
    done

    #if [ "$createmd5sum" = "1" ] ; then
    #  md5sum "$pdir/$ddir/$imagename" >>"$pdir/$ddir/$ddir.md5"
    #fi

  done
  logfile "Leaving directory \"$pdir/$ddir\"." 2

done

exit 0
