#!/bin/sh
#
# pimport.sh - Camera Photo Importer
# Copyright (C) 2006-2014 Jonas Kvinge
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
# ABOUT THIS SCRIPT:
#
# This script imports photos directly from your camera or memory card
# into your specified photo directory, it copies and renames the photo
# files after photo creation date in the format:
# img-yyyymmdd-hhmmss-nnn-widthxheight.ext
#
# Last modified: 24/07-2016
#

version="0.2.5"
revision="20160724"

# Basic settings

logging=1					# Log all the changes to a file so you can see what has been done.
logfile="pimport.log"				# Filename of the logfile.
createmd5sum=0					# Create a MD5 checksum file in each directory.
autorotate=1					# Rotate photos that are taken portrait.

devices="/dev/sdd1 /dev/sde1 /dev/sdf1 /dev/sdg1 /dev/sdh1 /dev/sdi1"
folders="DCIM"
photodir="$HOME/Photos/New"
tempdir="/tmp"
tempdiresc=`echo $tempdir | sed 's/ /\\\ /g'`


##################### DONT CHANGE ANYTHING BELOW HERE #####################


# Find out how to echo without newline

c=''
n=''
if [ "`eval echo -n 'a'`" = "-n a" ] ; then
  c='\c'
else
  n='-n'
fi

# Set dirs

destdir=$photodir
if ! [ "$1" = "" ] ; then
  case "$1" in
    /dev/* ) devices=$1;;
    * ) sourcedir=$1;;
  esac
  if ! [ "$2" = "" ] ; then
    destdir=$2
  else
    destdir=$photodir
  fi
fi

# See if the system has the needed commands to continue.

for cmd in "which" "ls" "mkdir" "mv" "cp" "rm" "sed" "awk" "bc" "tr" "date" "identify" "convert" "mogrify" "exiv2" "ufraw-batch" "md5sum" "udisksctl" "mount"
do
  which $cmd >/dev/null 2>&1
  if [ $? != 0 ] ; then
    echo "ERROR: Missing the \"${cmd}\" command!"
    exit 1
  fi
done

tput bold
tput setaf 7
 echo "    _
   /.)  ╔═╗┌─┐┌┬┐┌─┐┬─┐┌─┐  ╔═╗┬ ┬┌─┐┌┬┐┌─┐  ╦┌┬┐┌─┐┌─┐┬─┐┌┬┐┌─┐┬─┐
  /)\|  ║  ├─┤│││├┤ ├┬┘├─┤  ╠═╝├─┤│ │ │ │ │  ║│││├─┘│ │├┬┘ │ ├┤ ├┬┘
 // /   ╚═╝┴ ┴┴ ┴└─┘┴└─┴ ┴  ╩  ┴ ┴└─┘ ┴ └─┘  ╩┴ ┴┴  └─┘┴└─ ┴ └─┘┴└─
/'\" \"   v${version}                                 by Jonas Kvinge
"
tput sgr0

# Function to log to file and screen

logfile () {

  if [ "$2" = 2 ] ; then
    echo "$1"
  fi

  if [ "$logging" = "1" ] && ! [ "$destdir" = "" ] ; then
    echo "`date` *** $1" >>"$destdir/$logfile" || fail
  fi

}

fail () {

  sleep 90d

  exit 1

}

# Mount device

mounted=0
devices_total=0
devices_valid=0
devices_mount=0
devices_photo=0

if [ "$sourcedir" = "" ]; then
  if ! [ "$device" = "" ]; then
    devices=$device
  fi
  echo "Scanning devices \"$devices\"..."
  for device in $devices
  do
    #echo "Device: $device"
    devices_total=`echo $devices_total + 1 | bc`
    ls $device >/dev/null 2>&1
    if ! [ $? -eq 0 ]; then
      continue
    fi
    echo "Found device \"$device\"."
    devices_valid=`echo $devices_valid + 1 | bc`
    mountpoint=
    mounted=
    automounted=
    mount=`mount | grep "^${device}"`
    if [ "$mount" = "" ]; then
      echo $n "Mounting \"$device\". $c"
      udisksctl mount -b $device || continue
      # udisks may return 0 even when it's not mounted.
      mount=`mount | grep ^${device}.*`
      if [ "$mount" = "" ]; then
        echo "Failed."
        continue
      fi
      mountpoint=`echo $mount | awk '{print $3}'`
      automounted=1
      if [ "$mountpoint" = "" ]; then
        echo "Failed to find mountpoint."
        logfile "ERROR: Unable to find mountpoint for \"$device\"." 1
        udisksctl unmount -b $device
        continue
      fi
      #echo "$mountpoint."
    else
      echo $n "Probing \"$device\". $c"
      mountpoint=`echo $mount | awk '{print $3}'`
      if [ "$mountpoint" = "" ]; then
        echo "Failed to find mountpoint."
        logfile "ERROR: Unable to find mountpoint for \"$device\"." 1
        continue
      fi
      echo "$mountpoint."
    fi
    devices_mount=`echo $devices_mount + 1 | bc`
    logfile "Device \"$device\" mounted on \"$mountpoint\"." 1
    mounted=1
    found=0
    for folder in $folders
    do
      for i in $mountpoint/*
      do
        i=`echo $i | awk -F/ '{print $NF}'`
        if [ $i = $folder ]; then
          found=1
          break
        fi
      done
    done
    if [ $found = "0" ]; then
      logfile "Device \"$device\" missing folders $folders, skipping." 1
      if [ "$automounted" = "1" ]; then
        udisksctl unmount -b $device
      fi
      mountpoint=
      mounted=
      automounted=
      continue
    fi
    devices_photo=`echo $devices_photo + 1 | bc`
    tput bold
    echo $n "Contents: $c"
    tput setaf 2
    ls $mountpoint
    tput sgr0
    while true; do
      read -e -n 1 -p "Use $device (Y/N) " answer
      case $answer in
        [Yy]* ) answer=1;break;;
        [Nn]* ) answer=0;break;;
        * ) echo "Invalid answer. Press Y or N.";;
      esac
    done
    if [ "$answer" = "0" ]; then
      if [ "$automounted" = "1" ]; then
        udisksctl unmount -b $device
      fi
      mountpoint=
      mounted=
      automounted=
      userskipped=1
      continue
    fi
    break
  done
  sourcedir=$mountpoint
fi

if [ "$sourcedir" = "" ]; then
  if [ $devices_total -eq 0 ]; then
    logfile "No devices found." 2
  else
    if [ $devices_valid -eq 0 ]; then
      logfile "No valid devices found." 2
    else
      if [ $devices_mount -eq 0 ]; then
        logfile "Unable to mount any devices." 2
      else
        if [ $devices_photo -eq 0 ]; then
          logfile "Unable to find photos on any devices." 2
        else
          logfile "No more devices with photos." 2
        fi
      fi
    fi
  fi
  read -e -n 1 -p "" answer
  exit 1
fi

# Confirmation

while true; do
  read -e -n 1 -p "Import photos from $sourcedir to $destdir (Y/N) " answer
  case $answer in
    [Yy]* ) break;;
    [Nn]* ) exit 0;;
    * ) echo "Invalid answer. Press Y or N.";;
  esac
done

# Log start

logfile "Script started with: $0 $*" 2
if [ "$logging" = "1" ] ; then
  echo "Log file stored as $destdir/$logfile"
fi

# Create photo directory

mkdir -p $destdir || fail

if [ ! -d "$destdir" ] ; then
  echo "ERROR: \"$destdir\" is not a directory!"
  read -e -n 1 -p "" answer
  exit 1
fi

# Parse the camera directory.

#Replace space with colon to avoid splitting up one image name.
#for imagename in $cdir/*
# | sed 's/ /\:/g'`
IFS_DEFAULT=$IFS
IFS=$'\n'
for fullfile in `find $sourcedir`
do

  IFS=$IFS_DEFAULT

  if [ -d "$fullfile" ] ; then
    continue
  fi

  #fullfile=`echo $fullfile | sed 's/:/\ /g'`
  cdir=`dirname "$fullfile"`
  imagename=`echo $fullfile | awk -F/ '{print $NF}'`

  cdiresc=`echo $cdir | sed 's/ /\\\ /g'`
  imagenameesc=`echo $imagename | sed 's/ /\\\ /g'`
  imagenamefake=`echo $imagename | sed 's/ /\:/g'`

  # Check if the file is a known image file.

  image=0
  imagenamelow=`echo $imagename | tr 'A-Z' 'a-z'`
  case "$imagenamelow" in
    *.jpg ) image=1;;
    *.jpeg ) image=1;;
    *.cr2 ) image=1;;
    * ) image=0;;
  esac
  if [ "$image" = 1 ] ; then
    if [ "$imagelist" = "" ] ; then
      imagelist="$imagenamefake"
    else
      imagelist="$imagelist $imagenamefake"
    fi
  else
    logfile "Skipping file \"$cdir/$imagename\", unknown image format." 2
    continue
  fi

  # Copy image to a temporary location

  echo $n "Copying \"$cdir/$imagename\" to tempdir \"$tempdir/$imagename\". $c"
  cp --preserve=timestamps "$cdir/$imagename" "$tempdir/$imagename" || fail
  echo "Done."
  logfile "Copied \"$cdir/$imagename\" to tempdir \"$tempdir/$imagename\"." 1

  # Determine orientation

  #exif=`exiftool -Orientation -n "$tempdir/$imagename"` || fail
  #if [ "$exif" = "" ] ; then
  #  logfile "ERROR: Cannot determine orientation for image: \"$tempdir/$imagename\"." 2
  #  read -e -n 1 -p "" answer
  #  exit 1
  #fi
  #orientation=`echo $exif | awk '{print $3}'` || fail
  orientation=`identify -format '%[exif:orientation]' "$tempdir/$imagename"`
  if [ "$orientation" = "" ] ; then
    logfile "ERROR: Cannot determine orientation for image: \"$tempdir/$imagename\"." 2
    read -e -n 1 -p "" answer
    exit 1
  fi
  
  # Rotate portrait photos, we need to do this BEFORE numbering the image, since checksum will change on the file.

  if [ "$autorotate" = "1" ]; then
    if [ "$orientation" = "6" ] || [ "$orientation" = "8" ]; then
      echo $n "Rotating \"$tempdir/$imagename\". $c"
      convert -auto-orient "$tempdir/$imagename" "$tempdir/$imagename"
      echo "Done."
      orientation=`identify -format '%[exif:orientation]' "$tempdir/$imagename"`
      if [ "$orientation" = "" ] ; then
        logfile "ERROR: Cannot determine orientation for image: \"$tempdir/$imagename\"." 2
        read -e -n 1 -p "" answer
        exit 1
      fi
    fi
  fi

  #if [ "$autorotate" = "1" ] && [ "$width" -gt "$height" ]; then
  #  if [ "$orientation" = "6" ]; then
  #    echo $n "Rotating \"$tempdir/$imagename\" 90 degrees. $c"
  #    convert -rotate 90 "$tempdir/$imagename" "$tempdir/$imagename"
  #    exiftool -Orientation=1 -overwrite_original -n "$tempdir/$imagename"
      #echo "Done."
  #    logfile "Rotated \"$tempdir/$imagename\" 90 degrees." 1
  #    newwidth=$height
  #    newheight=$width
  #  elif [ "$orientation" = "8" ]; then
  #    echo $n "Rotating \"$tempdir/$imagename\" 270 degrees. $c"
  #    convert -rotate 270 "$tempdir/$imagename" "$tempdir/$imagename"
  #    exiftool -Orientation=1 -overwrite_original -n "$tempdir/$imagename"
  #    logfile "Rotated \"$tempdir/$imagename\" 270 degrees." 1
  #    newwidth=$height
  #    newheight=$width
  #  fi
  #fi

  # Determine date

  #echo $n "Dermining date for image \"$tempdir/$imagename\". $c"

  exif=`exiv2 "$tempdir/$imagename" | grep -a "^Image timestamp :"`
  if [ "$exif" = "" ] ; then
    logfile "ERROR: Cannot determine date for image: \"$tempdir/$imagename\"." 2
    read -e -n 1 -p "" answer
    exit 1
  fi
  #echo "exif: $exif"

  date=`echo $exif | awk '{print $4}'` || fail
  if [ "$date" = "" ] ; then
    logfile "ERROR: Cannot determine date for image: \"$tempdir/$imagename\"." 2
    read -e -n 1 -p "" answer
    exit 1
  fi
  #echo "Date: $date"

  time=`echo $exif | awk '{print $5}'` || fail
  if [ "$date" = "" ] ; then
    logfile "ERROR: Cannot determine time for image: \"$tempdir/$imagename\"." 2
    read -e -n 1 -p "" answer
    exit 1
  fi

  date=`echo $date |  sed 's/://g'` || fail
  if [ "$date" = "" ] ; then
    logfile "ERROR: Cannot determine date for image: \"$tempdir/$imagename\"." 2
    read -e -n 1 -p "" answer
    exit 1
  fi
  time=`echo $time |  sed 's/://g'` || fail
  if [ "$date" = "" ] ; then
    logfile "ERROR: Cannot determine date for image: \"$tempdir/$imagename\"." 2
    read -e -n 1 -p "" answer
    exit 1
  fi
  
  dir=$date

  # Determine the image format and geometry for use in the filename.

  echo $n "Dermining format and geometry for image \"$tempdir/$imagename\". $c"
  
  identify=`identify $tempdiresc/$imagenameesc` || fail
  #identifyfake=`echo $identify |  sed 's/\//:/g'`
  #cdirfake=`echo $cdir |  sed 's/\//:/g'`
  #identify=`echo $identifyfake | sed "s/${cdirfake}:${imagename} //g"`

  if [ "$identify" = "" ] ; then
    logfile "ERROR: Cannot determine format and geometry for image: \"$tempdir/$imagename\"." 2
    read -e -n 1 -p "" answer
    exit 1
  fi
  format=`echo $identify | awk '{print $2}'` || fail
  if [ "$format" = "" ] ; then
    logfile "ERROR: Cannot determine format for image: \"$tempdir/$imagename\"." 2
    read -e -n 1 -p "" answer
    exit 1
  fi
  extension=`echo $format | tr 'A-Z' 'a-z'` || fail
  if [ "$extension" = "" ] ; then
    logfile "ERROR: Cannot determine extension for image: \"$tempdir/$imagename\"." 2
    read -e -n 1 -p "" answer
    exit 1
  fi
  case "$extension" in
    jpeg ) extension=jpg;;
  esac
  geometry=`echo $identify | awk '{print $3}'` || fail
  if [ "$geometry" = "" ] ; then
    logfile "ERROR: Cannot determine geometry for image: \"$tempdir/$imagename\"." 2
    read -e -n 1 -p "" answer
    exit 1
  fi

  # Geometry can be 563x144+0+0 or 75x98
  # we need to get rid of the plus (+) and the x characters:
  width=`echo $geometry | sed 's/[^0-9]/ /g' | awk '{print $1}'` || fail
  if [ "$width" = "" ] ; then
    logfile "ERROR: Cannot determine width for image: \"$tempdir/$imagename\"." 2
    read -e -n 1 -p "" answer
    exit 1
  fi
  height=`echo $geometry | sed 's/[^0-9]/ /g' | awk '{print $2}'` || fail
  if [ "$height" = "" ] ; then
    logfile "ERROR: Cannot determine height for image: \"$tempdir/$imagename\"." 2
    read -e -n 1 -p "" answer
    exit 1
  fi
  newheight=$height
  newwidth=$width

  echo "$format ${width}x${height}"
  
  # Calculate the image number for use in the filename.
  skip=0
  for (( count = 1 ;; count++ ))
  do
    if [ $count -gt 999 ] ; then
      logfile "ERROR: Directory \"$dir\" has more then 999 images. Skipping image \"$tempdir/$imagename\"."; 2
      skip=1
      break
    fi
    imagenumber=`echo $count | awk '{printf("%.3d", $1)}'` || fail
    if [ "$imagenumber" = "" ] ; then
      logfile "ERROR: Cannot format number for image: \"$tempdir/$imagename\"."; 2
      read -e -n 1 -p "" answer
      exit 1
    fi
    newname="img-${date}-${time}-${imagenumber}-${newwidth}x${newheight}.${extension}"
    if [ -f "$destdir/$dir/$newname" ] ; then
      # Make sure we dont overwrite another image.
      md5sum1=`md5sum "$destdir/$dir/$newname" | awk '{print $1}'`
      if [ "$md5sum1" = "" ]; then
        logfile "ERROR: Cannot determine md5sum for image: \"$destdir/$dir/$newname\"." 2
        rm -f "$tempdir/$imagename"
        read -e -n 1 -p "" answer
        exit 1
      fi
      md5sum2=`md5sum "$tempdir/$imagename" | awk '{print $1}'`
      if [ "$md5sum2" = "" ]; then
        logfile "ERROR: Cannot determine md5sum for image: \"$tempdir/$imagename\"." 2
        rm -f "$tempdir/$imagename"
        read -e -n 1 -p "" answer
        exit 1
      fi
      if [ "$md5sum1" = "$md5sum2" ]; then
        # The same image already exist with right filename.
        logfile "Image \"$tempdir/$imagename\" already exist as \"$destdir/$dir/$newname\"." 2
        skip=1
        break
      else
        continue
      fi
    else
      # Found free filename.
      skip=0
      break
    fi
  done
  
  if [ "$skip" = "1" ] ; then
    rm -f "$tempdir/$imagename"
    continue
  fi

  # Create directory

  if [ ! -d "$destdir/$dir" ] ; then
    echo $n "Creating directory \"$destdir/$dir\". $c"
    mkdir $destdir/$dir || {
      rm -f "$tempdir/$imagename";
      read -e -n 1 -p "" answer;
      exit 1;
    }
    echo "Done."
  fi

  # Copy image
 
  echo $n "Copying \"$tempdir/$imagename\" to \"$destdir/$dir/$newname\". $c"
  mv "$tempdir/$imagename" "$destdir/$dir/$newname" || {
    rm -f "$tempdir/$imagename";
    read -e -n 1 -p "" answer;
    exit 1
  }
  echo "Done."
  logfile "Copied \"$tempdir/$imagename\" to \"$destdir/$dir/$newname\"." 1

  if [ "$createmd5sum" = "1" ] ; then
    md5sum "$destdir/$dir/$newname" >>"$destdir/$dir/$dir.md5"
  fi

done

if [ "$automounted" = "1" ]; then
  udisksctl unmount -b $device
fi

echo "Done."

sleep 90d

exit 0
