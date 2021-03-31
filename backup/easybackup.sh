#!/bin/sh
#
#  easybackup.sh - EASY RSYNC BACKUP SCRIPT
#  Copyright (C) 2011-2012 Jonas Kvinge
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
# This is a very BASIC terminal rsync backup script.
# You must understand basic shell scripts and rsync.
# Modify it as you wish. USE AT YOUR OWN RISK!!!
#
# rsync options:
#
# Verbose: -v
# Archive: -a (Same as -rlptgoD)
# Recursive: -r
# Checksum: -c
# Time: -t
# Dry run: -n
# Delete: --delete
# Relative path names: -R
#

version="0.2.5"

rsyncargs="-va --delete --delete-excluded --itemize-changes"
rsyncargsdry="-van --delete --delete-excluded --itemize-changes"
logfile="/tmp/easybackup-${RANDOM}.log"
backupexclude="\
/tmp
/dev
/proc
/run
/sys
/media
/lost+found
/var/cache
/var/tmp
/var/run
/var/spool/postfix/private
/var/spool/postfix/public
/var/lib/named/lib
/var/lib/named/proc
/var/lib/named/var
/var/lib/named/dev
/var/lib/mysql/mysql.sock
/var/lib/ntp/proc
/var/lib/ntp/dev
/var/lib/dhcp/dev
/var/lib/dhcp/proc
/var/lib/dhcp6/dev
/var/lib/dhcp6/proc
/home/*/.xsession-errors
/home/*/.local/share/Trash
/home/*/.local/share/akonadi
/home/*/.config/google-chrome/Default/Local Storage/*
/home/*/.config/google-chrome/Cookies*
/home/*/.config/google-chrome/History*
/home/*/.config/google-chrome/Default/Application Cache
/home/*/.cache
/home/*/.thumbnails
/home/*/.qt
/home/*/.gvfs
/home/*/.dbus
/home/*/.netx
/home/*/.kde/cache-*
/home/*/.kde/tmp-*
/home/*/.kde/socket-*
/home/*/.kde4/cache-*
/home/*/.kde4/tmp-*
/home/*/.kde4/socket-*
/home/*/.beagle
/home/*/.pulse-cookie
/home/*/.pulse
/home/*/.xine
/home/*/.mcop
/home/*/.java
/home/*/.adobe
/home/*/.macromedia
/home/*/.mozilla/firefox/*/Cache*
/home/*/.opera/cache
/home/*/.mythtv/*cache
/home/*/.xmltv/cache
/home/*/.googleearth
/home/*/.wine
/home/*/.wine_*
/home/*/.kde4/share/apps/nepomuk
/home/*/.kde/share/apps/amarok/albumcovers/cache
/home/*/VirtualBox
/mnt/data/Images
/mnt/data/Backup
/mnt/data/Xerox
"

##################### DONT CHANGE ANYTHING BELOW HERE #####################

backup_logo() {

  tput bold
  tput setaf 7

  echo "
▓█████ ▄▄▄        ██████▓██   ██▓ ▄▄▄▄    ▄▄▄       ▄████▄   ██ ▄█▀ █    ██  ██▓███
▓█   ▀▒████▄    ▒██    ▒ ▒██  ██▒▓█████▄ ▒████▄    ▒██▀ ▀█   ██▄█▒  ██  ▓██▒▓██░  ██▒
▒███  ▒██  ▀█▄  ░ ▓██▄    ▒██ ██░▒██▒ ▄██▒██  ▀█▄  ▒▓█    ▄ ▓███▄░ ▓██  ▒██░▓██░ ██▓▒
▒▓█  ▄░██▄▄▄▄██   ▒   ██▒ ░ ▐██▓░▒██░█▀  ░██▄▄▄▄██ ▒▓▓▄ ▄██▒▓██ █▄ ▓▓█  ░██░▒██▄█▓▒ ▒
░▒████▒▓█   ▓██▒▒██████▒▒ ░ ██▒▓░░▓█  ▀█▓ ▓█   ▓██▒▒ ▓███▀ ░▒██▒ █▄▒▒█████▓ ▒██▒ ░  ░
░░ ▒░ ░▒▒   ▓▒█░▒ ▒▓▒ ▒ ░  ██▒▒▒ ░▒▓███▀▒ ▒▒   ▓▒█░░ ░▒ ▒  ░▒ ▒▒ ▓▒░▒▓▒ ▒ ▒ ▒▓▒░ ░  ░
 ░ ░  ░ ▒   ▒▒ ░░ ░▒  ░ ░▓██ ░▒░ ▒░▒   ░   ▒   ▒▒ ░  ░  ▒   ░ ░▒ ▒░░░▒░ ░ ░ ░▒ ░
   ░    ░   ▒   ░  ░  ░  ▒ ▒ ░░   ░    ░   ░   ▒   ░        ░ ░░ ░  ░░░ ░ ░ ░░
   ░  ░     ░  ░      ░  ░ ░      ░            ░  ░░ ░      ░  ░      ░ v${version}
                         ░ ░           ░           ░

"
  
#echo "
#███████╗ █████╗ ███████╗██╗   ██╗██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗ 
#██╔════╝██╔══██╗██╔════╝╚██╗ ██╔╝██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗
#█████╗  ███████║███████╗ ╚████╔╝ ██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝
#██╔══╝  ██╔══██║╚════██║  ╚██╔╝  ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝ 
#███████╗██║  ██║███████║   ██║   ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║     
#╚══════╝╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝                                                                                      
#"

  tput sgr0

}

backup_init() {

  # Find out how to echo without newline

  c=''
  n=''
  if [ "$(eval echo -n 'a')" = "-n a" ] ; then
    c='\c'
  else
    n='-n'
  fi

  # See if the system has the needed commands to continue.

  for cmd in "which" "ls" "mkdir" "mv" "cp" "rm" "sed" "awk" "bc" "tr" "date" "md5sum" "udisksctl" "mount" "blkid"
  do
    which $cmd >/dev/null 2>&1
    if [ $? != 0 ] ; then
      echo "ERROR: Missing the \"${cmd}\" command!"
      backup_exit
      exit 1
    fi
  done

  # Parse parameters

  script=$(echo "$0" | sed 's/.*\///g')

  while getopts hvRcp:l: o
  do case "$o" in
    h)  echo "Usage: $script -hvdpl <Source directories> <Backupdisk labels>"
        echo ""
        echo "-h     Display this help and exit"
        echo "-v     Display script version and exit"
        echo "-p     Backup directory on backup disk, ie.: /Backup"
        echo "-l     Logfile"
        echo "-R     Relative names (rsync -R)"
        echo "-c     Checksum (rsync -c)"
        echo ""
        echo "Examples:"
        echo "Source directories = /mnt/data /home/jonas"
        echo "Backupdisk labels = backupdisk1 backupdisk2"
        echo "The script will pick the first disk in the system that matches one of the disklabels."
        echo ""
        exit 0;;
    v)  echo "$script v$version"; backup_exit; exit 0;;
    p)  backupdir="$OPTARG";;
    l)  logfile="$OPTARG";;
    c)  rsyncargs="$rsyncargs -c"; rsyncargsdry="$rsyncargsdry -c";;
    R)  rsyncargs="$rsyncargs -R"; rsyncargsdry="$rsyncargsdry -R";;
    \?)  echo "ERROR: Unknown option: $script -h for help."; backup_exit; exit 1;;
  esac
  done
  # Reset $@
  shift "$(echo $OPTIND-1 | bc)"
  
  params="$*"
  for param in $params ; do    
    echo "$param" | grep '/' >/dev/null 2>&1
    if [ $? = 0 ]; then
      if ! [ "$backupdisks" = "" ]; then
        echo "ERROR: You need to specify backup source directory before backup disk labels."
        backup_exit
        exit 1
      fi
      ls "$param" >/dev/null 2>&1
      if ! [ $? -eq 0 ] ; then
        echo "ERROR: File $param does not exist!."
        backup_exit
        exit 1
      fi
      if [ "$backupsource" = "" ]; then
        backupsource=$param
      else
        backupsource="$backupsource $param"
      fi
    else
      if [ "$backupdisks" = "" ]; then
        backupdisks=$param
      else
        backupdisks="$backupdisks $param"
      fi
    fi
  done

  if [ "$backupsource" = "" ]; then
    echo "ERROR: Missing backupsource."
    backup_exit
    exit 1
  fi
  if [ "$backupdisks" = "" ]; then
    echo "ERROR: Missing backupdisks."
    backup_exit
    exit 1
  fi
  backupsource="$backupsource /dev/null"

  echo "Source: $backupsource"
  echo "Backupdisks: $backupdisks"

  rm -f "$backupexcludestmpfile"
  
  backupexcludestmpfile="/tmp/easybackup-excludes-${RANDOM}.txt"
  echo "$backupexclude" >$backupexcludestmpfile || { backup_exit; }

}

backup_device() {

  found=0

  while true; do
    for i in $backupdisks
    do
      IFS=$'\n'
      for x in $(blkid)
      do
        device=$(echo "$x" | awk '{print $1}' | sed 's/://g')
        label=$(echo "$x" | awk '{print $2}')
        echo "$label" | grep '^LABEL=".*"$' >/dev/null 2>&1
        if ! [ $? = 0 ]; then
          continue
        fi
        label=$(echo "$label" | sed 's/LABEL=//g' | sed 's/"//g')
        if [ "$label" = "$i" ]; then
          found=1
          break
        fi
      done
      IFS=$' \t\n'
      if [ "$found" = "1" ]; then
        break
      fi
    done
    if ! [ "$found" = "1" ]; then
      read -e -n 1 -p "Insert backupdisk with labels \"$backupdisks\" and press any key to try again."
      continue
    fi
    break
  done

  echo "Using backupdisk \"$label\": \"$device\"."

}

backup_mount() {

  mountpoint=
  mounted=
  automounted=
  mount=$(mount | grep "^${device}")
  if [ "$mount" = "" ]; then
    echo $n "Mounting \"$device\". $c"
    udisksctl mount -b "$device" || {
      echo "ERROR: Unable to mount \"$device\"."
      backup_exit
      exit 1
    }
    # udisks may return 0 even when it's not mounted.
    mount=$(mount | grep ^${device}.*)
    if [ "$mount" = "" ]; then
      echo "Failed."
      backup_exit
      exit 1
    fi
    mountpoint=$(echo "$mount" | awk '{print $3}')
    if [ "$mountpoint" = "" ]; then
      echo "Failed to find mountpoint."
      echo "ERROR: Unable to find mountpoint for \"$device\"."
      backup_exit
      exit 1
    fi
    automounted=1
    #echo "$mountpoint."
  else
    echo $n "Probing \"$device\". $c"
    mountpoint=$(echo "$mount" | awk '{print $3}')
    if [ "$mountpoint" = "" ]; then
      echo "Failed to find mountpoint."
      echo "ERROR: Unable to find mountpoint for \"$device\"."
      backup_exit
      exit 1
    fi
    echo "$mountpoint."
    automounted=0
  fi

  echo "Device \"$device\" mounted on \"$mountpoint\"."
  mounted=1
  
  if [ "$backupdir" = "" ]; then
    backupdst=$mountpoint
  else
    echo "$backupdir" | grep '^/.*$' >/dev/null 2>&1
    if [ $? = 0 ]; then
      backupdst=${mountpoint}${backupdir}
    else
      backupdst=$mountpoint/$backupdir
    fi
    if ! [ -d "$backupdst" ]; then
      echo "Device \"$device\" missing directory \"$backupdir\"."
      backup_exit
      exit 1
    fi
  fi

  while true; do
    read -e -n 1 -p "Use $device (Y/N) " answer
    case $answer in
        [Yy]* ) answer=1;break;;
        [Nn]* ) answer=0;break;;
        * ) echo "Invalid answer. Press Y or N.";;
    esac
    if [ "$answer" = "0" ]; then
      backup_exit
      exit 1
    fi
    break
  done

}

backup_dryrun() {

  while true; do
    read -e -n 1 -p "DRY RUN first? (Y/N) " answer
    case $answer in
      [Yy]* ) break;;
      [Nn]* ) return 0;;
      * ) echo "Invalid answer. Press Y or N.";;
    esac
  done

  while true; do
    read -e -n 1 -p "Running rsync -n "$rsyncargsdry" --exclude-from="$backupexcludestmpfile" $backupsource $backupdst (DRY RUN), continue? (Y/N) " answer
    case $answer in
      [Yy]* ) break;;
      [Nn]* ) backup_exit; exit 1;;
      * ) echo "Invalid answer. Press Y or N.";;
    esac
  done

  echo "BACKUPSOURCE: $backupsource"
  echo "BACKUPDST: $backupdst"

  echo "COMMAND: rsync -n $rsyncargsdry --exclude-from=$backupexcludestmpfile $backupsource $backupdst" >>"$logfile"
  rsync -n $rsyncargsdry --exclude-from="$backupexcludestmpfile" "$backupsource" "$backupdst" 2>&1 | tee -a "$logfile"

  while true; do
    read -e -n 1 -p "Dry run complete, view logfile ($logfile). (Y/N) " answer
    case $answer in
      [Yy]* )
              kate "$logfile" >/dev/null 2>&1 &
              break;;
      [Nn]* ) break;;
      * ) echo "Invalid answer. Press Y or N.";;
    esac
  done

  while true; do
    read -e -n 1 -p "Dry run complete, continue with these changes?. (Y/N) " answer
    case $answer in
      [Yy]* ) break;;
      [Nn]* ) backup_exit; exit 1;;
      * ) echo "Invalid answer. Press Y or N.";;
    esac
  done

  return 0

}

backup_run() {

  while true; do
    read -e -n 1 -p "Run rsync $rsyncargs --exclude-from="$backupexcludestmpfile" $backupsource $backupdst, continue? (Y/N) " answer
    case $answer in
      [Yy]* ) break;;
      [Nn]* ) backup_exit; exit 1;;
      * ) echo "Invalid answer. Press Y or N.";;
    esac
  done

  echo "COMMAND: rsync $rsyncargs --exclude-from=$backupexcludestmpfile $backupsource $backupdst" >>"$logfile"
  rsync "$rsyncargs" --exclude-from="$backupexcludestmpfile" "$backupsource" "$backupdst" 2>&1 | tee -a "$logfile"

  return 0

}

backup_confirm() {

  while true; do
    read -e -n 1 -p "Using backup destination $backupdst, EVERYTHING IN THERE MIGHT BE DELETED OR OVERWRITTEN. ARE YOU SURE? (Y/N) " answer
    case $answer in
      [Yy]* ) break;;
      [Nn]* ) backup_exit; exit 1;;
      * ) echo "Invalid answer. Press Y or N.";;
    esac
  done

  return 0

}

backup_exit() {

  rm -f $backupexcludestmpfile
  if [ "$automounted" = "1" ]; then
    umount "$device"
  fi
  read -e -n 1 -p "Press any key to exit..."
  exit 0

}

backup_logo || exit 1
backup_init "$@" || exit 1
backup_device || exit 1
backup_mount || exit 1
backup_confirm || exit 1
backup_dryrun || exit 1
backup_run || exit 1
backup_exit || exit 1
