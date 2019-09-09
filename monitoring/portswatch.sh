#!/bin/sh
#
#  portswatch.sh - Monitor Ports Watch
#  Copyright (C) 2010 Jonas Kvinge
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
lockfile="/tmp/portswatch.lock"
lockfilettl=3600
tmpfile="/tmp/portswatch.tmp"
logfile="/tmp/portswatch.log"
log=1
debug=1
inettesthosts="8.8.8.8 8.8.4.4"			# Test all of these, only if 1 fails internet is reported to be down.
pingtimeout=2
connecttimeout=2
maxfailtime=15
reportfreq=120
emailfrom="nobody"
emailto="root"

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
    tput setaf $color
  fi
  echo "[$TS] $@"
  if [ -t 1 ]; then
    tput sgr0
  fi
  color=0
}
log() {
  timestamp
  echo "[$TS] $@" >>${logfile}
}
statusprint() { color=8; print $@; }
statuslog() { log $@; }
errorprint() {
  timestamp
  if [ -t 1 ]; then
    tput bold
    tput setaf 1
  fi
  echo "[$TS] ERROR: $@" >&2
  if [ -t 1 ]; then
    tput sgr0
  fi
  color=0
}
errorlog() { log "ERROR: $@"; }
status() { statusprint $@; statuslog $@; }
error() { errorprint $@; errorlog $@; }
debug() {
  if [ "$debug" = "1" ]; then
    color=3
    print $@
    log $@
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

  init $@
  
  cmdcheck
  inetstatus
  portswatch
  
  if [ "$sendreport" = "1" ]; then
    sendreport
  fi

  scriptend=$(date +%s)
  scripttime=$(echo $scriptend - $scriptstart | bc)
  status "Script finished in $(date -u -d @${scripttime} +"%T")"
  
  exit_safe 0

}

init() {

  scriptstart=$(date +%s)
  havelockfile=0

  status "Monitor Ports Watch - Starting - $0"

  loadconfig

  if [ -f "$lockfile" ]; then
    error "Script is already running. If this is incorrect, remove: $lockfile."
    exit_safe
  fi
  which lockfile >/dev/null 2>&1
  if [ $? -eq 0 ] ; then
    lockfile -r 0 -l $lockfilettl $lockfile || { exit_safe 1; }
  else
    touch $lockfile || { exit_safe 1; }
  fi
  havelockfile=1

  touch $tmpfile || exit_safe 1
  touch $logfile || exit_safe 1

}

exit_safe() {

  debug "exit_safe()"
  
  if [ "$havelockfile" -eq 1 ]; then
    rm -f $lockfile
  fi

  exit $?
}

#  Check that we got all the needed commands

cmdcheck() {

  debug "cmdcheck()"

  cmds="which cat cut tr sed grep bc cp mv rm mkdir date hostname ssh tput ping nc mutt"
  for cmd in $cmds
  do
    which $cmd >/dev/null 2>&1
    if [ $? != 0 ] ; then
      echo "ERROR: Missing \"${cmd}\" command!"
      exit_safe 1
    fi
  done
  
  debug "cmdcheck() finished"
  
}

inetstatus() {

  debug "inetstatus()"

  inetwasdown=
  inetwasdowntext=

  inetup=0
  for inettesthost in $inettesthosts
  do
    pingtext=$(ping -c 1 -W ${pingtimeout} ${inettesthost})
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
      inetwasdown=1
      #rm -f ${tmpfile} || exit_safe 1
      #touch ${tmpfile} || exit_safe 1
      sed -i "/^INETDOWN .*$/d" ${tmpfile}
      timenow=$(date +%s)
      entrytime=$(echo $entry | sed -e 's/.* Time=\(.*\).*/\1/g' | cut -d' ' -f1)
      if isnum "$entrytime" ; then
        time=$(echo $timenow - $entrytime | bc)
        timetext=$(date -u -d @${time} +"%T")
        inetwasdowntext="Internet was down $timetext"
        status $inetwasdowntext
      else
        inetwasdowntext="Internet was down - Failed to calculate downtime."
        status $inetwasdowntext
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

portswatch() {

  debug "portswatch()"

  i=0
  IFS_DEFAULT=$IFS
  IFS=$'\n'
  for l in ${hosts}
  do
    IFS=$IFS_DEFAULT
    if [ "$l" = "" ]; then
      continue
    fi
    host=$(echo $l | awk '{ print $1}')
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
      port=$(echo "$portent" | cut -d '/' -f1)
      protocol=$(echo "$portent" | cut -d '/' -f2)
      status "Checking host: $host - port: $portent"
      if [ "$protocol" = "tcp" ]; then
        nc -zw ${connecttimeout} $host $port
      elif [ $protocol = "udp" ]; then
        nc -zuw ${connecttimeout} $host $port
      else
        continue
      fi
      if [ $? -eq 0 ]; then # Port is up
        status="up"
	status "Host: $host - Port: $portent - Status: Up"
      else
        status="down"
        status "Host: $host - Port: $portent - Status: Down"
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
  done
  
  debug "portswatch() finished"
  
}
    
readfile() {

  debug "readfile()"

  entryfail=0
  failtime=0
  reporttime=0
  entrytime=0
  entry_ports_status=

  entry=$(grep -i "^$host .*" ${tmpfile})
  if [ "$entry" = "" ]; then
    return
  fi
  entry_ports_status=$(echo $entry | cut -d' ' -f2)
  if [ "$entry_ports_status" = "" ]; then
    entry=
    return
  fi

  entryfail=$(echo $entry | cut -d' ' -f3)
  if [ "$entryfail" = "" ] || ! isnum "$entryfail"; then
    entry=
    entry_ports_status=
    entryfail=0
    return
  fi

  failtime=$(echo $entry | cut -d' ' -f4)
  if [ "$failtime" = "" ] || ! isnum "$failtime"; then
    entry=
    entry_ports_status=
    entryfail=0
    failtime=0
    return
  fi

  reporttime=$(echo $entry | cut -d' ' -f5)
  if [ "$reporttime" = "" ] || ! isnum "$reporttime"; then
    entry=
    entry_ports_status=
    entryfail=0
    failtime=0
    reporttime=0
    return
  fi

  entrytime=$(echo $entry | cut -d' ' -f6)
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
  time=$(echo $timenow - $entrytime | bc)
debug "Entry with timestamp \"${entrytime}\" ($(date -u -d @${time} +"%T") ago) found for host \"$host\". Status: $entry_ports_status Fail: $entryfail FailTime: $failtime ReportTime: $reporttime"
  
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
  
  echo "$entry" | grep -i "^$host ${ports_status} .*" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    changed=0
  else
    changed=1
  fi

  timenow=$(date +%s)
  failtime_bc=$(echo $timenow - $failtime | bc)
  reporttime_bc=$(echo $timenow - $reporttime | bc)

  debug "Host: $host - Changed=$changed"

  if [ "$entry" = "" ]; then
    entrytime=$(date +%s)
    summary_add "This is the first ports watch for \"$host\"."
    sendreport=1
    reporttime=$timenow
  elif [ "$fail" -eq 1 ] && [ "$failtime_bc" -ge "$maxfailtime" ]; then
    entryfail=1
    summary_add "One or more ports on \"$host\" failed for more than $(date -u -d @$maxfailtime +"%T")."
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

  sed -i "/^${host} .*$/d" ${tmpfile}
  echo "${host} ${ports_status} ${entryfail} ${failtime} ${reporttime} ${entrytime}" >>${tmpfile}

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

  status "Sending monitor ports watch report..."

  scriptend=$(date +%s)
  scripttime=$(echo $scriptend - $scriptstart | bc)
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
  report_add "New report is sent every $(date -u -d @${reportfreq} +"%T") if status is changed or there is an error."
  report_add "</body>"
  report_add "</html>"

  LANG=en_GB
  EMAIL=$emailfrom mutt -e 'set content_type=text/html' -s "Monitor Ports Watch" $emailto <<EOT
  $reportdata
EOT

  debug "sendreport() finished"

}

main
exit_safe 0
