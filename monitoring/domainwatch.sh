#!/bin/bash
#
#  domainwatch.sh - Monitor Domain Watch
#  Copyright (C) 2017-2026 Jonas Kvinge
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

configfile="/etc/sysconfig/domainwatch"
if [ "$EUID" -eq 0 ]; then
  statedir="/var/lib/domainwatch"
  logfile="/var/log/domainwatch.log"
else
  statedir="$HOME/.local/state/domainwatch"
  logfile="$statedir/domainwatch.log"
fi
lockfile="$statedir/domainwatch.lock"
tmpfile="$statedir/domainwatch.state"
logmaxsize=1048576				# The log is moved to .1 when it's bigger than this.
debug=0
inettesthosts="8.8.8.8 8.8.4.4"			# Internet is reported to be down only if all of these fail.
pingtimeout=2
reportfreq=3600
emailfrom="nobody"
emailto="root"
mailtimeout=60

domains="test1.com test2.com test3.com"
whoistimeout=30
availablepatterns='^% No match$|^No match for |^NOT FOUND|^Domain not found|^No Data Found|^No entries found|^Status: *(free|available)'	# Answers from registries when a domain is not registered.

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
  echo "[$TS] $*" >>"${logfile}"
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
  domainwatch

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

  status "Monitor Domain Watch - Starting - $0"
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

  cmds="awk bc cut date dirname flock grep mkdir mktemp mutt mv ping sed stat timeout touch tput whois"
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

domainwatch() {

  debug "domainwatch()"

  for domain in ${domains}
  do
    readfile
    available=0
    output=$(timeout "$whoistimeout" whois "$domain" 2>&1)
    r=$?
    if grep -Eqi -- "$availablepatterns" <<< "$output"; then
      status="available"
      result_html="<font color=\"green\">Available</font>"
      available=1
    elif [ "$r" -eq 0 ] && [ -n "$output" ]; then
      status="taken"
      result_html="<font color=\"red\">Taken</font>"
    else
      status="error"
      result_html="<font color=\"red\">Error</font>"
    fi

    status "Domain: $domain Status: $status"

    writefile

    maildata="$maildata
Domain: $domain - ${result_html}<br />"

  done

  debug "domainwatch() finished"

}

readfile() {

  debug "readfile()"

  reporttime=0
  entrytime=0
  entrystatus=

  entry=$(state_get "$domain")
  if [ "$entry" = "" ]; then
    return
  fi
  entrystatus=$(echo "$entry" | cut -d' ' -f2)
  if [ "$entrystatus" = "" ]; then
    entry=
    return
  fi

  reporttime=$(echo "$entry" | cut -d' ' -f3)
  if [ "$reporttime" = "" ] || ! isnum "$reporttime"; then
    entry=
    entrystatus=
    reporttime=0
    return
  fi
  entrytime=$(echo "$entry" | cut -d' ' -f4)
  if [ "$entrytime" = "" ] || ! isnum "$entrytime"; then
    entry=
    entrystatus=
    reporttime=0
    entrytime=0
    return
  fi

  timenow=$(date +%s)
  time=$(echo "$timenow" - "$entrytime" | bc)
debug "Entry with timestamp \"${entrytime}\" ($(duration "$time") ago) found for domain \"$domain\". Status: $entrystatus ReportTime: $reporttime"
  
  debug "readfile() finished"
  
}

writefile() {

  debug "writefile()"
  
  timenow=$(date +%s)
  reporttime_bc=$(echo "$timenow" - "$reporttime" | bc)

  if [ "$entry" = "" ]; then
    entrytime=$(date +%s)
    summary_add "This is the first domain watch for \"$domain\"."
    sendreport=1
    reporttime=$(date +%s)
  elif [ "$available" -eq 1 ]; then
    summary_add "Domain \"$domain\" is available."
    if [ "$reporttime_bc" -ge "$reportfreq" ]; then
      sendreport=1
      reporttime=$(date +%s)
    fi
  elif [ "$status" = "error" ]; then
    summary_add "Failed to look up domain \"$domain\": $output"
    if [ "$reporttime_bc" -ge "$reportfreq" ]; then
      sendreport=1
      reporttime=$(date +%s)
    fi
  fi

  if [ "$entrytime" -le 0 ]; then
    entrytime=$(date +%s)
  fi

  state_remove "$domain"
  echo "${domain} ${status} ${reporttime} ${entrytime}" >>"$tmpfile"

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

  status "Sending monitor domain watch report..."

  scriptend=$(date +%s)
  scripttime=$(echo "$scriptend" - "$scriptstart" | bc)
  reporttime=$(date +%s)

  report_add "<html>"
  report_add "<body>"
  report_add "<h1>Monitor domain Watch</h1>"
  if ! [ "$inetwasdowntext" = "" ]; then
    report_add "<p>$inetwasdowntext</p>"
  fi
  if ! [ "$summary" = "" ]; then
    report_add "<p>$summary</p>"
  fi
  report_add "<br />"
  report_add "Status:<br />"
  report_add "$maildata"
  report_add "<br />"
  report_add "New report is sent every $(duration "$reportfreq")."

  report_add "</body>"
  report_add "</html>"

  read -r -a recipients <<< "$emailto"

  LANG=en_GB
  if ! EMAIL=$emailfrom timeout "$mailtimeout" mutt -e 'set content_type=text/html' -s "Monitor domain Watch" "${recipients[@]}" <<EOT
  $reportdata
EOT
  then
    error "Failed to send report to $emailto."
    scriptstatus=1
  fi

  debug "sendreport() finished"

}

main "$@"
