#!/bin/sh
#
#  tarbackup2-conf.sh - Configuration file for tarbackup2.sh
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
#  tarbackup.sh creates a backup specified by backupfileprefix and
#  backupfilerevision in b2zipped tar archives.
# 
#  Files to include in the backups are specified by backupfiles
#  the list of files in backupexclude are files to exclude from the
#  backup, such as temp files, sockets and cache.
#
#  New in version 2: "backuplocations" allows you to specify unlimited
#  number of locations and also supports mounting smb and ftp.
#  With new success/failure reporting.
#

backupid="$(hostname -s)"						# <--- An unique ID for the backup filename --->
backupdate="$(date '+%Y%m%d-%H%M%S')"					# <--- Datestamp in reverse used as the revision for the backup filename --->

backupfileprefix="abackup-$backupid"					# <--- A prefix for the backup filename --->
backupfilerevision=$backupdate						# <--- A revision that will increase on each run --->

backupemailsuccess="root"						# <--- Where to send backup success report, set to "0" for no report --->
backupemailfailure="root"						# <--- Where to send backup failure report, set to "0" for no report --->
backupemailfailureall="root"						# <--- Where to send backup report, set to "0" for no report --->

backupold2keep=3							# <--- Number of OLD backups to keep after new backup is done, 0 will only keep the NEW backup file and erase all previous backups! --->

backupmysql=1								# <--- Enable backup of local mysql databases 0/1 --->
backupmysqlfileprefix="abackup-$backupid-mysql"				# <--- File prefix for the mysql dump file --->
backupmysqlfilerevision=$backupdate					# <--- File revision for the mysql dump file --->
backupmysqlcmd="/usr/bin/mysqldump --all-databases -u root"		# <--- Command to dump database --->

backuppgsql=1								# <--- Enable backup of local postgres databases 0/1 */ --->
backuppgsqlfileprefix="abackup-$backupid-pgsql"				# <--- File prefix for the postgres dump file --.>
backuppgsqlfilerevision=$backupdate					# <--- File revision for the postgres dump file -.->
backuppgsqlcmd="/usr/local/pgsql/bin/pg_dumpall -U postgres"		# <--- Command to dump database --->

backupsshfsargs=
backupsshargs=

# Locations is where you store backups, the first one listed will be used to store the actual files, the next ones are secondary
# locations where you want to copy the backups to.
# The backups can be storted locally, via ssh/sftp, via smb, or via ftp.
# Syntax are, Local: /mnt/backup, SSH(SFTP): host:/mnt/backup, SMB: smb://user:pass@host/dir, FTP: ftp://user:pass@host/dir
# If the directory starts with /mnt or /media, it will be automatically mounted and umounted if it is not mounted already.
# The FIRST listed location should not be FTP.

backuplocations="\
host1:/mnt/datadisk/backup/abackup/$backupid
host2:/mnt/backup/abackup/$backupid
host3:/mnt/store/abackup/$backupid
"

# Enter files to backup here

backupfiles="\
etc
var/spool/mail
var/spool/cron
var/lib/samba
var/lib/named
var/lib/mysql
var/lib/pgsql
lib/firmware/dvb-fe-*
srv
home
usr/local
home/jonas/temp
"

# Enter files to exclude here, like temp files and sockets

backupexclude="\
home/*/temp
home/*/Temp
home/*/backup
home/*/Backup
home/*/build
home/*/.xsession-errors
home/*/.local/share/Trash
home/*/.cache
home/*/.thumbnails
home/*/.qt
home/*/.gvfs
home/*/.dbus
home/*/.netx
home/*/.kde/cache-*
home/*/.kde/tmp-*
home/*/.kde/socket-*
home/*/.kde4/cache-*
home/*/.kde4/tmp-*
home/*/.kde4/socket-*
home/*/.beagle
home/*/.pulse-cookie
home/*/.pulse
home/*/.xine
home/*/.mcop
home/*/.java
home/*/.adobe
home/*/.macromedia
home/*/.mozilla/firefox/*/Cache*
home/*/.opera/cache
home/*/.mythtv/*cache
home/*/.xmltv/cache
home/*/.googleearth
home/*/.wine
home/*/.wine_*
home/*/.kde4/share/apps/nepomuk
home/*/.kde/share/apps/amarok/albumcovers/cache
var/cache
var/tmp
var/run
var/spool/postfix/private
var/spool/postfix/public
var/lib/named/lib
var/lib/named/proc
var/lib/named/var
var/lib/named/dev
var/lib/mysql/mysql.sock
var/lib/ntp/proc
var/lib/samba/unexpected
home/jonas/photos
"
