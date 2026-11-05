#!/bin/bash
#
#  serviceswatch.sh - Monitor Services Watch
#  Copyright (C) 2010-2026 Jonas Kvinge
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

configfile="/etc/sysconfig/serviceswatch"
if [ "$EUID" -eq 0 ]; then
  statedir="/var/lib/serviceswatch"
  logfile="/var/log/serviceswatch.log"
else
  statedir="$HOME/.local/state/serviceswatch"
  logfile="$statedir/serviceswatch.log"
fi
lockfile="$statedir/serviceswatch.lock"
tmpfile="$statedir/serviceswatch.state"
logmaxsize=1048576				# The log is moved to .1 when it's bigger than this.
debug=0
inettesthosts="8.8.8.8 8.8.4.4"			# Internet is reported to be down only if all of these fail.
pingtimeout=2
connecttimeout=2
maxfailtime=15
reportfreq=120
emailfrom="nobody"
emailto="root"
mailtimeout=60
options=""					# Extra options for ssh.
sshtimeout=30

hosts="
server1 rsyslog sshd named sendmail saslauthd spfmilter opendkim opendmarc milter-regex spamd dovecot apache
server2 rsyslog sshd named sendmail saslauthd spfmilter opendkim opendmarc apache
server3 rsyslog sshd named sendmail saslauthd spfmilter opendkim opendmarc milter-regex mailscanner clamd
server4 rsyslog sshd named sendmail saslauthd spfmilter opendkim opendmarc milter-regex mailscanner clamd
"

timestamp() { TS=$(date '+%d/%m-%Y %H:%M:%S'); }

print() {
  timestamp
  if [ -t 1 ] && ! [ "$color" = "" ]; then
    tput bold
    tput setaf "$color"
  fi
  echo "[$TS] $*"
  if [ -t 1 ]; then
    tput sgr0
  fi
  color=0
}
log() {
  timestamp
  echo "[$TS] $*" >>"$logfile"
}
statusprint() { color=8; print "$@"; }
statuslog() { log "$@"; }
errorprint() {
  timestamp
  if [ -t 1 ]; then
    tput bold
    tput setaf 1
  fi
  echo "[$TS] ERROR: $*" >&2
  if [ -t 1 ]; then
    tput sgr0
  fi
  color=0
}
errorlog() { log "ERROR: $*"; }
status() { statusprint "$@"; statuslog "$@"; }
error() { errorprint "$@"; errorlog "$@"; }
debug() {
  if [ "$debug" = "1" ]; then
    color=3
    print "$@"
    log "$@"
  fi
}

isnum() {
  [[ $1 =~ ^-?[0-9]+$ ]]
}

# Durations can be longer than a day, which %T alone would wrap around.

duration() {
  local seconds="$1" days=$(( $1 / 86400 ))
  if [ "$days" -gt 0 ]; then
    echo "${days}d $(date -u -d "@$(( seconds % 86400 ))" +%T)"
  else
    date -u -d "@$seconds" +%T
  fi
}

html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<< "$1"
}

# The state file has one line per key, with the key as the first field. Keys are compared literally since they can be URL's.

state_get() {
  awk -v key="$1" '$1 == key' "$tmpfile"
}

state_remove() {
  local tmp
  tmp=$(mktemp "$tmpfile.XXXXXX") || return 1
  if awk -v key="$1" '$1 != key' "$tmpfile" > "$tmp"; then
    mv -f -- "$tmp" "$tmpfile"
  else
    rm -f -- "$tmp"
    return 1
  fi
}

loadconfig() {

  if [ -f "$configfile" ]; then
    # shellcheck source=/dev/null
    if ! . "$configfile"; then
      errorprint "Failed to load configuration file \"$configfile\"."
      exit 1
    fi
  fi

}

main() {

  init "$@"
  
  inetstatus
  serviceswatch
  
  if [ "$sendreport" = "1" ]; then
    sendreport
  fi

  scriptend=$(date +%s)
  scripttime=$(echo "$scriptend" - "$scriptstart" | bc)
  status "Script finished in $(duration "$scripttime")"
  
  exit_safe "$scriptstatus"

}

init() {

  scriptstart=$(date +%s)
  scriptstatus=0

  loadconfig

  read -r -a sshoptions <<< "$options"
  sshoptions+=(-n -o "ConnectTimeout=$connecttimeout" -o BatchMode=yes)

  if ! mkdir -p -- "$(dirname -- "$tmpfile")" "$(dirname -- "$logfile")" "$(dirname -- "$lockfile")"; then
    errorprint "Failed to create directories for \"$tmpfile\", \"$logfile\" and \"$lockfile\"."
    exit 1
  fi
  if [ -f "$logfile" ] && [ "$(stat -c %s -- "$logfile")" -gt "$logmaxsize" ]; then
    mv -f -- "$logfile" "$logfile.1"
  fi
  if ! touch -- "$tmpfile" "$logfile"; then
    errorprint "Failed to write to \"$tmpfile\" or \"$logfile\"."
    exit 1
  fi

  status "Monitor Services Watch - Starting - $0"
  if ! [ -f "$configfile" ]; then
    status "Configuration file not found: \"$configfile\" - Using defaults."
  fi

  cmdcheck

  # The lock belongs to this process and is released by the system when it ends, also when it's killed.
  if ! exec 9>>"$lockfile"; then
    error "Failed to open lockfile: \"$lockfile\"."
    exit 1
  fi
  if ! flock -n 9; then
    error "Script is already running, it holds the lock on: $lockfile."
    exit 1
  fi

}

exit_safe() {

  debug "exit_safe()"

  exit "${1:-0}"

}

#  Check that we got all the needed commands

cmdcheck() {

  debug "cmdcheck()"

  cmds="awk bc cut date dirname flock grep mkdir mktemp mutt mv ping sed ssh stat timeout touch tput"
  for cmd in $cmds
  do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      error "Missing \"${cmd}\" command!"
      exit_safe 1
    fi
  done

  debug "cmdcheck() finished"

}

inetstatus() {

  debug "inetstatus()"

  inetwasdowntext=

  inetup=0
  for inettesthost in $inettesthosts
  do
    if ping -c 1 -W "${pingtimeout}" "${inettesthost}" >/dev/null 2>&1; then
      inetup=1
      break
    fi
  done

  entry=$(state_get INETDOWN)

  if [ "$inetup" -eq 0 ]; then
    status "Internet connection was found to be down."
    if [ "$entry" = "" ]; then
      echo "INETDOWN Time=$(date +%s)" >>"$tmpfile"
      debug "Internet was found to be down - Writing to ${tmpfile}"
    else
      debug "Internet was found to be down - Existing info found in ${tmpfile}"
    fi
    exit_safe 1
  fi

  status "Internet connection found to be up."
  if ! [ "$entry" = "" ]; then
    state_remove INETDOWN
    entrytime=$(echo "$entry" | sed -e 's/.* Time=\(.*\).*/\1/g' | cut -d' ' -f1)
    if isnum "$entrytime" ; then
      time=$(( $(date +%s) - entrytime ))
      inetwasdowntext="Internet was down $(duration "$time")"
    else
      inetwasdowntext="Internet was down - Failed to calculate downtime."
    fi
    status "$inetwasdowntext"
  fi

  debug "inetstatus() finished"

}

serviceswatch() {

  debug "serviceswatch()"

  while IFS= read -r l
  do
    if [ "$l" = "" ]; then
      continue
    fi

    uhp=$(echo "$l" | awk '{ print $1}')
    read -r -a services <<< "$(echo "$l" | cut -d ' ' -f2-)"

    if [[ $uhp == ?*:?* ]]; then
      userhost=$(echo "$uhp" | cut -d':' -f1)
      port=$(echo "$uhp" | cut -d':' -f2)
      hostoptions=("${sshoptions[@]}" -p "$port")
    else
      userhost=$uhp
      port=22
      hostoptions=("${sshoptions[@]}")
    fi

    if [[ $userhost == ?*@?* ]]; then
      user=$(echo "$userhost" | cut -d'@' -f1)
      host=$(echo "$userhost" | cut -d'@' -f2)
    else
      user=root
      host=$userhost
    fi

    status "Host: $host User: $user - Port: $port UserHost: $userhost - Services: ${services[*]}"

    status=
    fail=0
    failtime=0
    services_status=
    services_status_html=

    readfile

    # All services are checked over one connection. is-active prints one line per service and fails if any is not active, ssh itself fails with 255 and timeout with 124.
    states=$(timeout "$sshtimeout" ssh "${hostoptions[@]}" "$userhost" systemctl is-active "${services[@]}" 2>/dev/null)
    r=$?
    mapfile -t statelist <<< "$states"

    for i in "${!services[@]}"
    do
      service="${services[i]}"
      if [ "$r" -eq 255 ] || [ "$r" -eq 124 ]; then
        status="unreachable"
      elif [ "${statelist[i]:-}" = "active" ]; then
        status="up"
      elif [ "${statelist[i]:-}" = "" ]; then
        status="unknown"
      else
        status="down"
      fi
      if ! [ "$status" = "up" ]; then
        fail=1
        if [ "$failtime" -le 1 ]; then
          failtime=$(date +%s)
        fi
      fi
      status "Host: $host - Service: $service - Status: $status"
      servicesstatus_add
    done

    servicesdata="$servicesdata
Host: $host - ${services_status_html}<br />"

    writefile

  done <<< "$hosts"

  debug "serviceswatch() finished"

}
    
readfile() {

  debug "readfile()"
  
  entryfail=0
  failtime=0
  reporttime=0
  entrytime=0
  entry_services_status=

  entry=$(state_get "$host")
  if [ "$entry" = "" ]; then
    return
  fi
  entry_services_status=$(echo "$entry" | cut -d' ' -f2)
  if [ "$entry_services_status" = "" ]; then
    entry=
    return
  fi

  entryfail=$(echo "$entry" | cut -d' ' -f3)
  if [ "$entryfail" = "" ] || ! isnum "$entryfail"; then
    entry=
    entry_services_status=
    entryfail=0
    return
  fi

  failtime=$(echo "$entry" | cut -d' ' -f4)
  if [ "$failtime" = "" ] || ! isnum "$failtime"; then
    entry=
    entry_services_status=
    entryfail=0
    failtime=0
    return
  fi

  reporttime=$(echo "$entry" | cut -d' ' -f5)
  if [ "$reporttime" = "" ] || ! isnum "$reporttime"; then
    entry=
    entry_services_status=
    entryfail=0
    failtime=0
    reporttime=0
    return
  fi

  entrytime=$(echo "$entry" | cut -d' ' -f6)
  if [ "$entrytime" = "" ] ||  ! isnum "$entrytime"; then
    entry=
    entry_services_status=
    entryfail=0
    entrytime=0
    failtime=0
    reporttime=0
    return
  fi
  
  timenow=$(date +%s)
  time=$(echo "$timenow" - "$entrytime" | bc)
  debug "Entry with timestamp \"${entrytime}\" ($(duration "$time") ago) found for host \"$host\". Status: $entry_services_status Fail: $entryfail FailTime: $failtime ReportTime: $reporttime"
  
  debug "readfile() finished"

}

servicesstatus_add() {

  debug "servicesstatus_add()"

  if [ "${services_status}" = "" ]; then
    services_status="$service=$status"
    if [ "$status" = "up" ]; then
      services_status_html="<b>$service</b>=<font color=\"green\">$status</font>"
    else
      services_status_html="<b>$service</b>=<font color=\"red\">$status</font>"
    fi
  else
    services_status="${services_status},$service=$status"
    if [ "$status" = "up" ]; then
      services_status_html="${services_status_html} <b>$service</b>=<font color=\"green\">$status</font>"
    else
      services_status_html="${services_status_html} <b>$service</b>=<font color=\"red\">$status</font>"
    fi
  fi

  debug "servicesstatus_add() finished"

}

writefile() {

  debug "writefile()"
  

  timenow=$(date +%s)
  failtime_bc=$(echo "$timenow" - "$failtime" | bc)
  reporttime_bc=$(echo "$timenow" - "$reporttime" | bc)

  if [ "$entry" = "" ]; then
    entrytime=$(date +%s)
    summary_add "This is the first services watch for \"$host\"."
    sendreport=1
    reporttime=$(date +%s)
  elif [ "$fail" -eq 1 ] && [ "$failtime_bc" -ge "$maxfailtime" ]; then
    entryfail=1
    summary_add "One or more services on \"$host\" failed for more than $(duration "$maxfailtime")."
    if [ "$reporttime_bc" -ge "$reportfreq" ]; then
      sendreport=1
      reporttime=$(date +%s)
    fi
  elif [ "$fail" -eq 0 ] && [ "$entryfail" -eq 1 ]; then
    entryfail=0
    summary_add "\"$host\" restored from one or more failed services."
    failtime=0
    sendreport=1
    reporttime=$(date +%s)
  fi

  if [ "$fail" -eq 0 ]; then
    entryfail=0
    failtime=0
  fi

  if [ "$entrytime" -le 0 ]; then
    entrytime=$(date +%s)
  fi

  state_remove "$host"
  echo "${host} ${services_status} ${entryfail} ${failtime} ${reporttime} ${entrytime}" >>"$tmpfile"

  debug "writefile() finished"

}

summary_add() {

  local text
  text=$(html_escape "$1")

  if [ "$summary" = "" ]; then
    summary="$text<br />"
  else
    summary="$summary
    $text<br />"
  fi

}

report_add() {

  if [ "$reportdata" = "" ]; then
    reportdata="$1"
  else
    reportdata="$reportdata
    $1"
  fi

}

sendreport() {

  debug "sendreport()"

  status "Sending monitor services watch report..."

  scriptend=$(date +%s)
  scripttime=$(echo "$scriptend" - "$scriptstart" | bc)
  reporttime=$(date +%s)

  report_add "<html>"
  report_add "<body>"
  report_add "<h1>Monitor Services Watch</h1>"
  if ! [ "$inetwasdowntext" = "" ]; then
    report_add "<p>$inetwasdowntext</p>"
  fi
  if ! [ "$summary" = "" ]; then
    report_add "<p>$summary</p>"
  fi
  report_add "Status:<br />"
  report_add "$servicesdata"
  report_add "<br />"
  report_add "New report is sent every $(duration "$reportfreq") if status is changed or there is an error.<br />"

  report_add "</body>"
  report_add "</html>"

  read -r -a recipients <<< "$emailto"

  LANG=en_GB
  if ! EMAIL=$emailfrom timeout "$mailtimeout" mutt -e 'set content_type=text/html' -s "Monitor Services Watch" "${recipients[@]}" <<EOT
  $reportdata
EOT
  then
    error "Failed to send report to $emailto."
    scriptstatus=1
  fi

  debug "sendreport() finished"

}

main "$@"
