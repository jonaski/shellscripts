#!/bin/sh
#
#  tarbackup2.sh - TAR BACKUP SCRIPT
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

backupversion="2.1.1"

# Functions below here

backup_local() {

  backupdir=$backuplocation
  mountpoint=$backuplocation
  mountpointdir=$backuplocation
  mounted=

  topdir=$(echo $backupdir | cut -d'/' -f2)
  if [ "$topdir" = "mnt" ] || [ "$topdir" = "media" ] ; then
    mountpoint=$(echo $backupdir | cut -d'/' -f-3)
    mountpoint -q $mountpoint
    if [ $? != 0 ] ; then
      mount $mountpoint || {
        if [ "$count" = "1" ]; then
          exit_failure
        fi
        return 1
      }
      mounted=1
      if [ "$count" = "1" ]; then
        mounted1=1
        mountpoint1=$mountpoint
      fi
    fi
  fi
  mkdir -p "$backupdir" || exit_failure

  if [ "$count" = "1" ]; then
    backup_create
  else
    backup_copy || {
      if [ "$mounted" = "1" ] ; then
        umount $mountpoint
      fi
      return 1
    }
  fi

  backup_delete

  if ! [ "$count" = "1" ] && [ "$mounted" = "1" ] ; then
    umount $mountpoint
  fi

  return 0

}

backup_ssh() {

  backuphost=$(echo $backuplocation | cut -d':' -f1)
  backupdir=$(echo $backuplocation | cut -d':' -f2-)

  if [ "$backuphost" = "$backupid" ] ; then
    backuplocation=$backupdir
    backup_local
    return $?
  fi

  mountpoint="/tmp/ssh-$backupid-$backuphost-$backupdate-$RANDOM"
  mountpointdir=$mountpoint

  if [ "$count" = "1" ]; then
    backup_ssh_mount || { rmdir $mountpoint >/dev/null 2>&1; exit_failure; }
    mounted1=1
    mountpoint1=$mountpoint
    backup_create
  else
    #ssh $backupsshargs $backuphost mkdir -p $backupdir || return 1
    backup_ssh_copy || return 1
    backup_ssh_mount || { rmdir $mountpoint >/dev/null 2>&1; return 1; }
  fi

  backup_delete

  if ! [ "$count" = "1" ]; then
    fusermount -u $mountpoint && rmdir $mountpoint
  fi

  return 0

}

backup_ssh_copy() {

  echo $n "Copying tar backup \"$backuplocationsrc/$backupfile.bz2\" to location \"$backuplocation\". $c"
  scp -qp $backupfileorig $backuplocation/ || return 1
  echo "Done."
  scp -qp $backupfileorigmd5 $backuplocation/ || return 1
  if [ "$backupmysql" = "1" ] ; then
    echo $n "Copying mysql backup \"$backuplocationsrc/$backupmysqlfile.bz2\" to location \"$backuplocation\". $c"
    scp -qp $backupmysqlfileorig $backuplocation || return 1
    echo "Done."
    scp -qp $backupmysqlfileorigmd5 $backuplocation || return 1
  fi
  if [ "$backuppgsql" = "1" ] ; then
    echo $n "Copying pgsql backup \"$backuplocationsrc/$backuppgsqlfile.bz2\" to location \"$backuplocation\". $c"
    scp -qp $backuppgsqlfileorig $backuplocation || return 1
    echo "Done."
    scp -qp $backuppgsqlfileorigmd5 $backuplocation || return 1
  fi

  return 0

}

backup_ssh_mount() {

   mkdir -p $mountpoint || return 1
   #ssh $backupsshargs $backuphost mkdir -p $backupdir || return 1
   sshfs $backupsshfsargs $backuplocation $mountpoint || return 1

   return 0

}

backup_smb() {

  backupproto="$(echo $backuplocation | grep '://' | sed -e 's,^\(.*://\).*,\1,g')"
  backupurl=$(echo $backuplocation | sed -e s,${backupproto},,g)
  backupuser="$(echo $backupurl | grep '@' | cut -d'@' -f1 | cut -d':' -f1)"
  backuppass="$(echo $backupurl | grep '@' | cut -d'@' -f1 | cut -d':' -f2)"
  backuphost="$(echo $backupurl | sed -e s,${backupuser}.*@,,g | cut -d/ -f1)"
  backupshare="$(echo $backupurl | cut -d'/' -f2)"
  backupdir="$(echo $backupurl | grep '/' | cut -d'/' -f3-)"
  backupdir="/$backupdir"

  mountpoint="/tmp/smb-$backupid-$backuphost-$backupdate-$RANDOM"
  mountpointdir="$mountpoint$backupdir"

  mkdir -p $mountpoint || return 1

  if ! [ "$backupuser" = "" ] && ! [ "$backuppass"  = "" ] ; then
    backupoptions="-o username=$backupuser,password=$backuppass"
  elif ! [ "$backupuser" = "" ] ; then
    backupoptions="-o username=$backupuser"
  else
    backupoptions=
  fi

  mount -t cifs "//$backuphost/$backupshare" $backupoptions $mountpoint || { rmdir $mountpoint; return 1; }

  if [ "$count" = "1" ]; then
    mounted1=1
    mountpoint1=$mountpoint
    backup_create
  else
    backup_copy || { umount $mountpoint && rmdir $mountpoint; return 1; }
  fi

  backup_delete

  if ! [ "$count" = "1" ]; then
    umount $mountpoint && rmdir $mountpoint
  fi

  return 0

}

backup_ftp() {

  if [ "$count" = "1" ]; then
    echo "ERROR: Can't use FTP as the first backup location!" >&2
    exit_failure
  fi

  backuplocation2=$(echo $backuplocation | sed -e 's/ftp:\/\///g')
  if [ "$backuplocation2" = "" ]; then
    echo "ERROR: Cant figure out URL for \"$backuplocation\"." >&2
    return 1
  fi

  mountpoint="/tmp/ftp-$backupid-$backuphost-$backupdate-$RANDOM"
  mountpointdir=$mountpoint
  mkdir -p $mountpoint || return 1

  curlftpfs $backuplocation2 $mountpoint || { rmdir $mountpoint; return 1; }

  if [ "$count" = "1" ]; then
    mounted1=1
    mountpoint1=$mountpoint
    backup_create
  else
    backup_copy || { umount $mountpoint && rmdir $mountpoint; return 1; }
  fi

  backup_delete

  if ! [ "$count" = "1" ]; then
    umount $mountpoint && rmdir $mountpoint
  fi

  return 0

}

backup_create() {

  backuplocationsrc=$backuplocation
  backupfileorig="$mountpointdir/$backupfile"

  for i in "$backupfileorig" "$backupfileorig.bz2"
  do
    if [ -f "$i" ] ; then
      echo "ERROR: File $i already exist on \"$filelocation\"!" >&2
      exit_failure
    fi
  done

  echo "tar -cvf $backupfileorig -C / --ignore-failed-read -X $backupexcludestmpfile $backupfiles"

  echo $n "Creating tar archive as \"$backuplocationsrc/$backupfile\". $c"
  echo "$backupexclude" >$backupexcludestmpfile || exit_failure
  echo "$backupmountpoint" >>$backupexcludestmpfile || exit_failure
  tar -cvf $backupfileorig -C / --ignore-failed-read -X $backupexcludestmpfile $backupfiles >$backupfilestmpfile || { rm -f $backupfileorig; exit_failure; return 1; }
  echo "Done."
  echo $n "Compressing tar archive as \"$backuplocationsrc/$backupfile.bz2\". $c"
  bzip2 $backupfileorig || { rm -f $backupfileorig; rm -f $backupfileorig.bz2; exit_failure; return 1; }
  echo "Done."
  backupfileorig="$backupfileorig.bz2"
  backupfileorigmd5="$backupfileorig.md5"
  echo $n "Creating MD5 checksum file \"$backuplocationsrc/$backupfile.bz2.md5\". $c"
  md5sum $backupfileorig >$backupfileorigmd5 && echo "Done."

  # MYSQL

  if [ "$backupmysql" = "1" ] ; then

    backupmysqlfileorig="$mountpointdir/$backupmysqlfile"

    for i in "$backupmysqlfileorig" "$backupmysqlfileorig.bz2"
    do
      if [ -f "$i" ] ; then
        echo "ERROR: File $i already exist on \"$filelocation\"!" >&2
        return
      fi
    done

    echo $n "Dumping mysql database to \"$backuplocationsrc/$backupmysqlfile\". $c"
    $backupmysqlcmd > $backupmysqlfileorig
    if [ $? != 0 ] ; then
      backupmysql=0
    else
      echo "Done."
      echo $n "Compressing mysql database as \"$backuplocationsrc/$backupmysqlfile.bz2\". $c"
      bzip2 $backupmysqlfileorig
      if [ $? != 0 ] ; then
        backupmysql=0
      else
        echo "Done."
        backupmysqlfileorig="$backupmysqlfileorig.bz2"
        backupmysqlfileorigmd5="$backupmysqlfileorig.md5"
        echo $n "Creating mysql database MD5 checksum file \"$backuplocationsrc/$backupmysqlfile.bz2.md5\". $c"
        md5sum $backupmysqlfileorig >$backupmysqlfileorigmd5 && echo "Done."
      fi
    fi
  fi

  # POSTGRESQL

  if [ "$backuppgsql" = "1" ] ; then

    backuppgsqlfileorig="$mountpointdir/$backuppgsqlfile"

    for i in "$backuppgsqlfileorig" "$backuppgsqlfileorig.bz2"
    do
      if [ -f "$i" ] ; then
        echo "ERROR: File $i already exist on \"$filelocation\"!" >&2
        return
      fi
    done

    echo $n "Dumping pgsql database to \"$backuplocationsrc/$backuppgsqlfile\". $c"
    $backuppgsqlcmd > $backuppgsqlfileorig
    if [ $? != 0 ] ; then
      backuppgsql=0
    else
      echo "Done."
      echo $n "Compressing pgsql database as \"$backuplocationsrc/$backuppgsqlfile.bz2\". $c"
      bzip2 $backuppgsqlfileorig
      if [ $? != 0 ] ; then
        backuppgsql=0
      else
        echo "Done."
        backuppgsqlfileorig="$backuppgsqlfileorig.bz2"
        backuppgsqlfileorigmd5="$backuppgsqlfileorig.md5"
        echo $n "Creating pgsql database MD5 checksum file \"$backuplocationsrc/$backuppgsqlfile.bz2.md5\". $c"
        md5sum $backuppgsqlfileorig >$backuppgsqlfileorigmd5 && echo "Done."
      fi
    fi
  fi

  return 0

}

backup_copy() {

  echo $n "Copying tar backup \"$backuplocationsrc/$backupfile.bz2\" to location \"$backuplocation\". $c"
  cp --preserve=timestamps $backupfileorig $mountpointdir || return 1
  echo "Done."
  cp --preserve=timestamps $backupfileorigmd5 $mountpointdir || return 1
  if [ "$backupmysql" = "1" ] ; then
    echo $n "Copying mysql backup \"$backuplocationsrc/$backupmysqlfile.bz2\" to location \"$backuplocation\". $c"
    cp --preserve=timestamps $backupmysqlfileorig $mountpointdir || return 1
    echo "Done."
    cp --preserve=timestamps $backupmysqlfileorigmd5 $mountpointdir || return 1
  fi
  if [ "$backuppgsql" = "1" ] ; then
    echo $n "Copying pgsql backup \"$backuplocationsrc/$backuppgsqlfile.bz2\" to location \"$backuplocation\". $c"
    cp --preserve=timestamps $backuppgsqlfileorig $mountpointdir || return 1
    echo "Done."
    cp --preserve=timestamps $backuppgsqlfileorigmd5 $mountpointdir || return 1
  fi

  return 0

}

backup_delete() {

  backups=0
  for i in `ls -1 -r "$mountpointdir"`
  do
    if ! echo "$i" | grep "^$backupfileprefix-.*\.tar\.bz2$" >/dev/null 2>&1 ; then
      continue
    fi
    if [ "$i" = "$backupfile.bz2" ] ; then
      continue
    fi
    backups=$(echo $backups + 1 | bc)
    if [ $backups -gt $backupold2keep ] ; then
      echo $n "Deleting old backup \"$backuplocation/$i\". $c"
      rm "$mountpointdir/$i" && echo "Done."
      rm -f "$mountpointdir/$i.md5"
    fi
  done

  # Delete old myql backups

  if [ "$backupmysql" = "1" ] ; then
    backups=0
    for i in `ls -1 -r "$mountpointdir"`
    do
      if ! echo "$i" | grep "$backupmysqlfileprefix-.*\.sql\.bz2$" >/dev/null 2>&1 ; then
        continue
      fi
      if [ "$i" = "$backupmysqlfile.bz2" ] ; then
        continue
      fi
      backups=$(echo $backups + 1 | bc)
      if [ $backups -gt $backupold2keep ] ; then
        echo $n "Deleting old mysql backup \"$backuplocation/$i\". $c"
        rm "$mountpointdir/$i" && echo "Done."
        rm -f "$mountpointdir/$i.md5"
      fi
    done
  fi

  # Delete old pgsql backups

  if [ "$backuppgsql" = "1" ] ; then
    backups=0
    for i in `ls -1 -r "$mountpointdir"`
    do
      if ! echo "$i" | grep "$backuppgsqlfileprefix-.*\.sql\.bz2$" >/dev/null 2>&1 ; then
        continue
      fi
      if [ "$i" = "$backuppgsqlfile.bz2" ] ; then
        continue
      fi
      backups=$(echo $backups + 1 | bc)
      if [ $backups -gt $backupold2keep ] ; then
        echo $n "Deleting old pgsql backup \"$backuplocation/$i\". $c"
        rm "$mountpointdir/$i" && echo "Done."
        rm -f "$mountpointdir/$i.md5"
      fi
    done
  fi

}

exit_cleanup() {

  rm -f $backupexcludestmpfile
  rm -f $backupfilestmpfile

  # Umount drives

  if [ "$mounted1" = "1" ] ; then
    echo $mountpoint1 | grep '^\/tmp\/ssh-' >/dev/null 2>&1
    if [ $? -eq 0 ] ; then
      fusermount -u $mountpoint1 && rmdir $mountpoint1
    else
      echo $mountpoint1 | grep '^\/tmp\/smb-' >/dev/null 2>&1
      if [ $? -eq 0 ] ; then
        umount $mountpoint1 && rmdir $mountpoint1
      else
        echo $mountpoint1 | grep '^\/tmp\/ftp-' >/dev/null 2>&1
        if [ $? -eq 0 ] ; then
          umount $mountpoint1 && rmdir $mountpoint1
        else
          umount $mountpoint1
        fi
      fi
    fi
  fi

}

report_success() {

  LANG="en_GB"
  mail -s "Tar backup for `hostname` on `date` to location $backuplocation was successful" -a "$backupfilestmpfile" "$backupemailsuccess" <<EOT
Tar backup for `hostname` on `date` to location $backuplocation was successful

Backup file: $backupfile
Configuration file: $backupconfig
Backup location: $backuplocation

----------------------------------------

- Files included:
$backupfiles

----------------------------------------

- Files excluded:
$backupexclude

----------------------------------------

See attachment for actual files in the backup.

$0 v$backupversion

EOT

}

report_failure() {

 LANG="en_GB"
 mail -s "Tar backup for `hostname` on `date` to location $backuplocation FAILED" "$backupemailfailure" <<EOT
Tar backup for `hostname` on `date` to location $backuplocation FAILED

Backup file: $backupfile
Configuration file: $backupconfig
Backup location: $backuplocation

----------------------------------------

- Files included:
$backupfiles

----------------------------------------

- Files excluded:
$backupexclude

----------------------------------------

$0 v$backupversion

EOT

}

report_failure_all() {

 LANG="en_GB"
 mail -s "Tar backup for `hostname` on `date` FAILED" "$backupemailfailureall" <<EOT
Tar backup for `hostname` on `date` FAILED

Backup file: $backupfile
Configuration file: $backupconfig
Backup locations: $backuplocations

----------------------------------------

- Files included:
$backupfiles

----------------------------------------

- Files excluded:
$backupexclude

----------------------------------------

$0 v$backupversion

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

# Find out how to echo without newline

c=''
n=''
if [ "`eval echo -n 'a'`" = "-n a" ] ; then
  c='\c'
else
  n='-n'
fi

# Parse parameters

script=$(echo "$0" | sed 's/.*\///g')
runpath=$(echo "$0" | sed 's/\(.*\)\/.*/\1/')
while getopts c:hv o
do case "$o" in
    c)  backupconfig="$OPTARG";;
    h)  echo "Usage: $script -hv -c <config>"; exit 0;;
    v)  echo "$script v$backupversion"; exit 0;;
    \?)  echo "Usage: $script -hv -c <config>"; exit 1;;
esac
done

# Reset $@
shift `echo $OPTIND-1 | bc`

# Locate configuration file

if [ "$backupconfig" = "" ] ; then
  backupconfig="tarbackup2-conf.sh"
fi

if ! [ -f "$backupconfig" ]; then
  if [ -f "./$backupconfig" ]; then
    backupconfig="./$backupconfig"
  else
    if [ -f "$runpath/$backupconfig" ]; then
      backupconfig="$runpath/$backupconfig"
    fi
  fi
fi

# Check for existence of needed config file and read it

if ! [ -f "$backupconfig" ]; then
  echo "ERROR: Backup configuration file \"$backupconfig\" does not exist!" >&2
  exit 1
fi

if ! [ -r "$backupconfig" ]; then
  echo "ERROR: Can't read configuration file \"$backupconfig\"." >&2
  exit 1;
fi

. $backupconfig

# Check that we got the configuration needed

for i in \
"backupid" \
"backupdate" \
"backupfileprefix" \
"backupfilerevision" \
"backupemailsuccess" \
"backupemailfailure" \
"backupemailfailureall" \
"backupold2keep" \
"backupmysql" \
"backupmysqlfileprefix" \
"backupmysqlfilerevision" \
"backupmysqlcmd" \
"backuppgsql" \
"backuppgsqlfileprefix" \
"backuppgsqlfilerevision" \
"backuppgsqlcmd" \
"backuplocations" \
"backupfiles" \
"backupexclude"
do
  if [ "${!i}" = "" ] ; then
    echo "ERROR: Missing configuration variable \"$i\" in \"$backupconfig\"!" >&2
    exit 1
  fi
done

# Check that we got all the needed commands

cmds="which cp scp mv rm mkdir rmdir cat tr bc cut sed grep mail tar bzip2 md5sum date hostname mount umount mountpoint fusermount"
for backuplocation in $backuplocations
do
  echo $backuplocation | grep -i '.*:\/\/.*\/' >/dev/null 2>&1
  if [ $? -eq 0 ] ; then
    echo $backuplocation | grep -i '^ftp:\/\/.*\/' >/dev/null 2>&1
    if [ $? -eq 0 ] ; then
      cmds="$cmds curlftpfs"
      continue
    fi
  else
    echo $backuplocation | grep '.*:\/' >/dev/null 2>&1
    if [ $? -eq 0 ] ; then
      cmds="$cmds sshfs"
      continue
    fi
  fi
done

for cmd in $cmds
do
  which $cmd >/dev/null 2>&1
  if [ $? != 0 ] ; then
    echo "ERROR: Missing \"${cmd}\" command!" >&2
    exit_failure
  fi
done

# Set variables

backupfile="$backupfileprefix-$backupfilerevision.tar"
backupmysqlfile="$backupmysqlfileprefix-$backupmysqlfilerevision.sql"
backuppgsqlfile="$backuppgsqlfileprefix-$backuppgsqlfilerevision.sql"

backupfilestmpfile="/tmp/tarbackupfiles-$backupdate-$RANDOM.txt"
backupexcludestmpfile="/tmp/tarbackupexcludes-$backupdate-$RANDOM.txt"

backuplocations=$(echo "$backuplocations" | tr '\n' ' ' | sed -e 's/^ //g' | sed -e 's/  / /g')

# Create backupfiles
# Only include files that actually exist to avoid tar error report

backupfilesX=$(echo "$backupfiles" | tr '\n' ' ' | sed -e 's/^ //g' | sed -e 's/  / /g')
backupfiles=
for ((i=1; ; i++))
do
  s=$(echo "$backupfilesX" | cut -d' ' -f$i)
  if [ "$s" = "" ]; then
    break
  fi
  s2=$s
  echo $s | grep -i '^\/.*' >/dev/null 2>&1
  if ! [ $? -eq 0 ] ; then
    s2="/$s"
  fi
  ls $s2 >/dev/null 2>&1
  if [ $? -eq 0 ] ; then
    backupfiles="$backupfiles $s"
  else
    echo "Excluding \"$s\" from backup, can't access!"
  fi
done
backupfiles=$(echo "$backupfiles" | sed -e 's/^ //g')

if [ "$backupfiles" = "" ] ; then
  echo "ERROR: No backupfiles exist!" >&2
  exit_failure
fi

# Loop locations, create tar, transfer new backups and delete old backups

count=0
locationssuccess=0
locationsfailure=0
for backuplocation in $backuplocations
do

  count=$(echo $count + 1 | bc)
  echo "Performing backup to \"$backuplocation\""

  backuphost=
  backupdir=
  mounted=
  mountpoint=
  mountpointdir=
  ret=

  echo $backuplocation | grep -i '.*:\/\/.*\/' >/dev/null 2>&1
  if [ $? -eq 0 ] ; then
    echo $backuplocation | grep -i '^smb:\/\/.*\/' >/dev/null 2>&1
    if [ $? -eq 0 ] ; then # SMB
      backup_smb
      ret=$?
    fi
    echo $backuplocation | grep -i '^ftp:\/\/.*\/' >/dev/null 2>&1
    if [ $? -eq 0 ] ; then # FTP
      backup_ftp
      ret=$?
    fi
  else
    echo $backuplocation | grep '^\/' >/dev/null 2>&1
    if [ $? -eq 0 ] ; then # Local
      backup_local
      ret=$?
    fi
    echo $backuplocation | grep '.*:\/' >/dev/null 2>&1
    if [ $? -eq 0 ] ; then # SSH
      backup_ssh
      ret=$?
    fi
  fi

  if [ "$ret" = "" ] ; then
    echo "ERROR: Unknown backup location: \"$backuplocation\"" >&2
    if [ "$count" -lt 2 ] ; then
      if ! [ "$backupemailfailureall" = "0" ]; then
        report_failure_all
      fi
      exit_failure
    fi
  elif [ "$ret" -eq "0" ] ; then
    locationssuccess=$(echo $locationssuccess + 1 | bc)
    if ! [ "$backupemailsuccess" = "0" ]; then
      report_success
    fi
  else
    locationsfailure=$(echo $locationsfailure + 1 | bc)
    if ! [ "$backupemailfailure" = "0" ]; then
      report_failure
    fi
  fi

done

if [ "$locationssuccess" -gt "0" ] ; then
  exit_success
else
  if ! [ "$backupemailfailureall" = "0" ]; then
    report_failure_all
  fi
  exit_failure
fi
