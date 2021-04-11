#!/bin/sh
#
#  domainwatch.sh - Monitor Domain Watch
#  Copyright (C) 2017 Jonas Kvinge
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
lockfile="/tmp/domainwatch.lock"
lockfilettl=3600
tmpfile="/tmp/domainwatch.tmp"
logfile="/tmp/domainwatch.log"
#log=1
debug=1
inettesthosts="8.8.8.8 8.8.4.4"			# Test all of these, only if 1 fails internet is reported to be down.
pingtimeout=2
#maxfailtime=1
reportfreq=3600
emailfrom="nobody"
emailto="root"

domains="test1.com test2.com test3.com"

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
  echo "$1" | grep -E '^\-?[0-9]+$' >/dev/null 2>&1
  return $?
}

loadconfig() {

  if [ -f "$configfile" ]; then
    . $configfile || {
      error "Failed to load configuration file \"$configfile\"."
      exit_safe 1
   }
  else
    status "Configuration file not found: \"$configfile\" - Using defaults."
  fi

}

main() {

  init "$@"

  cmdcheck
  inetstatus
  domainwatch

  if [ "$sendreport" = "1" ]; then
    sendreport
  fi

  scriptend=$(date +%s)
  scripttime=$(echo "$scriptend" - "$scriptstart" | bc)
  status "Script finished in $(date -u -d @${scripttime} +"%T")"

  exit_safe 0

}

init() {

  scriptstart=$(date +%s)
  havelockfile=0
  
  status "Monitor Domain Watch - Starting - $0"

  loadconfig

  if [ -f "$lockfile" ]; then
    error "Script is already running. If this is incorrect, remove: $lockfile."
    exit_safe
  fi
  which lockfile >/dev/null 2>&1
  if [ $? -eq 0 ] ; then
    lockfile -r 0 -l "$lockfilettl" "$lockfile" || { exit_safe 1; }
  else
    touch "$lockfile" || { exit_safe 1; }
  fi
  havelockfile=1

  touch "$tmpfile" || exit_safe 1
  touch "$logfile" || exit_safe 1

}

exit_safe() {

  debug "exit_safe()"
  
  if [ "$havelockfile" -eq 1 ]; then
    rm -f "$lockfile"
  fi

  exit $?
}

#  Check that we got all the needed commands

cmdcheck() {

  debug "cmdcheck()"

  cmds="which cat cut tr sed grep bc cp mv rm mkdir date hostname mail ssh tput ping whois mutt"
  for cmd in $cmds
  do
    which "$cmd" >/dev/null 2>&1
    if [ $? != 0 ] ; then
      echo "ERROR: Missing \"${cmd}\" command!"
      exit_safe 1
    fi
  done

  debug "cmdcheck() finished"

}

inetstatus() {

  debug "inetstatus()"

  #inetwasdown=
  inetwasdowntext=
  
  inetup=0
  for inettesthost in $inettesthosts
  do
    pingtext=$(ping -c 1 -W "${pingtimeout}" "${inettesthost}")
    r=$?
    if [ $r = 0 ] ; then
      inetup=1
      break
    fi
  done
  
  if [ "$inetup" -eq 1 ]; then
    status "Internet connection found to be up."
    entry=$(grep -i "INETDOWN Time=.*" ${tmpfile})
    if ! [ "$entry" = "" ]; then
      #inetwasdown=1
      #rm -f ${tmpfile} || exit_safe 1
      #touch ${tmpfile} || exit_safe 1
      sed -i "/^INETDOWN .*$/d" ${tmpfile}
      timenow=$(date +%s)
      entrytime=$(echo "$entry" | sed -e 's/.* Time=\(.*\).*/\1/g' | cut -d' ' -f1)
      if isnum "$entrytime" ; then
        time=$(echo "$timenow" - "$entrytime" | bc)
        timetext=$(date -u -d @${time} +"%T")
        inetwasdowntext="Internet was down $timetext"
        status "$inetwasdowntext"
      else
        inetwasdowntext="Internet was down - Failed to calculate downtime."
        status "$inetwasdowntext"
        entrytime=0
      fi
    fi
    return $r
  else
    status "Internet connection was found to be down."
    entry=$(grep -i "INETDOWN Time=.*" ${tmpfile})
    if [ "$entry" = "" ]; then
      timenow=$(date +%s)
      echo "INETDOWN Time=${timenow}" >${tmpfile}
      debug "Internet was found to be down - Writing to ${tmpfile}"
    else
      debug "Internet was found to be down - Existing info found in ${tmpfile}"
    fi
    exit_safe $r
  fi
  return $r
  
  debug "inetstatus() finished"

}

domainwatch() {

  debug "domainwatch()"

  for domain in ${domains}
  do
    readfile
    status=
    available=0
    result_html=
    output=$(whois "$domain" 2>&1)
    if [ $? -eq 0 ]; then
      IFS_DEFAULT=$IFS
      IFS=$'\n'
      for line in $output
      do
        IFS=$IFS_DEFAULT
	echo "$line" | grep '^% No match$' >/dev/null 2>&1
        if [ $? -eq 0 ]; then
          status="available"
          result_html="<font color=\"green\">Available</font>"
          available=1
        fi
      done
      if [ "$status" = "" ]; then
        status="taken"
        result_html="<font color=\"red\">Taken</font>"
        available=0
      fi
    elif [ $? -eq 1 ]; then
      status="available"
      result_html="<font color=\"green\">Available</font>"
      available=1
    else
      status="error"
      result_html="<font color=\"red\">Error</font>"
      available=0
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

  #entryfail=0
  #failtime=0
  reporttime=0
  entrytime=0
  entrystatus=
  #entryresult=

  entry=$(grep -i "^${domain} .*" ${tmpfile})
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
debug "Entry with timestamp \"${entrytime}\" ($(date -u -d @${time} +"%T") ago) found for domain \"$domain\". Status: $entrystatus ReportTime: $reporttime"
  
  debug "readfile() finished"
  
}

writefile() {

  debug "writefile()"
  
  echo "$entry" | grep -i "^${domain} ${status} .*" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    changed=0
  else
    changed=1
  fi
  debug "domain: ${domain} - Changed=$changed"

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
  fi

  if [ "$entrytime" -le 0 ]; then
    entrytime=$(date +%s)
  fi

  sed -i "/^${domain} .*$/d" $tmpfile
  echo "${domain} ${status} ${reporttime} ${entrytime}" >>${tmpfile}

  debug "writefile() finished"

}

summary_add() {

  if [ "$summary" = "" ]; then
    summary="$1<br />"
  else
    summary="$summary
    $1<br />"
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
  report_add "New report is sent every $(date -u -d @${reportfreq} +"%T")."

  LANG=en_GB
  EMAIL=$emailfrom mutt -e 'set content_type=text/html' -s "Monitor domain Watch" $emailto <<EOT
  $reportdata
EOT

  debug "sendreport() finished"

}

main "$@"
exit_safe 0
