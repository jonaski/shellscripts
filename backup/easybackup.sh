#!/bin/bash
#
#  easybackup.sh - EASY RSYNC BACKUP SCRIPT
#  Copyright (C) 2011-2026 Jonas Kvinge
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

rsyncargs=(-va --no-specials --delete --delete-excluded --itemize-changes)
logfile=""
logviewer="kate"

backupexclude="\
/lost+found
/tmp
/dev
/proc
/run
/sys
/media
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
/var/lib/systemd/coredump
/var/lib/nscd
/var/log/journal
/var/lib/flatpak
/root/.cache
/root/.local/share/Trash
/*/lost+found
/home/*/.xsession-errors
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
/home/*/.trinity/cache-*
/home/*/.trinity/tmp-*
/home/*/.trinity/socket-*
/home/*/.beagle
/home/*/.pulse-cookie
/home/*/.pulse
/home/*/.xine
/home/*/.mcop
/home/*/.java
/home/*/.adobe
/home/*/.macromedia
/home/*/.opera/cache
/home/*/.mythtv/*cache
/home/*/.xmltv/cache
/home/*/.googleearth
/home/*/.wine
/home/*/.wine_*
/home/*/.kde4/share/apps/nepomuk
/home/*/.kde/share/apps/amarok/albumcovers/cache
/home/*/.local/share/baloo
/home/*/.local/share/claude/versions
/home/*/.dropbox/*_socket
/home/*/.dropbox-dist
/home/*/.nv/ComputeCache
/home/*/.nx/cache
/home/*/.nx/temp
/home/*/.cargo/registry
/home/*/.cargo/git
/home/*/.claude/cache
/home/*/.claude/plugins/cache
/home/*/.claws-mail/imapcache
/home/*/.mozilla/firefox/*/Cache*
/home/*/.thunderbird/*/global-messages-db.sqlite
/home/*/.config/VirtualBox/VBoxGuestAdditions_*.iso
/home/*/.config/chromium/component_crx_cache
/home/*/.config/google-chrome/Cookies*
/home/*/.config/google-chrome/History*
/home/*/.config/google-chrome/Default/Local Storage/*
/home/*/.config/google-chrome/Default/Application Cache
/home/*/.config/google-chrome/OptGuideOnDeviceModel
/home/*/.config/google-chrome/OptGuideOnDeviceClassifierModel
/home/*/.config/google-chrome/optimization_guide_model_store
/home/*/.config/google-chrome/screen_ai
/home/*/.config/google-chrome/component_crx_cache
/home/*/.config/google-chrome/extensions_crx_cache
/home/*/.config/google-chrome/GPUPersistentCache
/home/*/.config/google-chrome/GrShaderCache
/home/*/.config/google-chrome/ShaderCache
/home/*/.config/google-chrome/Crash Reports
/home/*/.config/google-chrome/*/Service Worker/CacheStorage
/home/*/.config/google-chrome/*/Service Worker/ScriptCache
/home/*/.config/google-chrome/*/WebStorage/*/CacheStorage
/home/*/.config/google-chrome/*/Shared Dictionary/cache
/home/*/.config/google-chrome/*/GPUCache
/home/*/.config/google-chrome/*/Cookies*
/home/*/.config/google-chrome/*/History*
/home/*/.config/discord/Cache
/home/*/.config/discord/Code Cache
/home/*/.config/discord/GPUCache
/home/*/.config/discord/component_crx_cache
/home/*/.config/discord/logs
/home/*/.config/Microsoft/Microsoft Teams/Application Cache
/home/*/.config/Microsoft/Microsoft Teams/Cache
/home/*/.config/Microsoft/Microsoft Teams/Code Cache
/home/*/.config/Microsoft/Microsoft Teams/GPUCache
/home/*/.config/GitHub Desktop/Cache
/home/*/.config/GitHub Desktop/Code Cache
/home/*/.config/GitHub Desktop/GPUCache
/home/*/.config/Code/Cache
/home/*/.config/Code/CachedData
/home/*/.config/Code/Code Cache
/home/*/.config/Code/GPUCache
/home/*/.local/share/Trash
/home/*/.local/share/akonadi
/home/*/.local/share/TelegramDesktop/tdata/user_data/cache
/home/*/.local/share/TelegramDesktop/tdata/user_data/media_cache
/home/*/Downloads/**/node_modules/
/home/*/Downloads/**/.next/cache/
/home/*/Projects/**/node_modules/
/home/*/.local/share/flatpak
+ /home/*/.thunderbird/*/ImapMail/*/msgFilterRules.dat
+ /home/*/.thunderbird/*/Mail/*/msgFilterRules.dat
/home/*/.thunderbird/*/ImapMail/*/*
/home/*/.thunderbird/*/ImapMail/*.msf
/home/*/.thunderbird/*/Mail/*/*
/home/*/.thunderbird/*/Mail/*.msf
/home/*/VirtualBox
/mnt/data/Images
/mnt/data/Backup
"

##################### DONT CHANGE ANYTHING BELOW HERE #####################

backup_exclude_escape() {

  # rsync only treats a backslash as an escape if the pattern has a wildcard.
  case "$1" in
    *[*?[]* ) printf '%s' "$1" | sed 's/[][*?\\]/\\&/g';;
    * ) printf '%s' "$1";;
  esac

}

backup_exclude_extra() {

  # These go first in the exclude file, because rsync uses the first rule that matches.
  for extraexclude in "${extraexcludes[@]}"; do
    extraexclude=$(realpath -m -s -- "$extraexclude") || backup_exit 1
    if [ "$extraexclude" = "/" ]; then
      echo "ERROR: Can't exclude /."
      backup_exit 1
    fi
    if ! [ -e "$extraexclude" ]; then
      echo "WARNING: Excluded directory $extraexclude does not exist."
    fi
    echo "Excluding: $extraexclude"
    echo "EXCLUDED (-x): $extraexclude" >>"$logfile"
    backup_exclude_escape "$extraexclude" >>"$backupexcludestmpfile" || backup_exit 1
    echo >>"$backupexcludestmpfile"
    # Without -R, rsync matches from the name of the source directory, not the full path.
    if [ "$relative" = "0" ]; then
      for source in "${backupsources[@]}"; do
        case "$extraexclude" in
          "$source"|"$source"/*)
            backup_exclude_escape "/${source##*/}${extraexclude#"$source"}" >>"$backupexcludestmpfile" || backup_exit 1
            echo >>"$backupexcludestmpfile";;
        esac
      done
    fi
  done

}

backup_exclude_builds() {

  # Root can read everything, other users only search their own home directory.
  if [ "$EUID" -eq 0 ]; then
    buildsearch=/
  else
    buildsearch=$(realpath -- "$HOME") || backup_exit 1
  fi

  echo "Searching for CMake, GNU configure and Meson build directories in $buildsearch."

  buildcount=0
  while IFS= read -r -d '' buildfile; do
    # The second file confirms a real build. Test fixtures may only have the first one.
    case "$buildfile" in
      */CMakeCache.txt)
        builddir=${buildfile%/*}
        buildtype="CMake"
        buildconfirm="$builddir/CMakeFiles";;
      */config.status)
        builddir=${buildfile%/*}
        buildtype="GNU configure"
        buildconfirm="$builddir/config.log";;
      *)
        builddir=${buildfile%/meson-private/coredata.dat}
        buildtype="Meson"
        buildconfirm="$builddir/meson-info";;
    esac
    if ! [ -e "$buildconfirm" ]; then
      continue
    fi
    # A source file here means an in-source build, and the directory also holds source code.
    insource=0
    for sourcefile in CMakeLists.txt meson.build configure configure.ac configure.in; do
      if [ -e "$builddir/$sourcefile" ]; then
        insource=1
      fi
    done
    if [ "$insource" = "1" ]; then
      echo "BUILD KEPT, IN-SOURCE ($buildtype): $builddir" >>"$logfile"
      continue
    fi
    echo "BUILD EXCLUDED ($buildtype): $builddir" >>"$logfile"
    printf '%s/\n' "$(backup_exclude_escape "$builddir")" >>"$backupexcludestmpfile" || backup_exit 1
    buildcount=$((buildcount + 1))
  done < <(find "$buildsearch" \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /tmp -o -name CMakeFiles \) -prune -o -type f \( -name CMakeCache.txt -o -name config.status -o -path '*/meson-private/coredata.dat' \) -print0 2>/dev/null)

  echo "Excluding $buildcount build directories, see logfile: $logfile"

}

backup_cleanup() {

  rm -f "$backupexcludestmpfile"
  backupexcludestmpfile=""
  if [ "$automounted" = "1" ]; then
    automounted=0
    if ! udisksctl unmount -b "$device"; then
      echo "ERROR: Unable to unmount \"$device\"."
      return 1
    fi
  fi
  return 0

}

backup_exit() {

  status=${1:-0}
  if ! backup_cleanup && [ "$status" = "0" ]; then
    status=1
  fi
  read -e -n 1 -p "Press any key to exit..."
  exit "$status"

}

trap 'backup_cleanup; exit 130' INT
trap 'backup_cleanup; exit 143' TERM

# Show the logo.

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
   ░  ░     ░  ░      ░  ░ ░      ░            ░  ░░ ░      ░  ░      ░
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

# Check the system, parse the parameters and create the exclude file.

# Find out how to echo without newline

c=''
n=''
if [ "$(eval echo -n 'a')" = "-n a" ] ; then
  c='\c'
else
  n='-n'
fi

# See if the system has the needed commands to continue.

for cmd in "ls" "rm" "sed" "tee" "tput" "find" "getopt" "mktemp" "realpath" "rsync" "blkid" "findmnt" "udisksctl"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Missing the \"${cmd}\" command!"
    backup_exit 1
  fi
done

# Parse parameters

script=$(echo "$0" | sed 's/.*\///g')

relative=0
extraexcludes=()
parsedargs=$(getopt -o hRcp:l:x: -l help,relative,checksum,backupdir:,logfile:,exclude: -n "$script" -- "$@") || {
  echo "ERROR: Invalid option: $script -h for help."
  backup_exit 1
}
eval set -- "$parsedargs"
while true; do
  case "$1" in
    -h|--help)
      echo "Usage: $script [options] <Source directories> <Backupdisk labels>"
      echo ""
      echo "-h, --help                  Display this help and exit"
      echo "-p, --backupdir <directory> Backup directory on backup disk, ie.: /Backup"
      echo "-l, --logfile <file>        Logfile"
      echo "-x, --exclude <directory>   Exclude this directory, can be used several times, works with and without -R"
      echo "-R, --relative              Relative names (rsync -R), the built-in excludes only apply with this option"
      echo "-c, --checksum              Checksum (rsync -c)"
      echo ""
      echo "Source directories must contain a /, use ./data for a directory in the current directory."
      echo "With -R, sources are stored under their full path on the backup disk, ie.: /mnt/data in <disk>/mnt/data"
      echo ""
      echo "Examples:"
      echo "Source directories = /mnt/data /home/jonas"
      echo "Backupdisk labels = backupdisk1 backupdisk2"
      echo "The script will pick the first disk in the system that matches one of the disklabels."
      echo ""
      exit 0;;
    -p|--backupdir) backupdir="$2"; shift 2;;
    -l|--logfile) logfile="$2"; shift 2;;
    -x|--exclude) extraexcludes+=("$2"); shift 2;;
    -c|--checksum) rsyncargs+=(-c); shift;;
    -R|--relative) rsyncargs+=(-R); relative=1; shift;;
    --) shift; break;;
  esac
done

backupsources=()
backupdisks=()
for param in "$@"; do
  if [[ "$param" == */* ]]; then
    if [ "${#backupdisks[@]}" -gt 0 ]; then
      echo "ERROR: You need to specify backup source directory before backup disk labels."
      backup_exit 1
    fi
    if ! [ -e "$param" ]; then
      echo "ERROR: File $param does not exist!."
      backup_exit 1
    fi
    # The excludes are matched against the full path, and rsync -R treats /./ specially.
    param=$(realpath -s -- "$param")
    # An unmounted source is an empty directory, and --delete would then empty the backup.
    if [ -d "$param" ] && [ -z "$(ls -A -- "$param")" ]; then
      echo "ERROR: Source directory $param is empty or unreadable. Is it mounted?"
      backup_exit 1
    fi
    backupsources+=("$param")
  else
    backupdisks+=("$param")
  fi
done

if [ "${#backupsources[@]}" -eq 0 ]; then
  echo "ERROR: Missing backupsource."
  backup_exit 1
fi
if [ "${#backupdisks[@]}" -eq 0 ]; then
  echo "ERROR: Missing backupdisks."
  backup_exit 1
fi

echo "Source: ${backupsources[*]}"
echo "Backupdisks: ${backupdisks[*]}"

if [ "$logfile" = "" ]; then
  logfile=$(mktemp -t easybackup-XXXXXX.log) || backup_exit 1
fi
backupexcludestmpfile=$(mktemp -t easybackup-excludes-XXXXXX.txt) || backup_exit 1
backup_exclude_extra
echo "$backupexclude" >>"$backupexcludestmpfile" || backup_exit 1
backup_exclude_builds

# Find the backup disk.

device=""

while [ "$device" = "" ]; do
  for label in "${backupdisks[@]}"
  do
    device=$(blkid -L "$label" 2>/dev/null)
    if ! [ "$device" = "" ]; then
      break
    fi
  done
  if [ "$device" = "" ]; then
    read -e -n 1 -p "Insert backupdisk with labels \"${backupdisks[*]}\" and press any key to try again."
  fi
done

echo "Using backupdisk \"$label\": \"$device\"."

# Mount the backup disk and find the backup destination.

automounted=
mountpoint=$(findmnt -n -f -l -o TARGET --source "$device")
if [ "$mountpoint" = "" ]; then
  echo $n "Mounting \"$device\". $c"
  udisksctl mount -b "$device" || {
    echo "ERROR: Unable to mount \"$device\"."
    backup_exit 1
  }
  automounted=1
  # udisks may return 0 even when it's not mounted.
  mountpoint=$(findmnt -n -f -l -o TARGET --source "$device")
  if [ "$mountpoint" = "" ]; then
    echo "Failed to find mountpoint."
    echo "ERROR: Unable to find mountpoint for \"$device\"."
    backup_exit 1
  fi
else
  echo "Probing \"$device\". $mountpoint."
  automounted=0
fi

echo "Device \"$device\" mounted on \"$mountpoint\"."

if [ "$backupdir" = "" ]; then
  backupdst=$mountpoint
else
  if [[ "$backupdir" == /* ]]; then
    backupdst=${mountpoint}${backupdir}
  else
    backupdst=$mountpoint/$backupdir
  fi
  if ! [ -d "$backupdst" ]; then
    echo "Device \"$device\" missing directory \"$backupdir\"."
    backup_exit 1
  fi
fi

while true; do
  read -e -n 1 -p "Use $device (Y/N) " answer
  case $answer in
    [Yy]* ) break;;
    [Nn]* ) backup_exit 1;;
    * ) echo "Invalid answer. Press Y or N.";;
  esac
done

# Confirm the backup destination.

while true; do
  read -e -n 1 -p "Using backup destination $backupdst, EVERYTHING IN THERE MIGHT BE DELETED OR OVERWRITTEN. ARE YOU SURE? (Y/N) " answer
  case $answer in
    [Yy]* ) break;;
    [Nn]* ) backup_exit 1;;
    * ) echo "Invalid answer. Press Y or N.";;
  esac
done

# Dry run, if requested.

dryrun=0
while true; do
  read -e -n 1 -p "DRY RUN first? (Y/N) " answer
  case $answer in
    [Yy]* ) dryrun=1; break;;
    [Nn]* ) break;;
    * ) echo "Invalid answer. Press Y or N.";;
  esac
done

if [ "$dryrun" = "1" ]; then

  while true; do
    read -e -n 1 -p "Running rsync -n ${rsyncargs[*]} --exclude-from=$backupexcludestmpfile ${backupsources[*]} $backupdst (DRY RUN), continue? (Y/N) " answer
    case $answer in
      [Yy]* ) break;;
      [Nn]* ) backup_exit 1;;
      * ) echo "Invalid answer. Press Y or N.";;
    esac
  done

  echo "BACKUPSOURCE: ${backupsources[*]}"
  echo "BACKUPDST: $backupdst"

  echo "COMMAND: rsync -n ${rsyncargs[*]} --exclude-from=$backupexcludestmpfile ${backupsources[*]} $backupdst" >>"$logfile"
  rsync -n "${rsyncargs[@]}" --exclude-from="$backupexcludestmpfile" "${backupsources[@]}" "$backupdst" 2>&1 | tee -a "$logfile"
  rsyncstatus=${PIPESTATUS[0]}
  if [ "$rsyncstatus" = "0" ]; then
    result="Dry run complete"
  else
    result="WARNING: Dry run FAILED (rsync exit code $rsyncstatus)"
  fi

  while true; do
    read -e -n 1 -p "$result, view logfile ($logfile). (Y/N) " answer
    case $answer in
      [Yy]* )
              if command -v "$logviewer" >/dev/null 2>&1; then
                "$logviewer" "$logfile" >/dev/null 2>&1 &
              else
                ${PAGER:-less} "$logfile"
              fi
              break;;
      [Nn]* ) break;;
      * ) echo "Invalid answer. Press Y or N.";;
    esac
  done

  while true; do
    read -e -n 1 -p "$result, continue with these changes?. (Y/N) " answer
    case $answer in
      [Yy]* ) break;;
      [Nn]* ) backup_exit 1;;
      * ) echo "Invalid answer. Press Y or N.";;
    esac
  done

fi

# Run the backup.

while true; do
  read -e -n 1 -p "Run rsync ${rsyncargs[*]} --exclude-from=$backupexcludestmpfile ${backupsources[*]} $backupdst, continue? (Y/N) " answer
  case $answer in
    [Yy]* ) break;;
    [Nn]* ) backup_exit 1;;
    * ) echo "Invalid answer. Press Y or N.";;
  esac
done

echo "COMMAND: rsync ${rsyncargs[*]} --exclude-from=$backupexcludestmpfile ${backupsources[*]} $backupdst" >>"$logfile"
rsync "${rsyncargs[@]}" --exclude-from="$backupexcludestmpfile" "${backupsources[@]}" "$backupdst" 2>&1 | tee -a "$logfile"
rsyncstatus=${PIPESTATUS[0]}
if ! [ "$rsyncstatus" = "0" ]; then
  echo "ERROR: Backup FAILED (rsync exit code $rsyncstatus). See logfile: $logfile"
  backup_exit "$rsyncstatus"
fi

echo "Backup complete. Logfile: $logfile"

# Clean up and exit.

backup_exit 0
