#!/bin/bash
#
#  syswatch.sh - Monitor System Watch
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

configfile="/etc/sysconfig/syswatch"
if [ "$EUID" -eq 0 ]; then
  statedir="/var/lib/syswatch"
  logfile="/var/log/syswatch.log"
else
  statedir="$HOME/.local/state/syswatch"
  logfile="$statedir/syswatch.log"
fi
lockfile="$statedir/syswatch.lock"
tmpfile="$statedir/syswatch.state"
logmaxsize=1048576				# The log is moved to .1 when it's bigger than this.
debug=0
reportfreq=180
pingtimeout=2
connecttimeout=2
options=""					# Extra options for ssh.
sshtimeout=30
inettesthosts="8.8.8.8 8.8.4.4"
emailfrom="nobody"
emailto="root"
mailtimeout=60

maxcpu=70.00
maxhdd=90
maxmem=90

memfailreporttime=60
cpufailreporttime=60
hddfailreporttime=60

hosts="server1 server2 server3 server4"
filesystems="/boot / /usr /opt /var /home /usr/local /tmp /srv /share/MD0_DATA /mnt/HDA_ROOT /mnt/ext"

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

human_print() {

  while read -r B _; do
    [ "$B" -lt 1024 ] && echo "${B}" && break
    KB=$(((B+512)/1024))
    [ "$KB" -lt 1024 ] && echo "${KB}K" && break
    MB=$(((KB+512)/1024))
    [ "$MB" -lt 1024 ] && echo "${MB}M" && break
    GB=$(((MB+512)/1024))
    [ "$GB" -lt 1024 ] && echo "${GB}G" && break
    TB=$(((GB+512)/1024))
    echo "${TB}T"
    break
  done

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

  status "Monitor System Watch - Starting - $0"
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

main() {

  init "$@"

  inetstatus
  syswatch

  if [ "$sendreport" = "1" ]; then
    sendreport
  fi

  scriptend=$(date +%s)
  scripttime=$(echo "$scriptend" - "$scriptstart" | bc)
  status "Script finished in $(duration "$scripttime")"

  exit_safe "$scriptstatus"

}

exit_safe() {

  debug "exit_safe()"

  exit "${1:-0}"

}

#  Check that we got all the needed commands

cmdcheck() {

  debug "cmdcheck()"

  cmds="awk bc cut date dirname flock grep mkdir mktemp mutt mv ping sed ssh stat timeout touch tput tr"
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

syswatch() {

  debug "syswatch()"
  
  for uhp in ${hosts}
  do
    if [[ $uhp == ?*@?* ]]; then
      user=$(echo "$uhp" | cut -d'@' -f1)
      hostport=$(echo "$uhp" | cut -d'@' -f2)
    else
      user=
      hostport=$uhp
    fi

    if [[ $hostport == ?*:?* ]]; then
      host=$(echo "$hostport" | cut -d':' -f1)
      port=$(echo "$hostport" | cut -d':' -f2)
      hostoptions=("${sshoptions[@]}" -p "$port")
    else
      host=$hostport
      port=22
      hostoptions=("${sshoptions[@]}")
    fi
    if [ "$user" = "" ]; then
      hostuh="${host}"
    else
      hostuh="${user}@${host}"
    fi

    debug "Starting syswatch for \"$host\"."

    hostfail=0
    hostsummary=0
    havefree=0
    havesar=0
    havedf=0
    sshfail=0
    sshresult=
    sshtext=
    report=0

    hostchkcmds

    if [ "$sshfail" = "1" ]; then
      debug "SSH command failure for \"$host\": ${sshtext}"
    fi

    readfile
    cpuload
    memusage
    hddusage
    writefile

    if [ "$report" -eq 1 ]; then
      sendreport=1
    fi

    status "Status: $host - CPU: ${cpuload}% Mem: ${memusage}% HDD: $hddusage"

  done
  
  debug "syswatch() finished"
  
}

sshfail() {

  sshfail=1

  if [ "$sshresult" = "" ]; then
    sshresult="SSH connection failure."
  fi
  if [ "$sshtext" = "" ]; then
    sshtext=$sshresult
  fi

}

remote() {
  timeout "$sshtimeout" ssh "${hostoptions[@]}" "$hostuh" "$@"
}

# Find the commands on the host over one connection. The remote output is only used after checking that it looks like a path.

hostchkcmds() {

  debug "hostchkcmds()"

  havefree=0
  havedf=0
  havesar=0

  # shellcheck disable=SC2016
  if ! sshresult=$(remote 'PATH="$PATH:/opt/bin"; for c in sar free df; do p=$(command -v "$c") && echo "$c $p"; done; echo "version $("$(command -v free)" --version 2>&1 | head -n 1)"' 2>&1); then
    sshfail
    return 1
  fi

  local cmd cmdpath freepath=""
  while read -r cmd cmdpath
  do
    if [ "$cmd" = "version" ]; then
      if [[ $cmdpath == "free from procps"* ]] && [ -n "$freepath" ]; then
        FREE=$freepath
        havefree=1
      fi
    elif ! [[ $cmdpath =~ ^/[A-Za-z0-9._/+-]+$ ]]; then
      debug "Ignoring invalid path for \"$cmd\" on host \"$host\"."
    elif [ "$cmd" = "sar" ]; then
      SAR=$cmdpath
      havesar=1
    elif [ "$cmd" = "df" ]; then
      DF=$cmdpath
      havedf=1
    elif [ "$cmd" = "free" ]; then
      freepath=$cmdpath
    fi
  done <<< "$sshresult"

  if ! [ "$havesar" -eq 1 ]; then
    error "Host \"$host\" Missing correct version of \"sar\" command!"
  fi
  if ! [ "$havefree" -eq 1 ]; then
    error "Host \"$host\" Missing correct version of \"free\" command!"
  fi
  if ! [ "$havedf" -eq 1 ]; then
    error "Host \"$host\" Missing correct version of \"df\" command!"
  fi

  debug "hostchkcmds() finished"

}

# CPU LOAD

cpuload() {

  debug "cpuload()"

  cpuload="?"
  cpustatus=
  cpustatus_check=
  cpuload_html=

  if [ "$sshfail" = "1" ]; then
    text="SSH command failure for \"$host\": ${sshtext}"
    summary_add "$text"
    status "$text"
    cpuload_fail "FAIL"
    cpuload_html="<b>CPU:</b> <font color=\"red\">$(html_escape "$sshtext")</font>"
    return
  fi
  if ! [ "$havesar" -eq 1 ]; then
    text="Missing sar command for \"$host\"."
    summary_add "$text"
    status "$text"
    cpuload_fail "FAIL"
    cpuload_html="<b>CPU:</b> <font color=\"red\">Missing SAR command!</font>"
    return
  fi

  if ! sshresult=$(remote env LC_ALL=C "$SAR" -P ALL 1 2 2>&1); then
    text="SSH command failure for \"$host\": ${sshresult}"
    summary_add "$text"
    status "$text"
    cpuload_fail "FAIL"
    cpuload_html="<b>CPU:</b> <font color=\"red\">$(html_escape "$sshresult")</font>"
    return
  fi
  idle=$(echo "$sshresult" | grep 'Average.*all' | awk '{print $NF}')
  if ! [[ $idle =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    cpuload="?"
    text="Failed to read CPU load on \"$host\"."
    summary_add "$text"
    status "$text"
    cpuload_fail "FAIL"
    cpuload_html="<b>CPU:</b> <font color=\"red\">Failed to read CPU load.</font>"
    return
  fi
  cpuload=$(awk -v idle="$idle" 'BEGIN { print 100.0 - idle }')
  if [ 1 -eq "$(echo "${cpuload} >= ${maxcpu}" | bc)" ]; then
    text="CPU threshold (${maxcpu}) exceeded for host \"$host\", CPU load is ${cpuload}."
    summary_add "$text"
    status "$text"
    cpuload_fail "ERROR"
    cpuload_html="<b>CPU:</b> <font color=\"red\">${cpuload}%</font>"
  else
    cpustatus="OK"
    cpustatus_check="OK"
    cpufailtime=0
    cpuload_html="<b>CPU:</b> <font color=\"green\">${cpuload}%</font>"
    debug "CPU load for host \"$host\" is within threshold."
    if [ "$cpuprevstatus" = "ERROR" ]; then
      text="Host \"$host\" restored from high CPU usage."
      debug "$text"
      summary_add "$text"
      report=1
    elif [ "$cpuprevstatus" = "FAIL" ]; then
      text="Host \"$host\" restored from CPU status failure."
      debug "$text"
      summary_add "$text"
      report=1
    fi
  fi

  debug "cpuload() finished"

}

cpuload_fail() {

  if [ "$1" = "" ]; then
    cpustatus="ERROR"
  else
    cpustatus=$1
  fi
  cpustatus_check="OK"

  if [ "$cpufailtime" -le 0 ]; then
    timenow=$(date +%s)
    cpufailtime=$timenow
    debug "Zero CPU failure time for host \"$host\", setting CPU failure time to NOW ($timenow)."
  fi
  timenow=$(date +%s)
  time=$(echo "$timenow" - "$cpufailtime" | bc)
  if [ "$time" -ge "$cpufailreporttime" ]; then
    hostfail=1
    cpustatus_check=$cpustatus
    debug "CPU failure for host \"$host\" longer than CPU fail report time $(duration "$cpufailreporttime"), CPU fail time is $(duration "$time")."
  fi

}

# MEM USAGE

memusage() {

  debug "memusage()"

  memstatus=
  memstatus_check=
  memusage=0
  memtotal=0
  used=0
  free=0
  total=0

  if [ "$sshfail" -eq 1 ]; then
    text="SSH command failure for \"$host\": ${sshtext}"
    summary_add "$text"
    status "$text"
    memusage_fail "FAIL"
    memusage_html="<b>Mem:</b> <font color=\"red\">$(html_escape "$sshtext")</font>"
    return
  fi
  if ! [ "$havefree" -eq 1 ]; then
    text="Missing correct free command for \"$host\"."
    summary_add "$text"
    status "$text"
    memusage_fail "FAIL"
    memusage_html="<b>Mem:</b> <font color=\"red\">Missing FREE command!</font>"
    return
  fi

  if ! sshresult=$(remote "$FREE" -b 2>&1); then
    text="SSH command failure for \"$host\": ${sshresult}"
    summary_add "$text"
    status "$text"
    memusage_fail "FAIL"
    memusage_html="<b>Mem:</b> <font color=\"red\">$(html_escape "$sshresult")</font>"
    return
  fi

  count=0
  while IFS= read -r l
  do
    count=$(( count + 1 ))
    if [ "$l" = "" ]; then
      continue
    fi
    if [ "$count" -eq 1 ]; then
      column1=$(echo "$l" | awk '{print $1}')
      column6=$(echo "$l" | awk '{print $6}')
      continue
    fi
    
    row=$(echo "$l" | awk '{print $1}')
    param1=$(echo "$l" | awk '{print $2}')
    param2=$(echo "$l" | awk '{print $3}')
    param3=$(echo "$l" | awk '{print $4}')
    param6=$(echo "$l" | awk '{print $7}')
    
    if [ "$row" = "Mem:" ]; then
      if [ "$column1" = "total" ]; then
        total=$param1
      fi
      if [ "$column6" = "available" ]; then
        free=$param6
        if isnum "$total" && isnum "$free"; then
          used=$(echo "$total" - "$free" | bc)
	fi
      fi
    elif [ "$row" = "-/+" ] && [ "$param1" = "buffers/cache:" ] ; then
      used=$param2
      free=$param3
    else
      continue
    fi
  done <<< "$sshresult"

  if ! isnum "$used" || ! isnum "$free" || ! isnum "$total" || [ "$total" -le 0 ]; then
    text="Failed to calculate memory usage on \"$host\"."
    summary_add "$text"
    status "$text"
    memusage_fail "FAIL"
    memusage_html="<b>Mem:</b> <font color=\"red\">Failed to calculate memory usage.</font>"
    return
  fi
  
  memusage=$(echo "${used} * 100 / ${total}" | bc)
  memtotal=$(echo "$total" | human_print)
  if [ "$memusage" -ge "$maxmem" ]; then
    text="Memory usage threshold (${maxmem}) exceeded for host \"$host\", memory usage is ${memusage}."
    summary_add "$text"
    status "$text"
    memusage_fail "ERROR"
    memusage_html="<b>Mem:</b> <font color=\"red\">${memusage}% / ${memtotal}</font>"
  else
    memstatus="OK"
    memstatus_check="OK"
    memfailtime=0
    memusage_html="<b>Mem:</b> <font color=\"green\">${memusage}% / ${memtotal}</font>"
    debug "Memory usage for host \"$host\" is within threshold."
    if [ "$memprevstatus" = "FAIL" ]; then
      text="Host \"$host\" restored from memory status failure."
      debug "$text"
      summary_add "$text"
      report=1
    elif [ "$memprevstatus" = "ERROR" ]; then
      text="Host \"$host\" restored from high memory usage."
      debug "$text"
      summary_add "$text"
      report=1
    fi
  fi

  debug "memusage() finished"

}

memusage_fail() {

  if [ "$1" = "" ]; then
    memstatus="ERROR"
  else
    memstatus=$1
  fi
  memstatus_check="OK"

  if [ "$memfailtime" -le 0 ]; then
    timenow=$(date +%s)
    memfailtime=$timenow
    debug "Zero memory failure time for host \"$host\", setting memory failure time to NOW ($timenow)."
  fi
  timenow=$(date +%s)
  time=$(echo "$timenow" - "$memfailtime" | bc)
  if [ "$time" -ge "$memfailreporttime" ]; then
    hostfail=1
    memstatus_check=$memstatus
    debug "Memory failure for host \"$host\" longer than memory failure report time $(duration "$memfailreporttime"), memory failure time is $(duration "$time")."
  fi

}

hddusage() {

  debug "hddusage()"

  hddfail=0
  hddstatus="OK"
  hddstatus_check="OK"
  hddstatus_line=
  hddusage_html=
  hddusage=
  hddcount=0

  if [ "$sshfail" -eq 1 ]; then
    text="SSH command failure for \"$host\": ${sshtext}"
    summary_add "$text"
    status "$text"
    hddusage_fail "FAIL"
    hddusage_html="<b>HDD:</b> <font color=\"red\">$(html_escape "$sshtext")</font><br />"
    return
  fi
  if ! [ "$havedf" -eq 1 ]; then
    text="Missing correct df command for \"$host\"."
    summary_add "$text"
    status "$text"
    hddusage_fail "FAIL"
    hddusage_html="<b>HDD:</b> <font color=\"red\">Missing DF command!</font><br />"
    return
  fi

  # Ignore the status from df, it can return an error even if there are valid results. It's a failure if none of the filesystems could be read, checked below.
  sshresult=$(remote env LC_ALL=C "$DF" -hP 2>&1)

  while IFS= read -r l
  do
    if [ "$l" = "" ]; then
      continue
    fi
    total=$(echo "$l" | awk '{print $2}')
    used=$(echo "$l" | awk '{print $3}')
    use=$(echo "$l" | awk '{print $5}' | sed 's/%//g')
    filesystem=$(echo "$l" | awk '{print $6}')
    
    if ! isnum "$use"; then
      continue
    fi

    found=0
    for x in ${filesystems}
    do
      if [ "${x}" = "${filesystem}" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      continue
    fi

    hddcount=$(( hddcount + 1 ))

    if [ "$use" -ge "$maxhdd" ]; then
      text="HDD usage threshold (${maxhdd}) exceeded for host \"$host\" on partition \"${filesystem}\", HDD usage is ${use}%."
      summary_add "$text"
      status "$text"
      hddusage_fail "ERROR"
    else
      debug "HDD usage for host \"$host\" partition \"${filesystem}\" is within threshold."
    fi

    if [ "$hddusage" = "" ]; then
      hddusage="$filesystem=$use% ($used / $total)"
      if [ "$use" -ge "$maxhdd" ]; then
        hddstatus_line="$filesystem=ERROR"
        hddusage_html="<b>HDD:</b><br />  <b>$filesystem</b> <font color=\"red\">$use% ($used / $total)</font><br />"
      else
        hddstatus_line="$filesystem=OK"
        hddusage_html="<b>HDD:</b><br />  <b>$filesystem</b> <font color=\"green\">$use% ($used / $total)</font><br />"
      fi
    else
      hddusage="$hddusage $filesystem=$use% ($used / $total)"
      if [ "$use" -ge "$maxhdd" ]; then
        hddstatus_line="$hddstatus_line,$filesystem=ERROR"
        hddusage_html="$hddusage_html  <b>$filesystem</b> <font color=\"red\">$use% ($used / $total)</font><br />"
      else
        hddstatus_line="$hddstatus_line,$filesystem=OK"
        hddusage_html="$hddusage_html  <b>$filesystem</b> <font color=\"green\">$use% ($used / $total)</font><br />"
      fi
    fi

  done <<< "$sshresult"

  if [ "$hddcount" -eq 0 ]; then
    text="Failed to read HDD usage on \"$host\": ${sshresult}"
    summary_add "$text"
    status "$text"
    hddusage_fail "FAIL"
    hddusage_html="<b>HDD:</b> <font color=\"red\">Failed to read HDD usage: $(html_escape "$sshresult")</font><br />"
    return
  fi

  if [ "$hddfail" -ne 1 ]; then
    hddfailtime=0
    debug "HDD usage for all partitions on host \"$host\" are within threshold."
    if [ "$hddprevstatus" = "FAIL" ]; then
      text="Host \"$host\" restored from HDD status failure."
      summary_add "$text"
      status "$text"
      report=1
    elif [ "$hddprevstatus" = "ERROR" ]; then
      text="Host \"$host\" restored from high HDD usage."
      summary_add "$text"
      status "$text"
      report=1
    fi
  fi
  
  debug "hddusage() finished"

}

hddusage_fail() {

  hddfail=1

  if [ "$1" = "" ]; then
    hddstatus="ERROR"
  else
    hddstatus=$1
  fi
  hddstatus_check="OK"

  if [ "$hddfailtime" -le 0 ]; then
    timenow=$(date +%s)
    hddfailtime=$timenow
    debug "Zero HDD failure time for host \"$host\", setting HDD failure time to NOW ($timenow)."
  fi
  timenow=$(date +%s)
  time=$(echo "$timenow" - "$hddfailtime" | bc)
  if [ "$time" -ge "$hddfailreporttime" ]; then
    debug "HDD failure for host \"$host\" partition \"${filesystem}\" longer than HDD failure report time $(duration "$hddfailreporttime"), HDD failure time is $(duration "$time")."
    hddstatus_check=$hddstatus
    hostfail=1
  fi

}

readfile() {

  debug "readfile()"

  cpuprevstatus="Unknown"
  memprevstatus="Unknown"
  hddprevstatus="Unknown"
  cpufailtime=0
  memfailtime=0
  hddfailtime=0
  reporttime=0
  entrytime=0

  entry=$(state_get "$host")
  if [ "$entry" = "" ]; then
    debug "No entry found for \"$host\"."
    summary_add "This is the first system watch for \"$host\"."
    report=1
    return
  fi

  for token in $entry
  do
   
    if [ "$token" = "$host" ]; then
      continue
    fi
   
    var=$(echo "$token" | cut -d'=' -f1)
    data=$(echo "$token" | cut -d'=' -f2)
    
    if [ "$var" = "" ] || [ "$data" = "" ]; then
      debug "Invalid entry \"$token\" in entry file."
      continue
    fi

    if [ "$var" = "CPU" ]; then
      cpuprevstatus=$data
      continue
    elif [ "$var" = "Mem" ]; then
      memprevstatus=$data
      continue
    elif [ "$var" = "HDD" ]; then
      hddprevstatus=$data
      continue
    elif [ "$var" = "CPUFailTime" ] && isnum "$data"; then
      cpufailtime=$data
      continue
    elif [ "$var" = "MemFailTime" ] && isnum "$data"; then
      memfailtime=$data
      continue
    elif [ "$var" = "HDDFailTime" ] && isnum "$data"; then
      hddfailtime=$data
      continue
    elif [ "$var" = "ReportTime" ] && isnum "$data"; then
      reporttime=$data
      continue
    elif [ "$var" = "Time" ] && isnum "$data"; then
      entrytime=$data
      continue
    fi

  done
  
  timenow=$(date +%s)
  time=$(echo "$timenow" - "$entrytime" | bc)
  debug "Entry with timestamp \"${entrytime}\" ($(duration "$time") ago) found for host \"$host\". CPUPrevStatus: $cpuprevstatus CPUFailTime: $cpufailtime MemPrevStatus: $memprevstatus MemFailTime: $memfailtime HDDPrevStatus: $hddprevstatus HDDFailTime: $hddfailtime ReportTime: $reporttime."

  debug "readfile() finished"

}

writefile() {

  debug "writefile()"

  timenow=$(date +%s)
  reporttime_bc=$(echo "$timenow" - "$reporttime" | bc)

  if [ "$entry" = "" ]; then
    entrytime=$(date +%s)
    report=1
    sendreport=1
    reporttime=$(date +%s)
  elif [ "$hostfail" -eq 1 ] && [ "$reporttime_bc" -ge "$reportfreq" ]; then
    report=1
    sendreport=1
    reporttime=$(date +%s)
  fi

  if [ "$entrytime" -le 0 ]; then
    entrytime=$(date +%s)
  fi

  state_remove "$host"
  timenow=$(date +%s)
  echo "${host} CPU=${cpustatus_check} CPUFailTime=${cpufailtime} Mem=${memstatus_check} MemFailTime=${memfailtime} HDD=${hddstatus_check} ${hddstatus_line} HDDFailTime=${hddfailtime} ReportTime=${reporttime} Time=${entrytime}" >>"$tmpfile"

  syswatch="$syswatch
Host: ${host}<br />
${cpuload_html}<br />
${memusage_html}<br />
${hddusage_html}<br />
"

  debug "writefile() finished"

}

summary_add() {

  if [ "$hostsummary" -eq 1 ]; then
    return 1
  fi
  hostsummary=1

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

  status "Sending monitor system watch report..."

  scriptend=$(date +%s)
  scripttime=$(echo "$scriptend" - "$scriptstart" | bc)
  reporttime=$(date +%s)

  report_add "<html>"
  report_add "<body>"
  report_add "<h1>Monitor System Watch</h1>"
  if ! [ "$inetwasdowntext" = "" ]; then
    report_add "<p>$inetwasdowntext</p>"
  fi
  if ! [ "$summary" = "" ]; then
    report_add "<p>"
    report_add "<h2>Summary:</h2>"
    report_add "$summary"
    report_add "</p>"  
  fi

  report_add "<p>"
  report_add "<h2>Status:</h2>"
  report_add "$syswatch"
  report_add "</p>"
  report_add "<p>"
  report_add "Script finished in $(duration "$scripttime")<br />"
  report_add "New report is sent if status has changed or every $(duration "$reportfreq") if there is an error.<br />"
  report_add "</p>"
  report_add "</body>"
  report_add "</html>"

  read -r -a recipients <<< "$emailto"

  LANG=en_GB
  if ! EMAIL=$emailfrom timeout "$mailtimeout" mutt -e 'set content_type=text/html' -s "Monitor System Watch" "${recipients[@]}" <<EOT
  $reportdata
EOT
  then
    error "Failed to send report to $emailto."
    scriptstatus=1
  fi

  debug "sendreport() finished"

}

main "$@"
