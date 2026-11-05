#!/bin/bash
#
#  portswatch.sh - Monitor Ports Watch
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

configfile="/etc/sysconfig/portswatch"
if [ "$EUID" -eq 0 ]; then
  statedir="/var/lib/portswatch"
  logfile="/var/log/portswatch.log"
else
  statedir="$HOME/.local/state/portswatch"
  logfile="$statedir/portswatch.log"
fi
lockfile="$statedir/portswatch.lock"
tmpfile="$statedir/portswatch.state"
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

hosts="
server1 ssh/tcp domain/udp domain/tcp smtp/tcp imaps/tcp pop3s/tcp http/tcp https/tcp
server2 ssh/tcp domain/udp domain/tcp smtp/tcp http/tcp https/tcp
server3 ssh/tcp domain/udp domain/tcp smtp/tcp
server4 ssh/tcp domain/udp domain/tcp smtp/tcp
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
  portswatch

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

  status "Monitor Ports Watch - Starting - $0"
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

  cmds="awk bc cut date dig dirname flock grep mkdir mktemp mutt mv nc ping sed stat timeout touch tput"
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

portswatch() {

  debug "portswatch()"

  while IFS= read -r l
  do
    if [ "$l" = "" ]; then
      continue
    fi
    host=$(echo "$l" | awk '{ print $1}')
    ports=$(echo "$l" | cut -d ' ' -f2-)
    status=
    fail=0
    failtime=0
    ports_status=
    ports_status_html=
    debug "Host: $host - Ports: $ports"
    readfile
    for portent in $ports
    do
      status "Checking host: $host - port: $portent"
      portcheck "$portent"
      if [ "$status" = "up" ]; then
        status "Host: $host - Port: $portent - Status: Up"
      else
        status "Host: $host - Port: $portent - Status: ${status^}"
        fail=1
        if [ "$failtime" -le 1 ]; then
          failtime=$(date +%s)
        fi
      fi
      portsstatus_add
    done

    portswatchdata="$portswatchdata
Host: $host - ${ports_status_html} <br />"

    writefile
  done <<< "$hosts"

  debug "portswatch() finished"

}

# Check one port and set status. UDP has no connection to test, so nc only notices a port that actively refuses and reports everything else as up. DNS is tested with a real query instead.

portcheck() {

  local port protocol
  port=$(echo "$1" | cut -d '/' -f1)
  protocol=$(echo "$1" | cut -d '/' -f2)

  status="down"
  case "$protocol" in
    tcp)
      if timeout "$((connecttimeout + 1))" nc -zw "$connecttimeout" "$host" "$port" >/dev/null 2>&1; then
        status="up"
      fi
      ;;
    udp)
      if [ "$port" = "domain" ] || [ "$port" = "53" ]; then
        if timeout "$((connecttimeout + 1))" dig +time="$connecttimeout" +tries=1 "@$host" . SOA >/dev/null 2>&1; then
          status="up"
        fi
      elif timeout "$((connecttimeout + 1))" nc -zuw "$connecttimeout" "$host" "$port" >/dev/null 2>&1; then
        status="up"
      fi
      ;;
    *)
      error "Invalid protocol in \"$1\" for host \"$host\", use tcp or udp."
      status="invalid"
      ;;
  esac

}
    
readfile() {

  debug "readfile()"

  entryfail=0
  failtime=0
  reporttime=0
  entrytime=0
  entry_ports_status=

  entry=$(state_get "$host")
  if [ "$entry" = "" ]; then
    return
  fi
  entry_ports_status=$(echo "$entry" | cut -d' ' -f2)
  if [ "$entry_ports_status" = "" ]; then
    entry=
    return
  fi

  entryfail=$(echo "$entry" | cut -d' ' -f3)
  if [ "$entryfail" = "" ] || ! isnum "$entryfail"; then
    entry=
    entry_ports_status=
    entryfail=0
    return
  fi

  failtime=$(echo "$entry" | cut -d' ' -f4)
  if [ "$failtime" = "" ] || ! isnum "$failtime"; then
    entry=
    entry_ports_status=
    entryfail=0
    failtime=0
    return
  fi

  reporttime=$(echo "$entry" | cut -d' ' -f5)
  if [ "$reporttime" = "" ] || ! isnum "$reporttime"; then
    entry=
    entry_ports_status=
    entryfail=0
    failtime=0
    reporttime=0
    return
  fi

  entrytime=$(echo "$entry" | cut -d' ' -f6)
  if [ "$entrytime" = "" ] ||  ! isnum "$entrytime"; then
    entry=
    entry_ports_status=
    entryfail=0
    entrytime=0
    failtime=0
    reporttime=0
    return
  fi

  timenow=$(date +%s)
  time=$(echo "$timenow" - "$entrytime" | bc)
debug "Entry with timestamp \"${entrytime}\" ($(duration "$time") ago) found for host \"$host\". Status: $entry_ports_status Fail: $entryfail FailTime: $failtime ReportTime: $reporttime"
  
  debug "readfile() finished"
  
}

portsstatus_add() {

  debug "portsstatus_add()"

  if [ "${ports_status}" = "" ]; then
    ports_status="$portent=$status"
    if [ "$status" = "up" ]; then
      ports_status_html="<b>$portent</b>=<font color=\"green\">$status</font>"
    else
      ports_status_html="<b>$portent</b>=<font color=\"red\">$status</font>"
    fi
  else
    ports_status="${ports_status},$portent=$status"
    if [ "$status" = "up" ]; then
      ports_status_html="${ports_status_html} <b>$portent</b>=<font color=\"green\">$status</font>"
    else
      ports_status_html="${ports_status_html} <b>$portent</b>=<font color=\"red\">$status</font>"
    fi
  fi
  
  debug "portsstatus_add() finished"

}

writefile() {

  debug "writefile()"
  
  debug "ports_status_____ : $ports_status"
  debug "entry_ports_status: $entry_ports_status"
  

  timenow=$(date +%s)
  failtime_bc=$(echo "$timenow" - "$failtime" | bc)
  reporttime_bc=$(echo "$timenow" - "$reporttime" | bc)

  if [ "$entry" = "" ]; then
    entrytime=$(date +%s)
    summary_add "This is the first ports watch for \"$host\"."
    sendreport=1
    reporttime=$timenow
  elif [ "$fail" -eq 1 ] && [ "$failtime_bc" -ge "$maxfailtime" ]; then
    entryfail=1
    summary_add "One or more ports on \"$host\" failed for more than $(duration "$maxfailtime")."
    if [ "$reporttime_bc" -ge "$reportfreq" ]; then
      sendreport=1
      reporttime=$timenow
    fi
  elif [ "$fail" -eq 0 ] && [ "$entryfail" -eq 1 ]; then
    entryfail=0
    summary_add "\"$host\" restored from one or more failed ports."
    failtime=0
    sendreport=1
    reporttime=$timenow
  fi

  if [ "$fail" -eq 0 ]; then
    entryfail=0
    failtime=0
  fi

  if [ "$entrytime" -le 0 ]; then
    entrytime=$(date +%s)
  fi

  state_remove "$host"
  echo "${host} ${ports_status} ${entryfail} ${failtime} ${reporttime} ${entrytime}" >>"$tmpfile"

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

  status "Sending monitor ports watch report..."

  scriptend=$(date +%s)
  scripttime=$(echo "$scriptend" - "$scriptstart" | bc)
  reporttime=$(date +%s)

  report_add "<html>"
  report_add "<body>"
  report_add "<h1>Monitor Ports Watch</h1>"
  if ! [ "$inetwasdowntext" = "" ]; then
    report_add "<p>$inetwasdowntext</p>"
  fi
  if ! [ "$summary" = "" ]; then
    report_add "<p>$summary</p>"
  fi
  report_add "Status:<br />"
  report_add "$portswatchdata"
  report_add "<br />"
  report_add "New report is sent every $(duration "$reportfreq") if status is changed or there is an error."
  report_add "</body>"
  report_add "</html>"

  read -r -a recipients <<< "$emailto"

  LANG=en_GB
  if ! EMAIL=$emailfrom timeout "$mailtimeout" mutt -e 'set content_type=text/html' -s "Monitor Ports Watch" "${recipients[@]}" <<EOT
  $reportdata
EOT
  then
    error "Failed to send report to $emailto."
    scriptstatus=1
  fi

  debug "sendreport() finished"

}

main "$@"
