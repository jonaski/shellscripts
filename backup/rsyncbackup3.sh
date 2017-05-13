#!/bin/sh
#
#  rsyncbackup3.sh - RSYNC BACKUP SCRIPT
#  Copyright (C) 2011-2017 Jonas Kvinge
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
#  $Id$
#
#  MAKE SURE YOU UNDERSTAND THIS SCRIPT BEFORE YOU USE IT!
#  I AM NOT RESPONSIBLE FOR LOSS OF DATA!
#
#  To backup daily and name the backups after the current days
#  you can create a crontab entry to run the days you want and
#  set:
#  backuparchives="Day`date '+%w'`"
#
#  Settings "backuparchives" to "" will rsync the files directly
#  into the path sepcified in backuplocation.
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

backupversion="3.2.1"
backupconfig="/etc/sysconfig/rsyncbackup3"

#
# All variables below will be overwritten by the configuration file.
# To configure this script, copy what you want to change below and put it in a seperate file, ie: /etc/sysconfig/rsyncbackup3
#

backuphost="`hostname -s`"							# <--- Hostname of this machine --->
backuplockfiledir="$HOME"							# <--- Lockfile to prevent multiple occurrences of the script running at the same time --->
backuplockfilettl=172800
backuplogfile="/var/log/rsyncbackup3.log"					# <--- Logfile, this will be the same output as sent in e-mail reports --->
backuplogdir="/tmp"								# <--- Directory to temporary store rsync log files --->
backupdate="`date '+%Y%m%d-%H%M%S'`"						# <--- Datestamp --->
backupdebug=0									# <--- Debug output, starting script with -d will set this to 1 --->

backuparchives=3                                                                # <--- Number of archives --->
#backuparchivedir="Day`date '+%w'`"
backuparchivedir="`date '+%Y%m%d'`"                                             # <--- Random archive dir -->

# If backuparchivedirs is set, it will use only these directories instead of renamed directories
#backuparchivedirs="backup1 backup2 backup3"					# <--- Subdirs of backupdir, the script will loop through these and update the oldest archive --->

# Arguments to rsync command

# Dry run
backuprsyncargs="-vaRn --itemize-changes --delete --delete-excluded"

# Archive
#backuprsyncargs="-vaR --itemize-changes --delete --delete-excluded"

# Checksum
#backuprsyncargs="-vacR --itemize-changes --delete --delete-excluded"

backupsshfsargs=""								# <--- Arguments to sshfs command --->
backupsshargs=""								# <--- Arguments to ssh command --->

backupidfile=".RSYNCBACKUPID"							# <--- File touched to identify that the directory is a valid archive --->
backuptsfile="RSYNCBACKUPTS"							# <--- Timestamp file placed in the archive directory to track which directory was used last time, HIDDEN FILE WONT WORK! --->
backupid=$(date '+%Y%m%d%H%M%S')
backupts=$(date '+%Y%m%d%H%M%S')

backupemailfrom="nobody"							# <--- From address to send backup reports from --->
backupemailsuccess="root"							# <--- Where to send backup report, set to "0" for no report --->
backupemailfailure="root"							# <--- Where to send backup report, set to "0" for no report --->

backupmntdir="$HOME/tmp-mnt-$RANDOM"						# <--- Where to mount --->

backupgziplog=1									# <--- Compress logfile --->

backupsourceretries=3								# <--- Times to retry if there is an error --->
backupsourceretrydelay=3							# <--- Time to sleep between each retry attempt if there is an error --->
backupsourceretryttl=60								# <--- Maximum time to attempt backup source before giving up --->
backupsourceconnectdelay=10							# <--- Time to sleep between each connect attempt if there is an error --->
backupsourceconnectttl=172800							# <--- How long time in seconds to wait for a host to come online before giving up --->

# One or more sources that you want to backup.
# Syntax are, Local: /home or SSH(SFTP): host:/home
# Use comma to seperate each file/directory to backup.
# Files/directories specified with '-' in front will be exceptions.

backupsources="\
server:		/etc,/var,/srv,/home,/usr/local,/tmp,-/mnt/backup
pc:		/etc,/var,/srv,/home,/usr/local,/mnt/datadisk,/tmp,-/mnt/backup
"

# One or more destinations where you want to backup files to.

# This can be locally, via ssh/sftp, or via smb.
# Syntax are, Local: /mnt/backup, SSH(SFTP): host:/mnt/backup, SMB: smb://user:pass@host/dir
# If the directory starts with /mnt or /media and is not mounted it will be automatically mounted and umounted.

backupdestinations="\
$backuphost:/mnt/backup/rbackup
"

# Enter files to exclude here, like temp files and sockets

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
/mnt/*/backup*
/mnt/*/Backup*
/home/*/temp
/home/*/Temp
/home/*/backup
/home/*/Backup
/home/*/build
/home/*/.xsession-errors*
/home/*/.local/share/Trash
/home/*/.local/share/akonadi
/home/*/.cache
/home/*/.thumbnails
/home/*/.qt
/home/*/.gvfs
/home/*/.dbus
/home/*/.netx
/home/*/.beagle
/home/*/.pulse-cookie
/home/*/.pulse
/home/*/.xine
/home/*/.mcop
/home/*/.java
/home/*/.adobe
/home/*/.macromedia
/home/*/.config/google-chrome/Default/Local Storage/*
/home/*/.config/google-chrome/Cookies*
/home/*/.config/google-chrome/History*
/home/*/.config/google-chrome/Default/Application Cache
/home/*/.mozilla/firefox/*/Cache*
/home/*/.opera/cache
/home/*/.mythtv/*cache
/home/*/.xmltv/cache
/home/*/.googleearth
/home/*/.wine
/home/*/.wine_*
/home/*/.kde/cache-*
/home/*/.kde/tmp-*
/home/*/.kde/socket-*
/home/*/.kde4/cache-*
/home/*/.kde4/tmp-*
/home/*/.kde4/socket-*
/home/*/.kde4/share/apps/nepomuk
/home/*/.kde/share/apps/amarok/albumcovers/cache
"

# Variables - Don't change this.

cmds_required="which tput cat cut tr sed grep wc bc cp mv rm mkdir rmdir touch md5sum date hostname mutt mount umount mountpoint fusermount ssh sshfs rsync"
cmds_prefergnu="ls cat cut grep sed tr touch"
cmds_requiregnu="ls"

TPUT=dummy
MUTT=dummy
LS="ls"
TR="tr"
CAT="cat"
CUT="cut"
SED="sed"
AWK="awk"
GREP="grep"
TOUCH="touch"

# Functions below here

dummy() { echo "">/dev/null; }
timestamp() { TS=$(date '+%d/%m-%Y %H:%M:%S'); }

print() {
  timestamp
  if [ -t 1 ] && ! [ "$color" = "" ]; then
    $TPUT bold
    $TPUT setaf $color
  fi
  echo "[$TS] $@"
  if [ -t 1 ]; then
    $TPUT sgr0
  fi
  color=0
}
errorprint() {
  timestamp
  if [ -t 1 ]; then
    $TPUT bold
    $TPUT setaf 1
  fi
  echo "[$TS] ERROR: $@" >&2
  if [ -t 1 ]; then
    $TPUT sgr0
  fi
  color=0
}
nnprint() {
  timestamp
  if [ -t 1 ]; then
    $TPUT bold
    $TPUT setaf 0
  fi
  echo $n "[$TS] $@ $c"
  if [ -t 1 ]; then
    $TPUT bold
    $TPUT setaf 1
  fi
}
failprint() {
  if [ -t 1 ]; then
    $TPUT bold
    $TPUT setaf 1
  fi
}
successprint() {
  if [ -t 1 ]; then
    $TPUT bold
    $TPUT setaf 2
  fi
  echo "Done."
  if [ -t 1 ]; then
    $TPUT sgr0
  fi
}
startprint() { failprint; }
stopprint() {
  if [ -t 1 ]; then
    $TPUT sgr0
  fi
}

log() {
  timestamp
  log="$log
  [$TS] $@"
  logall="$logall
  [$TS] $@"
  if [ "$haveconfig" -eq 1 ]; then
    echo "[$TS] $@" >>$backuplogfile
  fi
}
debuglog() {
  timestamp
  debuglog="$debuglog
  [$TS] [DEBUG] $@"
}

status() { statusprint $@; statuslog $@; }
statusnn() { nnprint $@; statuslog $@; }
result() { resultprint $@; resultlog $@; }
info() { infoprint $@; infolog $@; }
warn() { warnprint $@; warnlog $@; }
error() { errorprint $@; errorlog $@; }
debug() {
  if [ "$backupdebug" = "1" ]; then
    debugprint $@
    debuglog $@
  fi
}

statusprint() { color=0; print $@; }
resultprint() { color=2; print $@; }
infoprint() { color=7; print $@; }
warnprint() { color=3; print "WARN: $@"; }
debugprint() { color=4; print "[DEBUG] $@"; }

statuslog() { log $@; }
resultlog() { log $@; }
infolog() { log $@; }
warnlog() { log "WARN: $@"; }
errorlog() { log "ERROR: $@"; }

prnlognts() {
  echo $@
  log="$log
  $@"
  logall="$logall
  $@"
}

run() {

  info "- $@"
  $@
  ret=$?
  if ! [ $? = 0 ]; then
    error "$@ failed!"
  fi
  return $ret
  
}

main() {
  backup_init $@
}

backup_logo() {

  $TPUT bold
  $TPUT setaf 7
  #echo "  _   __          _  _        _         _  "
  #echo " |_) (_ \_/ |\ | /  |_)  /\  /  |/ | | |_) "
  #echo " | \ __) |  | \| \_ |_) /--\ \_ |\ |_| |   "
  echo "  ___  _____   ___  _  ___ ___   _   ___ _  ___   _ ___"
  echo " | _ \/ __\ \ / / \| |/ __| _ ) /_\ / __| |/ / | | | _ \\"
  echo " |   /\__ \\\\ V /| .\` | (__| _ \/ _ \ (__| ' <| |_| |  _/"
  echo " |_|_\|___/ |_| |_|\_|\___|___/_/ \_\___|_|\_\\\\___/|_|"
  $TPUT sgr0
  $TPUT setaf 7
  echo " v$backupversion"
  echo ""
  $TPUT sgr0

}

backup_init() {

  lockfile=0
  mntdir=0
  haveconfig=0
  backuprun=0

  backup_logo
  info "Command: $0 $@"

  backup_chkcmds

  # Find out how to echo without newline

  c=''
  n=''
  if [ "`eval echo -n 'a'`" = "-n a" ] ; then
    c='\c'
  else
    n='-n'
  fi

  # Parse parameters

  script=$(echo "$0" | $SED 's/.*\///g')
  runpath=$(echo "$0" | $SED 's/\(.*\)\/.*/\1/')
  while getopts c:hvdR o
  do case "$o" in
    c)  backupconfig="$OPTARG";;
    h)  prnlognts "Usage: $script -hvdR -c <config>"; exit 0;;
    v)  prnlognts "$script v$backupversion"; exit 0;;
    d)  backupdebug=1;;
    R)  backuprun=1;;
    \?)  prnlognts "ERROR: Unknown option: $script -h for help."; backup_failure_report_all; exit 1;;
  esac
  done

  # Reset $@
  shift `echo $OPTIND-1 | bc`
  
  # Load configuration

  backup_loadconf

  # Initialize logfile

  $TOUCH $backuplogfile || { backup_failure_report_all; exit_failure; }
  echo "$log" >>$backuplogfile || { backup_failure_report_all; exit_failure; }

  # Check if script is already running

  backuplockfile="${backuplockfiledir}/RSYNCBACKUP-LOCKFILE-$(echo $backupconfig | $SED 's/\//-/g' | $SED 's/ /-/g' | $SED 's/\./-/g').lock"
  backuplockfile=$(echo $backuplockfile | $SED 's/--/-/g')

  which lockfile >/dev/null 2>&1
  if [ $? -eq 0 ] ; then
    lockfile -r 0 -l $backuplockfilettl $backuplockfile
    if ! [ $? -eq 0 ] ; then
      error "Script is already running. If this is incorrect, remove: $backuplockfile."
      backup_failure_report_all
      exit_failure
    fi
  else
    if [ -f "$backuplockfile" ]; then
      error "Script is already running. If this is incorrect, remove: $backuplockfile."
      backup_failure_report_all
      exit_failure
    fi
    $TOUCH $backuplockfile || { backup_failure_report_all; exit_failure; }
  fi
  lockfile=1
  
  mkdir -p $backupmntdir || { backup_failure_report_all; exit_failure; }
  mntdir=1

  # Loop sources
  backup_source_loop

  if [ "$sources_failure" -gt 0 ] ; then
    exit_failure
  else
    exit_success
  fi

}

backup_chkcmds() {

  #  Make sure $cmds_required contain all commands

  if ! [ "$cmds_requiregnu" = "" ]; then
    for cmd1 in $cmds_requiregnu
    do
      found=0
      for cmd2 in $cmds_required
      do
        if [ "$cmd1" = "$cmd2" ]; then
          found=1
          break
	fi
      done
      if ! [ "$found" -eq 1 ]; then
        cmds_required="$cmds_required $cmd1"
      fi
    done
  fi

  if ! [ "$cmds_prefergnu" = "" ]; then
    for cmd1 in $cmds_prefergnu
    do
      found=0
      for cmd2 in $cmds_required
      do
        if [ "$cmd1" = "$cmd2" ]; then
          found=1
          break
	fi
      done
      if ! [ "$found" -eq 1 ]; then
        cmds_required="$cmds_required $cmd1"
      fi
    done
  fi
  
  #  Check that we got all the needed commands

  for cmd in $cmds_required
  do
    which $cmd >/dev/null 2>&1
    if ! [ $? -eq 0 ] ; then
      error "Missing \"${cmd}\" command!"
      backup_failure_report_all
      exit_failure
    fi

    prefergnu=0
    requiregnu=0
    if ! [ "$cmds_prefergnu" = "" ]; then
      for cmd2 in $cmds_prefergnu
      do
        if [ "$cmd" = "$cmd2" ]; then
          prefergnu=1
          break
        fi
      done
    fi
    if ! [ "$cmds_requiregnu" = "" ]; then
      for cmd2 in $cmds_requiregnu
      do
        if [ "$cmd" = "$cmd2" ]; then
          requiregnu=1
          break
        fi
      done
    fi

    found=0
    gnu=0
    CMD=$(echo "$cmd" | tr /a-z/ /A-Z/)
    paths=$(echo $PATH | $SED 's/:/ /g')
    for path in $paths
    do
      cmdpath=$path/$cmd
      if ! [ -x "$cmdpath" ]; then
        continue
      fi
      if ! [ "$found" -eq 1 ]; then
        eval ${CMD}="$cmdpath"
      fi
      found=1
      if ! [ "$prefergnu" -eq 1 ]; then
        break
      fi
      
      # Check that we got the GNU version of the command
    
      result=$($cmdpath --version 2>&1 | head -n1)
      if ! [ $? -eq 0 ] ; then
        continue
      fi
      echo "$result" | $GREP "^.* (GNU coreutils) .*$" >/dev/null 2>&1
      if ! [ $? -eq 0 ] ; then
        echo "$result" | $GREP "^.* (GNU ${cmd}) .*$" >/dev/null 2>&1
	if ! [ $? -eq 0 ] ; then
          continue
	fi
      fi
      gnu=1
      eval ${CMD}="$cmdpath"
      break
    done
    if ! [ "$found" -eq 1 ]; then
      error "Missing \"${cmd}\" command!"
      backup_failure_report_all
      exit_failure
    fi
    if [ "$requiregnu" -eq 1 ] && ! [ "$gnu" -eq 1 ]; then
      error "Missing GNU version of \"${cmd}\" command!"
      backup_failure_report_all
      exit_failure
    fi
  done
  
}

backup_loadconf() {

  # Locate configuration file

  if [ "$backupconfig" = "" ] ; then
    backupconfig="/etc/sysconfig/rsyncbackup3"
  fi

  # Check for existence of needed config file and read it

  if ! [ -f "$backupconfig" ]; then
    error "Backup configuration file \"$backupconfig\" does not exist!"
    backup_failure_report_all
    exit_failure
  fi

   if ! [ -r "$backupconfig" ]; then
    error "Unable to read configuration file \"$backupconfig\"."
    backup_failure_report_all
    exit_failure
  fi
  
  info "Configuration: $backupconfig"

  . $backupconfig || {
    error "Failed to load configuration file \"$backupconfig\"."
    backup_failure_report_all
    exit_failure
  }


  # Check that we got the configuration needed

  for i in \
  "backupconfig" \
  "backuphost" \
  "backuplockfiledir" \
  "backuplockfilettl" \
  "backuplogfile" \
  "backupdate" \
  "backuprsyncargs" \
  "backupidfile" \
  "backuptsfile" \
  "backupid" \
  "backupts" \
  "backupemailfrom" \
  "backupemailsuccess" \
  "backupemailfailure" \
  "backupsources" \
  "backupdestinations" \
  "backupexclude" \
  "backuparchives" \
  "backuparchivedir" \
  "backupmntdir" \
  "backuplogdir" \
  "backupgziplog" \
  "backupsourceretries" \
  "backupsourceretrydelay" \
  "backupsourceretryttl" \
  "backupsourceconnectdelay" \
  "backupsourceconnectttl"
  
  do
    if [ "${!i}" = "" ]; then
      error "Missing configuration variable \"$i\" in $backupconfig!"
      backup_failure_report_all
      exit_failure
    fi
  done

  # Set variables
  
  haveconfig=1

  myhostshort="`hostname -s`"
  myhostlong="`hostname`"

  backupexcludeoneline=$(echo "$backupexclude" | tr '\n' ' ' | $SED -e 's/^ //g' | $SED -e 's/  / /g')
  
  #backupsources=$(echo "$backupsources" | $SED -e 's/ //g' | $SED -e 's/\t//g')
  #backupsources=$(echo "$backupsources" | tr '\n' ' ' | $SED -e 's/^ //g' | $SED -e 's/  / /g')
  backupsources=$(echo "$backupsources" | tr -d ' ' | tr -d '\t')
  backupsources=$(echo "$backupsources" | tr '\n' ' ')

  #backupdestinations=$(echo "$backupdestinations" | $SED -e 's/ //g' | $SED -e 's/\t//g')
  #backupdestinations=$(echo "$backupdestinations" | tr '\n' ' ' | $SED -e 's/^ //g' | $SED -e 's/  / /g')
  backupdestinations=$(echo "$backupdestinations" | tr -d ' ' | tr -d '\t')
  backupdestinations=$(echo "$backupdestinations" | tr '\n' ' ')
  
  sources_success=0
  sources_failure=0
  
  destinations_success=0
  destinations_failure=0

  debug "backupsources: $backupsources"
  debug "backupdestinations: $backupdestinations"
  debug "backupexcludeoneline: $backupexcludeoneline"

}

backup_source_loop() {

  sources_total=$(echo $backupsources | wc -w)
  sources_finished=0

  while [ "$sources_finished" -lt "$sources_total" ]
  do
    source_index=0
    for backupsource in $backupsources
    do

      source_index=$(echo $source_index + 1 | bc)
      
      sourcehost=
      sourceuser=
      sourcefiles=
      sourcemountpoint=
      sourceexcludes=
      log=${source_log[$source_index]}

      if ! [ "${source_finished[$source_index]}" = "" ] && [ "${source_finished[$source_index]}" -eq 1 ]; then
        continue
      fi
      if [ "${source_count[$source_index]}" = "" ]; then
        source_count[$source_index]=1
        sourcecount=${source_count[$source_index]}
        source_timestart[$source_index]=`date +%s`
      else
        source_count[$source_index]=$(echo ${source_count[$source_index]} + 1 | bc)
        sourcecount=${source_count[$source_index]}
      fi

      ret=
      echo $backupsource | $GREP '^\/' >/dev/null 2>&1
      if [ $? -eq 0 ]; then # Local
        backup_source_local
        ret=$?
      fi
      echo $backupsource | $GREP '.*:\/' >/dev/null 2>&1
      if [ $? -eq 0 ]; then # SSH
        backup_source_ssh
        ret=$?
      fi

      if [ "$ret" = "" ]; then
        source_finished[$source_index]=1
        sources_finished=$(echo $sources_finished + 1 | bc)
        sources_failure=$(echo $sources_failure + 1 | bc)
        error "Unknown backup source: \"$backupsource\""
        sourcehost=$backupsource
        if ! [ "$backupemailfailure" = "0" ]; then
          backup_source_failure_report
        fi
        continue
      elif [ "$ret" -eq 0 ]; then
        backup_dest_loop
        if [ "$destinations_success" -gt 0 ]; then
          source_finished[$source_index]=1
          sources_finished=$(echo $sources_finished + 1 | bc)
          sources_success=$(echo $sources_success + 1 | bc)
          continue
        fi
      fi
      timenow=`date +%s`
      time=$(echo $timenow - ${source_timestart[$source_index]} | bc)
      if [ "${source_count[$source_index]}" -ge "$backupsourceretries" ] || [ "$time" -ge "$backupsourceretryttl" ]; then
        source_finished[$source_index]=1
        sources_finished=$(echo $sources_finished + 1 | bc)
        sources_failure=$(echo $sources_failure + 1 | bc)
        if ! [ "$backupemailfailure" = "0" ]; then
          backup_source_failure_report
        fi
        continue
      fi
      source_log[$source_index]=$log
      continue

    done
  done

  if [ "$sources_failure" -eq 0 ] ; then
    return 0
  else
    return 1
  fi

}

backup_source_local() {

  if [ "$sourcehost" = "" ]; then
    sourcehost="`hostname -s`"
  fi
  if [ "$sourcefiles" = "" ]; then
    sourcefiles=$backupsource
  fi
  sourcemountpoint=
  
  if [ "$sourcecount" -gt 1 ]; then
    status "Waiting $backupsourceretrydelay seconds to retry local source \"$sourcehost\"."
    sleep $backupsourceretrydelay
  fi

  status "Doing backup of local source \"$sourcehost\" [$sourcecount]."
  
  backup_source_checkdirs
  
  return $?

}

backup_source_ssh() {

  sourcehost=$(echo $backupsource | cut -d':' -f1)
  sourceuh=$sourcehost
  sourcefiles=$(echo $backupsource | cut -d':' -f2-)

  echo $sourcehost | $GREP '.@.' >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    sourceuser=$(echo $sourcehost | cut -d'@' -f1)
    sourcehost=$(echo $sourcehost | cut -d'@' -f2-)
  fi

  if [ "$sourcehost" = "`hostname -s`" ] ; then
    backup_source_local
    return $?
  fi
  
  if [ "$sourcecount" -gt 1 ]; then
    status "Waiting $backupsourceretrydelay seconds to retry remote source \"$sourcehost\"."
    sleep $backupsourceretrydelay
  fi

  status "Doing backup of remote source \"$sourcehost\" [$sourcecount]."

  # Check if host is up

  checkstarttime=`date +%s`
  waitprint=0
  while :
  do
    ssh -o ConnectTimeout=3 -o BatchMode=yes $sourceuh echo "" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      status "Backup source \"$sourcehost\" is up."
      break
    fi
    if [ "$waitprint" -eq 0 ]; then
      waitprint=1
      error "Backup source \"$sourcehost\" is down - Waiting for host to respond."
    fi
    sleep $backupsourceconnectdelay
    timenow=`date +%s`
    time=$(echo $timenow - $checkstarttime | bc)
    if [ "$time" -ge "$backupsourceconnectttl" ]; then
      error "Backup source \"$sourcehost\" is down - Giving up."
      return 1
    fi
  done

  sourcemountpoint="$backupmntdir/ssh-`hostname -s`-$sourcehost-$backupdate-$RANDOM"
  mkdir -p $sourcemountpoint || return 1
  statusnn "Connecting SSH source \"$sourcehost\" on \"$sourcemountpoint\"."
  sshfs $backupsshfsargs ${sourceuh}:/ $sourcemountpoint || {
    error "Unable to connect to SSH source \"$sourcehost\"."
    rmdir $sourcemountpoint >/dev/null 2>&1;
    return 1;
  }
  successprint

  backup_source_checkdirs

  return $?

}

backup_source_checkdirs() {

  status "Validating backup directories of source \"$sourcehost\"."

  sourcefilesX=$(echo "$sourcefiles" | tr '\n' ' ' | $SED -e 's/^ //g' | $SED -e 's/  / /g')
  sourcefiles=
  sourcefilesmissing=0
  sourceexcludes=

  for ((i=1; ; i++))
  do
    s=$(echo "$sourcefilesX" | cut -d',' -f$i)
    if [ "$s" = "" ]; then
      break
    fi

    echo "$s" | $GREP -i '^-.*$' >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      s=$(echo $s | $SED -e 's/^-//g')
      debug "Excluding file \"$s\" for \"$sourcehost\"."
      if [ "$sourceexcludes" = "" ]; then
        sourceexcludes="$s"
      else
        sourceexcludes="$sourceexcludes
        $s"
      fi
      continue
    fi

    if [ "$sourcemountpoint" = "" ]; then
      lsfile=$s
    else
      lsfile=$sourcemountpoint/$s
    fi
    $LS $lsfile >/dev/null 2>&1
    if [ $? -eq 0 ] ; then
      debug "Including file \"$s\" for \"$sourcehost\"."
      if [ "$sourcehost" = "`hostname -s`" ]; then
        sourcefiles="$sourcefiles $s"
      else
        sourcefiles="$sourcefiles ${sourceuh}:${s}"
      fi
    else
      #error "Excluding \"$s\" from backup for \"$sourcehost\", can't access!"
      error "Cant't access file \"$s\" on \"$sourcehost\"."
      sourcefilesmissing=$(echo $sourcefilesmissing + 1 | bc)
    fi
  done

  sourcefiles=$(echo "$sourcefiles" | $SED -e 's/^ //g')
  sourcefilesX=

  if ! [ "$sourcemountpoint" = "" ]; then
    statusnn "Unmounting source \"$sourcehost\" from \"$sourcemountpoint\"."
    fusermount -u $sourcemountpoint && { rmdir $sourcemountpoint && successprint; }
    stopprint
  fi

  if [ "$sourcefiles" = "" ] ; then
    error "No valid source files for \"$sourcehost\", aborting backup!"
    return 1
  fi

  if ! [ "$sourcefilesmissing" -eq 0 ]; then
    error "One or more source files missing for \"$sourcehost\", aborting backup!"
    return 1
  fi

  if [ "$sourcehost" = "`hostname -s`" ]; then
    sourcefiles="$sourcefiles /dev/null"
  else
    sourcefiles="$sourcefiles $sourceuh:/dev/null"
  fi

  return 0

}

backup_dest_loop() {

  destinations_failure=0
  destinations_success=0

  for backupdest in $backupdestinations
  do
  
    status "Doing backup from source \"$sourcehost\" to destination \"$backupdest\"."

    desttype=
    desttarget=
    desthost=
    destuser=
    destuh=
    destdir=
    destmountpoint=
    destmountdir=
    destmounted=0

    rsyncstart=
    rsyncfinish=

    ret=
    echo $backupdest | $GREP -i '.*:\/\/.*\/' >/dev/null 2>&1
    if [ $? -eq 0 ] ; then
      echo $backupdest | $GREP -i '^smb:\/\/.*\/' >/dev/null 2>&1
      if [ $? -eq 0 ] ; then # SMB
        backup_dest_smb
        ret=$?
      fi
    else
      echo $backupdest | $GREP '^\/' >/dev/null 2>&1
      if [ $? -eq 0 ] ; then # Local
        backup_dest_local
        ret=$?
      fi
      echo $backupdest | $GREP '.*:\/' >/dev/null 2>&1
      if [ $? -eq 0 ] ; then # SSH
        backup_dest_ssh
        ret=$?
      fi
    fi

    if [ "$ret" = "" ] ; then
      destinations_failure=$(echo $destinations_failure + 1 | bc)
      error "Unknown backup destination: \"$backupdest\""
      if ! [ "$backupemailfailure" = "0" ]; then
        backup_failure_report
      fi
      continue
    fi

    if [ "$ret" -eq 0 ] ; then
      backup_rsync
      ret=$?
    fi

    if [ "$ret" -eq 0 ] ; then
      destinations_success=$(echo $destinations_success + 1 | bc)
      if ! [ "$backupemailsuccess" = "0" ]; then
        backup_success_report
      fi
    else
      destinations_failure=$(echo $destinations_failure + 1 | bc)
      if ! [ "$backupemailfailure" = "0" ]; then
        backup_failure_report
      fi
    fi
    
    if ! [ "$backupexcludestmpfile" = "" ]; then
      rm -f $backupexcludestmpfile
      backupexcludestmpfile=
    fi
    if ! [ "$backuplogtmpfile" = "" ]; then
      rm -f $backuplogtmpfile
      backuplogtmpfile=
    fi
    if ! [ "$backuplogtmpfile_stdout" = "" ]; then
      rm -f $backuplogtmpfile_stdout
      backuplogtmpfile_stdout=
    fi

  done

  if [ $destinations_failure -eq 0 ] ; then
    return 0
  else
    return 1
  fi

}

backup_dest_local() {

  desttype=1
  if [ "$desthost" = "" ]; then
    desthost="`hostname -s`"
  fi
  if [ "$destdir" = "" ]; then
    destdir=$backupdest
  fi
  if [ "$desttarget" = "" ]; then
    desttarget=$backupdest
  fi
  destmountpoint=
  destmounted=0
  destmountdir=$destdir
  
  debug "Backup to local destination \"$backupdest\"."
  
  backup_dest_local_mount
  
  return $?
  
}

backup_dest_local_mount() {

  topdir=$(echo $destdir | cut -d'/' -f2)
  if [ "$topdir" = "mnt" ] || [ "$topdir" = "media" ] ; then
    destmountpoint=$(echo $destdir | cut -d'/' -f-3)
    mountpoint -q $destmountpoint
    if [ $? != 0 ] ; then
      statusnn "Mounting destination \"$backupdest\" on \"$destmountpoint\"."
      mount $destmountpoint || { stopprint; return 1; }
      # Check if the directory is actually mounted. If nofail is set in /etc/fstab, mount will not fail.
      # This is to prevent backing up to the mountpoint under /mnt
      mountpoint -q $destmountpoint
      if [ $? != 0 ] ; then
        error "Unable to mount \"$destmountpoint\" for \"$backupdest\"."
        return 1
      fi
      successprint
      destmounted=1
    fi
  fi
  mkdir -p "$destdir" || {
    if [ "$destmounted" = "1" ] ; then
      umount $destmountpoint
    fi
    return 1
  }
  
  return 0

}

backup_dest_ssh() {

  desttype=2
  destmounted=0
  desthost=$(echo $backupdest | cut -d':' -f1)
  destuh=$desthost
  destdir=$(echo $backupdest | cut -d':' -f2-)

  echo $desthost | $GREP '.@.' >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    destuser=$(echo $desthost | cut -d'@' -f1)
    desthost=$(echo $desthost | cut -d'@' -f2-)
  fi

  if [ "$desthost" = "`hostname -s`" ] ; then
    desttarget=$destdir
    backup_dest_local
    return $?
  fi

  debug "Backup to ssh destination \"$backupdest\"."
  
  desttarget=$backupdest
  destmountpoint="$backupmntdir/ssh-`hostname -s`-$desthost-$backupdate-$RANDOM"
  destmountdir=$destmountpoint

  backup_dest_ssh_mount
  
  return $?

}

backup_dest_ssh_mount() {

  #ssh $backupsshargs $desthost mkdir -p $destdir || return 1
  statusnn "Mounting destination \"$backupdest\" on \"$destmountpoint\"."
  mkdir -p $destmountpoint || { stopprint; return 1; }
  sshfs $backupsshfsargs $backupdest $destmountpoint || {
    error "Unable to connect to backup destination \"$desthost\" (SSH)"
    rmdir $destmountpoint >/dev/null 2>&1
    return 1
  }
  destmounted=1
  successprint

}

backup_dest_smb() {

  desttype=3
  destmounted=0
  destproto="$(echo $backupdest | $GREP '://' | $SED -e 's,^\(.*://\).*,\1,g')"
  desturl=$(echo $backupdest | $SED -e s,${destproto},,g)
  destuser="$(echo $desturl | $GREP '@' | cut -d'@' -f1 | cut -d':' -f1)"
  destpass="$(echo $desturl | $GREP '@' | cut -d'@' -f1 | cut -d':' -f2)"
  desthost="$(echo $desturl | $SED -e s,${destuser}.*@,,g | cut -d/ -f1)"
  destshare="$(echo $desturl | cut -d'/' -f2)"
  destdir="$(echo $desturl | $GREP '/' | cut -d'/' -f3-)"
  destdir="/$destdir"

  destmountpoint="$backupmntdir/smb-`hostname -s`-$desthost-$backupdate-$RANDOM"
  destmountdir="${destmountpoint}${destdir}"
  desttarget=$destmountdir

  debug "Backup to smb destination \"$backupdest\"."

  mkdir -p $destmountpoint || return 1

  if ! [ "$destuser" = "" ] && ! [ "$destpass"  = "" ] ; then
    backupoptions="-o username=$destuser,password=$destpass"
  elif ! [ "$destuser" = "" ] ; then
    backupoptions="-o username=$destuser"
  else
    backupoptions=
  fi
  
  backup_dest_smb_mount

  return $?

}

backup_dest_smb_mount() {

  statusnn "Mounting destination \"$backupdest\" on \"$destmountpoint\"."
  mount.cifs "//$desthost/$destshare" $backupoptions $destmountpoint || {
    error "Unable to connect to backup destination \"$desthost\" (SMB)"
    rmdir $destmountpoint
    return 1
  }
  #mount -t cifs "//$desthost/$destshare" $backupoptions $destmountpoint || { rmdir $destmountpoint; return 1; }
  destmounted=1
  successprint

}

backup_dest_umount() {

  # Umount destination
  if [ "$destmounted" -eq "1" ] ; then
    if [ "$desttype" -eq "1" ] ; then
      statusnn "Unmounting local destination \"$backupdest\" from \"$destmountpoint\"."
      umount $destmountpoint && successprint
      stopprint
    elif [ "$desttype" -eq "2" ] ; then
      statusnn "Unmounting SSH destination \"$backupdest\" from \"$destmountpoint\"."
      fusermount -u $destmountpoint && { rmdir $destmountpoint && successprint; }
      stopprint
    else
      statusnn "Unmounting SMB destination \"$backupdest\" from \"$destmountpoint\"."
      umount $destmountpoint && { rmdir $destmountpoint && successprint; }
      stopprint
    fi
    destmounted=0
    destmountpoint=
  fi

}

# Find archive dir and rsync to it

backup_rsync() {

  info "Backup of files \"$sourcefiles\" on \"$sourcehost\" to destination \"$backupdest\"."
  rsynctime=0

  # Locate witch backup archive directory to use

  mkdir -p "$destmountdir/$sourcehost" || return 1

  if [ "$backuparchives" = "0" ] || [ "$backuparchives" = "" ]; then # Dont use archives.

    destarchivedir="NONE"
    destmountdirfull="$destmountdir/$sourcehost"
    destts=0
    desttargetfull="$desttarget/$sourcehost"
    count_archives=0
    
    info "Backup of \"$sourcehost\" to non-archive directory: \"$backupdest/$sourcehost\""
    
    if [ -d "$destmountdirfull" ]; then
      # Dont backup into an existing directory unless it is identified as a backupdir
      if ! [ -r "$destmountdirfull/$backupidfile" ]; then
        error "Missing backup ID file \"$backupidfile\" in directory \"$desttargetfull\"."
        return 1
      fi
    else
      mkdir -p "$destmountdirfull" || return 1
    fi
    echo "$backupid" >"$destmountdirfull/$backupidfile" || return 1

  else # Find archive directory to use
  
    if ! [ "$backuparchivedirs" = "" ]; then
      for i in $backuparchivedirs
      do
        if [ -d "$destmountdir/$sourcehost/$i" ]; then
          continue
        fi
        mkdir -p "$destmountdir/$sourcehost/$i" || return 1
        echo "$backupid" >"$destmountdir/$sourcehost/$i/$backupidfile" || return 1
      done
    fi
    destarchivedir=
    destmountdirfull=
    destts=0
    desttargetfull=
    count_archives=0
    for i in `$LS -lt --time-style='+%Y%m%d%H%M%S' $destmountdir/$sourcehost | $SED 's/ /\\\/g'`
    do
      i=$(echo $i | $SED 's/\\/ /g')
      f=$(echo $i | $AWK '{ print $7}')
      ts=$(echo $i | $AWK '{ print $6}')
      if [ "$f" = "" ]; then
        continue
      fi
      
      if ! [ "$backuparchivedirs" = "" ]; then
        found=0
        for y in $backuparchivedirs
        do
          if [ "$y" = "$f" ]; then
            found=1
            break
          fi
        done
        if  ! [ "$found" = "1" ]; then
          error "Directory \"$desttarget/$sourcehost/$f\" is not part of archive directories \"$backuparchivedirs\" - Skipping."
          continue
        fi
      fi
      
      if ! [ -d "$destmountdir/$sourcehost/$f" ]; then
        warn "There is a file in the destination directory: \"$desttarget/$sourcehost/$f\"."
      fi
      # Dont backup into an existing directory unless it is identified as a backup archive
      if ! [ -r "$destmountdir/$sourcehost/$f/$backupidfile" ]; then
        error "Missing backup ID file \"$backupidfile\" in archive directory \"$desttarget/$sourcehost/$f\"."
        if ! [ "$backuparchivedirs" = "" ]; then
          return 1
        fi
        continue
      fi
      
      count_archives=$(echo $count_archives + 1 | bc)
      
      if [ -r "$destmountdir/$f/$backuptsfile" ]; then
        tstmp=$(cat $destmountdir/$f/$backuptsfile)
        if [[ "$tstmp" =~ ^[0-9]+$ ]] ; then
          ts=$tstmp
        fi
      fi
      
      if [ "$destarchivedir" = "$backuparchivedir" ]; then
        continue
      fi
      
      if [ "$destarchivedir" = "" ] || [ "$ts" -lt "$destts" ]; then
        destarchivedir=$f
        destts=$ts
      fi
    done
    
    if [ "$destarchivedir" = "" ] || [ "$count_archives" -lt "$backuparchives" ]; then # Create new archive directory
      if ! [ "$backuparchivedirs" = "" ]; then
        error "Found no archive directories to use for \"$desttarget/$sourcehost\"."
        return 1
      fi
      destarchivedir=$backuparchivedir
      destmountdirfull="$destmountdir/$sourcehost/$destarchivedir"
      desttargetfull="$desttarget/$sourcehost/$destarchivedir"
      info "Creating new archive directory \"$desttarget/$sourcehost/$destarchivedir\" for backup source \"$sourcehost\" destination \"$backupdest\"."
      mkdir -p "$destmountdir/$sourcehost/$destarchivedir" || return 1
    else # Use existing archive directory
      info "Using existing archive \"$desttarget/$sourcehost/$destarchivedir\" for backup source \"$sourcehost\" destination \"$backupdest\"."
      found=0
      if ! [ "$backuparchivedirs" = "" ]; then
        for i in $backuparchivedirs
        do
          if [ "$destarchivedir" = "$i" ]; then
            found=1
          fi
        done
      fi
      if ! [ "$found" = "1" ] && ! [ "$destarchivedir" = "$backuparchivedir" ]; then
        info "Renaming archive \"$desttarget/$sourcehost/$destarchivedir\" to \"$desttarget/$sourcehost/$backuparchivedir\" for backup source \"$sourcehost\" destination \"$backupdest\"."
        if [ -d "$destmountdir/$sourcehost/$backuparchivedir" ]; then
          error "Archive directory \"$destmountdir/$sourcehost/$backuparchivedir\" already exist!"
          return 1
        fi
        mv "$destmountdir/$sourcehost/$destarchivedir" "$destmountdir/$sourcehost/$backuparchivedir" || return 1
        destarchivedir=$backuparchivedir
      fi
      destmountdirfull="$destmountdir/$sourcehost/$destarchivedir"
      desttargetfull="$desttarget/$sourcehost/$destarchivedir"
    fi
    
    # Last sanity check - WARNING: DO NOT REMOVE THIS
    if [ "$destarchivedir" = "" ] ; then
      error "FAILED TO SET BACKUP ARCHIVE DIR!"
      return 1
    fi
    
    echo "$backupid" >"$destmountdirfull/$backupidfile" || return 1

    info "Backup of \"$sourcehost\" to archive directory: \"$backupdest/$sourcehost/$destarchivedir\""

  fi
  
  # Umount destination because we don't use it for rsync
  backup_dest_umount

  # Last sanity check - WARNING: DO NOT REMOVE THIS
  if [ "$destmountdirfull" = "" ] || [ "$desttargetfull" = "" ] ; then
    error "FAILED TO SET BACKUP DESTINATION!"
    return 1
  fi
  
  if [ "$sourcefiles" = "" ] ; then
    error "FAILED TO SET BACKUP SOURCEFILES!"
    return 1
  fi

  #  Perform rsync backup

  rsyncstart=1
  
  # Set logfile
  
  backuplogtmpfile="$backuplogdir/rsyncbackup-from-$sourcehost-to-$desthost-$backupdate-$RANDOM.log"
  backuplogtmpfile_stdout="$backuplogdir/rsyncbackup-from-$sourcehost-to-$desthost-$backupdate-$RANDOM-stdout.log"
  mkdir -p $backuplogdir || return 1
  $TOUCH $backuplogtmpfile || return 1
  $TOUCH $backuplogtmpfile_stdout || return 1
  
  # Create exclude file

  backupexcludestmpfile="/tmp/rsyncbackup-excludes-$sourcehost-$backupdate-$RANDOM.txt"
  echo "$backupexclude" >$backupexcludestmpfile || { backup_failure_report_all; exit_failure; }
  if ! [ "$sourceexcludes" = "" ]; then
    echo "$sourceexcludes" >>$backupexcludestmpfile || { backup_failure_report_all; exit_failure; }
  fi
  if [ "$sourcehost" = "$desthost" ]; then
    echo "$destdir" >>$backupexcludestmpfile || return 1
  fi
  echo "$backupmntdir" >>$backupexcludestmpfile || { backup_failure_report_all; exit_failure; }
  $SED -i '/^$/d' $backupexcludestmpfile || { backup_failure_report_all; exit_failure; }

  if [ "$backuprun" -eq 1 ]; then
    echo "Command: rsync $backuprsyncargs -e 'ssh -o BatchMode=yes' --exclude-from=$backupexcludestmpfile --log-file=$backuplogtmpfile $sourcefiles $desttargetfull" >$backuplogtmpfile
    echo "Command: rsync $backuprsyncargs -e 'ssh -o BatchMode=yes' --exclude-from=$backupexcludestmpfile --log-file=$backuplogtmpfile $sourcefiles $desttargetfull" >$backuplogtmpfile_stdout
    status "Running rsync $backuprsyncargs -e 'ssh -o BatchMode=yes' --exclude-from=$backupexcludestmpfile --log-file=$backuplogtmpfile $sourcefiles ${desttargetfull}"
    starttime=`date +%s`
    rsync $backuprsyncargs -e 'ssh -o BatchMode=yes' --exclude-from="$backupexcludestmpfile" --log-file="$backuplogtmpfile" $sourcefiles $desttargetfull >$backuplogtmpfile_stdout || {
      error "Rsync command failed for backup source \"$sourcehost\" destination \"$desthost\"."
      return 1
    }
    finishtime=`date +%s`
    rsynctime=`echo "$finishtime - $starttime" | bc`
    rsyncts=`date -u -d @${rsynctime} +"%T"`
    rsyncfinish=1
    #successprint
    result "Rsync finished for \"$sourcehost\" to \"$desthost\" in $rsyncts. See \"$backuplogtmpfile\" for results."
  else
    error "Skipping rsync command on \"$sourcehost\" to \"$backupdest\" --- To actually perform rsync run script again with $0 -R"
    error "Command is: rsync $backuprsyncargs -e 'ssh -o BatchMode=yes' --exclude-from=$backupexcludestmpfile --log-file=$backuplogtmpfile $sourcefiles $desttargetfull"
    return 1
  fi

  # Update the timestamp file into the archive directories
  # This is how the script tracks which directory to use next time

  # Mount backup destination again to update TS
  if [ "$desttype" -eq "1" ] ; then
    backup_dest_local_mount || return 1
  elif [ "$desttype" -eq "2" ] ; then
    backup_dest_ssh_mount || return 1
  elif [ "$desttype" -eq "3" ] ; then
    backup_dest_smb_mount || return 1
  fi

  rm -f "$destmountdirfull/$backuptsfile" || return 1
  echo "$backupts" >"$destmountdirfull/$backuptsfile" || return 1
  
  # Umount destination
  backup_dest_umount

  return 0

}

exit_cleanup() {

  if [ "$lockfile" -eq 1 ]; then
    rm -f $backuplockfile
  fi
  if [ "$mntdir" -eq 1 ]; then
    rmdir $backupmntdir
  fi

}

backup_failure_report_all() {

  LANG=en_GB
  EMAIL=$backupemailfrom $MUTT -s "Rsync backup script on `hostname` on `date` FAILED" "$backupemailfailure" <<EOT
Rsync backup script on `hostname` on `date` FAILED

Sources: $backupsources
Destinations: $backupdestinations
Configuration file: $backupconfig
Rsync arguments: $backuprsyncargs
Files excluded: $backupexcludeoneline

$logall

$script v$backupversion

EOT

}

backup_source_failure_report() {

  status "Sending failure report for backup source \"$sourcehost\"."

  LANG=en_GB
  EMAIL=$backupemailfrom $MUTT -s "Rsync backup for $sourcehost on `date` FAILED" "$backupemailfailure" <<EOT
Rsync backup for $sourcehost on `date` FAILED

Source: $backupsource
Destinations: $backupdestinations
Configuration file: $backupconfig
Rsync arguments: $backuprsyncargs
Files excluded: $backupexcludeoneline

$log

$script v$backupversion

EOT

}

backup_success_report() {

  status "Sending success report for backup source \"$sourcehost\" destination \"$desthost\"."
  
  attachment=
  if [ "$rsyncstart" = "1" ]; then
    if [ "$backupgziplog" = "1" ]; then
      bzip2 $backuplogtmpfile
      backuplogtmpfile="$backuplogtmpfile.bz2"
    fi
    attachment="-a $backuplogtmpfile --"
  fi

  LANG=en_GB
  EMAIL=$backupemailfrom $MUTT -s "Rsync backup for $sourcehost to $backupdest on `date` was successful" $attachment "$backupemailsuccess" <<EOT
Rsync backup for $sourcehost to $backupdest on `date` was successful

Source: $backupsource
Destination: $backupdest
Time: $rsyncts
Archive directory: $destarchivedir
Configuration file: $backupconfig
Rsync arguments: $backuprsyncargs
Files excluded: $backupexcludeoneline

$log

$script v$backupversion

EOT

}

backup_failure_report() {

  status "Sending failure report for backup source \"$sourcehost\" destination \"$desthost\"."
  
  attachment=
  if [ "$rsyncstart" = "1" ]; then
    if [ "$backupgziplog" = "1" ]; then
      bzip2 $backuplogtmpfile
      backuplogtmpfile="$backuplogtmpfile.bz2"
    fi
    attachment="-a $backuplogtmpfile --"
  fi

  LANG=en_GB
  EMAIL=$backupemailfrom $MUTT -s "Rsync backup for $sourcehost to $backupdest on `date` FAILED" $attachment "$backupemailfailure" <<EOT
Rsync backup for $sourcehost to $backupdest on `date` FAILED

Source: $backupsource
Destination: $backupdest
Archive directory: $destarchivedir
Configuration file: $backupconfig
Rsync arguments: $backuprsyncargs
Files excluded: $backupexcludeoneline

$log

$script v$backupversion

EOT

}

exit_failure() {
  exit_cleanup
  exit 1
}

exit_success() {
  exit_cleanup
  exit 0
}

exit_quiet() {
  exit_cleanup
  exit 0
}

main $@
