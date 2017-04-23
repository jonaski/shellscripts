#!/bin/sh
#
#  webwatch.sh - Monitor Web Watch
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
#  $Id$
#

configfile="/etc/sysconfig/webwatch"
lockfile="/tmp/webwatch.lock"
lockfilettl=3600
tmpfile="/tmp/webwatch.tmp"
logfile="/tmp/webwatch.log"
log=1
debug=1
emailfrom="nobody"
emailto="root"
emailevery=120
pingtimeout=2
inettesthosts="8.8.8.8 8.8.4.4"

websites="
http://www.jkvinge.net/ <address>Apache Server at www.jkvinge.net Port 80</address>
https://secure.jkvinge.net/ <title>secure.jkvinge.net</title>
https://mail.jkvinge.net/src/login.php <tr><td align=\"left\"><center><input type=\"submit\" value=\"Login\" />
http://teamviewer.jkvinge.net/ <h2>TeamViewer Remote Assistance</h2>
http://files.jkvinge.net/ <address>Apache Server at files.jkvinge.net Port 80</address>
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

exit_safe() {
  debug "exit_safe()"
  rm -f $lockfile
  exit $?
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

#  Check that we got all the needed commands

cmdcheck() {

  debug "cmdcheck()"

  cmds="which cat cut tr sed grep bc cp mv rm mkdir date hostname mail ssh tput ping curl mutt"
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
      rm -f ${tmpfile} || exit_safe 1
      touch ${tmpfile} || exit_safe 1
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

webwatch() {

  debug "webwatch()"

  IFS_DEFAULT=$IFS
  IFS=$'\n'
  for l in ${websites}
  do
    IFS=$IFS_DEFAULT
    if [ "$l" = "" ]; then
      continue
    fi
    url=$(echo $l | awk '{print $1}')
    if [ "$url" = "" ]; then
        continue
    fi
    url2=$(echo $url | sed 's/\//\\\//g')
    match=$(echo "$l" | cut -d ' ' -f2-)
    if [ "$match" = "" ]; then
      continue
    fi
    readfile
    status=""
    result=""
    output=$(curl -sSf --insecure $url 2>&1)
    if ! [ $? -eq 0 ]; then
      exitstatus=$?
      status=down
      result=$(echo $output | sed 's/curl: (.*) //g')
      result_html="<font color=\"red\">${result} <br /> ${exitstatus}</font>"
      fail=1
    else
      curl -sSf --insecure $url | grep -i "$match" >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        status=up
        result="Up and running"
        result_html="<font color=\"green\">Up and running</font>"
      else
        status=down
        result="Wrong content"
        result_html="<font color=\"red\">Wrong content</font>"
        fail=1
      fi
    fi
    status "Website: $url Result: $result"
    statuscheck
    writefile
    
    maildata="$maildata
Website: $url - ${result_html}<br />"
    
  done
  
  debug "webwatch() finished"

}

readfile() {

  debug "readfile()"

  entry=$(grep -i "^Website: ${url}: Result: .* Time=.*" ${tmpfile})
  if [ "$entry" = "" ]; then
    entrytime=0
    changed=1
  else
    entrytime=$(echo $entry | sed -e 's/.* Time=\(.*\).*/\1/g' | cut -d' ' -f1)
    if [ "$entrytime" = "" ]; then
      entrytime=0
    fi
  fi
  
  debug "readfile() finished"
  
}

statuscheck() {

  debug "statuscheck()"

  entrych=$(echo $entry | grep -i "^Website: ${url}: Result: ${result} Time=.*")
  if [ "$entrych" = "" ]; then
    changed=1
  else
    changed=0
  fi
  
  debug "statuscheck() finished"

}

writefile() {

  debug "writefile()"

  timenow=$(date +%s)
  time=$(echo $timenow - $entrytime | bc)

  if [ \( "$fail" = "1" -a "$time" -gt "$emailevery" \) -o "$changed" = "1" ]; then
    sendreport=1
    entrytime=$(date +%s)
  fi
  
  if [ "$entrytime" -le 0 ]; then
    entrytime=$(date +%s)
  fi
  
  sed -i "s/^Website: ${url2}: Result:.*$//g" $tmpfile
  sed -i '/^$/d' $tmpfile
  echo "Website: ${url}: Result: ${result} Time=$timenow" >>$tmpfile
  
  debug "writefile() finished"

}

summary_add() {

  #count_summary=$(echo $count_summary + 1 | bc)
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

  status "Sending monitor web watch report..."

  scriptend=$(date +%s)
  scripttime=$(echo $scriptend - $scriptstart | bc)
  reporttime=$(date +%s)

  report_add "<html>"
  report_add "<body>"
  report_add "<h1>Monitor Web Watch</h1>"
  if ! [ "$inetwasdowntext" = "" ]; then
    report_add "<p>$inetwasdowntext</p>"
  fi
  report_add "<br />"
  report_add "Status:<br />"
  report_add "$maildata"
  report_add "<br />"
  report_add "New report is sent every $(date -u -d @${emailevery} +"%T") if status is changed or there is an error."

  LANG=en_GB
  EMAIL=$emailfrom mutt -e 'set content_type=text/html' -s "Monitor Web Watch" $emailto <<EOT
  $reportdata
EOT

  debug "sendreport() finished"

}

status "Monitor Web Watch - Starting - $0"

scriptstart=$(date +%s)

loadconfig
lockfile -r 0 -l 3600 $lockfile || exit 1
touch $tmpfile || exit_safe 1
touch $logfile || exit_safe 1

cmdcheck
inetstatus
webwatch
if [ "$sendreport" = "1" ]; then
  sendreport
fi

scriptend=$(date +%s)
scripttime=$(echo $scriptend - $scriptstart | bc)
status "Script finished in $(date -u -d @${scripttime} +"%T")"

exit_safe 0
