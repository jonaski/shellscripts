#!/bin/bash
#
#  syswatch.sh - Monitor System Watch
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

configfile="/etc/sysconfig/syswatch"
hostname=$(hostname -s)
lockfile="/tmp/syswatch.lock"
lockfilettl=3600
tmpfile="/tmp/syswatch.tmp"
logfile="/tmp/syswatch.log"
log=1
debug=1
reportfreq=180
pingtimeout=2
connecttimeout=2
options="-o ConnectTimeout=${connecttimeout}"
inettesthosts="8.8.8.8 8.8.4.4"
emailfrom="nobody"
emailto="root"

maxcpu=70.00
maxhdd=90
maxmem=90

memfailreporttime=0
cpufailreporttime=5
hddfailreporttime=0

hosts="server1 server2 server3 server4"
filesystems="/boot / /usr /opt /var /home /usr/local /tmp /srv /share/MD0_DATA /mnt/HDA_ROOT /mnt/ext"

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

human_print(){

  while read B dummy; do
    [ $B -lt 1024 ] && echo "${B}" && break
    KB=$(((B+512)/1024))
    [ $KB -lt 1024 ] && echo "${KB}K" && break
    MB=$(((KB+512)/1024))
    [ $MB -lt 1024 ] && echo "${MB}M" && break
    GB=$(((MB+512)/1024))
    [ $GB -lt 1024 ] && echo "${GB}G" && break
    TB=$(((GB+512)/1024))
    echo "${TB}T"
    break
  done

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

init() {

  scriptstart=$(date +%s)
  havelockfile=0
  
  status "Monitor System Watch - Starting - $0"

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

main() {

  init $@

  cmdcheck
  inetstatus
  syswatch

  if [ "$sendreport" = "1" ]; then
    sendreport
  fi

  scriptend=$(date +%s)
  scripttime=$(echo $scriptend - $scriptstart | bc)
  status "Script finished in $(date -u -d @${scripttime} +"%T")"

  exit_safe 0

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

  cmds="test which cat cut tr sed grep bc cp mv rm mkdir date hostname ssh tput curl mutt ps head sort sar touch ping"
  for cmd in $cmds
  do
    which $cmd >/dev/null 2>&1
    if [ $? != 0 ] ; then
      error "Missing \"${cmd}\" command!"
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

syswatch() {

  debug "syswatch()"
  
  cpuerrors=0
  memerrors=0
  hddhosterrors=0
  hdderrors=0

  i=0
  #IFS_DEFAULT=$IFS
  #IFS=$'\n'
  for l in ${hosts}
  do
    #IFS=$IFS_DEFAULT
    i=$(echo $i +1 | bc)
    if [ "$l" = "" ]; then
      continue
    fi
    hostuh=$(echo $l | awk '{ print $1}')
    user=$(echo $hostuh | cut -d'@' -f1)
    host=$(echo $hostuh | cut -d'@' -f2)

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
    uname=

    hostchkcmds

    sshresult=$(ssh $options $hostuh uname -a 2>&1)
    if [ $? -eq 0 ]; then
      uname=$sshresult
    else
      sshfail
    fi

    if [ "$sshfail" = "1" ]; then
      debug "SSH command failure for \"$host\": ${sshtext}"
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

hostchkcmds() {

  debug "hostchkcmds()"

  havefree=0
  havedf=0
  havesar=0

  sshresult=$(ssh $options $hostuh echo '$PATH' | sed 's/:/ /g')
  if [ $? -eq 0 ] ; then
    paths="$sshresult /opt/bin"
  else
    sshfail
    return 1
  fi

  for cmd in sar free df
  do

    CMD=$(echo "$cmd" | tr /a-z/ /A-Z/)
    found=0

    for path in $paths
    do
      cmdpath=$path/$cmd

      ssh $options $hostuh test -x $cmdpath >/dev/null 2>&1
      if ! [ $? -eq 0 ] ; then
        continue
      fi

      if [ "$cmd" = "free" ] && ! [ "$havefree" -eq 1 ]; then
        sshresult=$(ssh $options $hostuh $cmdpath --version 2>&1 | head -n1)
        if [ $? -eq 0 ] ; then
          echo "$sshresult" | grep "^free from procps.*$" >/dev/null 2>&1
          if [ $? -eq 0 ] ; then
            eval ${CMD}="$cmdpath"
            found=1
            havefree=1
            break
          fi
        fi
      elif [ "$cmd" = "df" ] && ! [ "$havedf" -eq 1 ]; then
        #sshresult=$(ssh $options $hostuh $cmdpath --version 2>&1 | head -n1)
        #if [ $? -eq 0 ] ; then
          #echo "$sshresult" | grep "^df (GNU coreutils) .*$" >/dev/null 2>&1
          #if [ $? -eq 0 ] ; then
            found=1
            eval ${CMD}="$cmdpath"
            havedf=1
            break
	  #fi
        #fi
      elif [ "$cmd" = "sar" ] && ! [ "$havesar" -eq 1 ]; then
        found=1
        eval ${CMD}="$cmdpath"
        havesar=1
        break
      fi
    done
    if ! [ "$found" -eq 1 ]; then
      error "Host \"$host\" Missing correct version of \"${cmd}\" command!"
    fi

  done
  
  debug "hostchkcmds() finished"
  
}

# CPU LOAD

cpuload() {

  debug "cpuload()"

  cpufail=0
  cpustatus=
  cpustatus_check=
  cpuload_html=

  if [ "$sshfail" = "1" ]; then
    text="SSH command failure for \"$host\": ${sshtext}"
    summary_add "$text"
    status $text
    cpuload_fail "FAIL"
    cpuload_html="<b>CPU:</b> <font color=\"red\">${sshtext}</font>"
    return
  fi
  if ! [ "$havesar" -eq 1 ]; then
    text="Missing sar command for \"$host\"."
    summary_add "$text"
    status $text
    cpuload_fail "FAIL"
    cpuload_html="<b>CPU:</b> <font color=\"red\">Missing SAR command!</font>"
    return
  fi

  sshresult=$(ssh $options $hostuh $SAR -P ALL 1 2 2>&1)
  if ! [ $? -eq 0 ]; then
    text="SSH command failure for \"$host\": ${sshresult}"
    summary_add "$text"
    status $text
    cpuload_fail "FAIL"
    cpuload_html="<b>CPU:</b> <font color=\"red\">${sshresult}</font>"
    return
  fi
  cpuload=$(echo $sshresult | grep 'Average.*all' | awk -F" " '{print 100.0 -$NF}')
  if [ 1 -eq "$(echo "${cpuload} >= ${maxcpu}" | bc)" ]; then
    text="CPU threshold (${maxcpu}) exceeded for host \"$host\", CPU load is ${cpuload}."
    summary_add "$text"
    status $text
    cpuload_fail "ERROR"
    cpuload_html="<b>CPU:</b> <font color=\"red\">${cpuload}%</font>"
  else
    cpufail=0
    cpustatus="OK"
    cpustatus_check="OK"
    cpufailtime=0
    cpuload_html="<b>CPU:</b> <font color=\"green\">${cpuload}%</font>"
    debug "CPU load for host \"$host\" is within threshold."
    if [ "$cpuprevstatus" = "ERROR" ]; then
      text="Host \"$host\" restored from high CPU usage."
      debug $text
      summary_add "$text"
      report=1
    elif [ "$cpuprevstatus" = "FAIL" ]; then
      text="Host \"$host\" restored from CPU status failure."
      debug $text
      summary_add "$text"
      report=1
    fi
  fi

  debug "cpuload() finished"

}

cpuload_fail() {

  cpufail=1
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
  time=$(echo $timenow - $cpufailtime | bc)
  if [ "$time" -ge "$cpufailreporttime" ]; then
    hostfail=1
    cpustatus_check=$cpustatus
    debug "CPU failure for host \"$host\" longer than CPU fail report time $(date -u -d @$cpufailreporttime +"%T"), CPU fail time is $(date -u -d @$time +"%T")."
  fi

  cpuerrors=$(echo $cpuerrors + 1 | bc)

}

# MEM USAGE

memusage() {

  debug "memusage()"

  memstatus=
  memstatus_check=
  memusage=0
  memtotal=0
  memfail=0
  used=0
  free=0
  total=0

  if [ "$sshfail" -eq 1 ]; then
    text="SSH command failure for \"$host\": ${sshtext}"
    summary_add "$text"
    status $text
    memusage_fail "FAIL"
    memusage_html="<b>Mem:</b> <font color=\"red\">${sshtext}</font>"
    return
  fi
  if ! [ "$havefree" -eq 1 ]; then
    text="Missing correct free command for \"$host\"."
    summary_add "$text"
    status $text
    memusage_fail "FAIL"
    memusage_html="<b>Mem:</b> <font color=\"red\">Missing FREE command!</font>"
    return
  fi

  sshresult=$(ssh $options $hostuh $FREE -b 2>&1)
  if ! [ $? -eq 0 ]; then
    text="SSH command failure for \"$host\": ${sshresult}"
    summary_add "$text"
    status $text
    memusage_fail "FAIL"
    memusage_html="<b>Mem:</b> <font color=\"red\">${sshresult}</font>"
    return
  fi
  #echo $sshresult >/tmp/debug-df-$host

  count=0
  IFS_DEFAULT=$IFS
  IFS=$'\n'
  for l in ${sshresult}
  do
    count=$(echo $count +1 | bc)
    IFS=$IFS_DEFAULT
    if [ "$l" = "" ]; then
      continue
    fi
    if [ $count -eq 1 ]; then
      column1=$(echo $l | awk '{print $1}')
      column2=$(echo $l | awk '{print $2}')
      column3=$(echo $l | awk '{print $3}')
      column4=$(echo $l | awk '{print $4}')
      column5=$(echo $l | awk '{print $5}')
      column6=$(echo $l | awk '{print $6}')
      continue
    fi
    
    row=$(echo $l | awk '{print $1}')
    param1=$(echo $l | awk '{print $2}')
    param2=$(echo $l | awk '{print $3}')
    param3=$(echo $l | awk '{print $4}')
    param4=$(echo $l | awk '{print $5}')
    param5=$(echo $l | awk '{print $6}')
    param6=$(echo $l | awk '{print $7}')
    
    if [ "$row" = "Mem:" ]; then
      if [ "$column1" = "total" ]; then
        total=$param1
      fi
      if [ "$column6" = "available" ]; then
        free=$param6
        if isnum "$total" && isnum "$free"; then
          used=$(echo $total - $free | bc)
	fi
      fi
    elif [ "$row" = "-/+" ] && [ "$param1" = "buffers/cache:" ] ; then
      used=$param2
      free=$param3
    else
      continue
    fi
  done
  
  if ! isnum "$used" || ! isnum "$free" || ! isnum "$total"; then
    text="Failed to calculate memory usage on \"$host\"."
    summary_add "$text"
    status $text
    memusage_fail "FAIL"
    memusage_html="<b>Mem:</b> <font color=\"red\">Failed to calculate memory usage.</font>"
    return
  fi
  
  memusage=$(echo ${used}*100 / ${total} | bc)
  memtotal=$(echo $total | human_print)
  if [ "$memusage" -ge "$maxmem" ]; then
    text="Memory usage threshold (${maxmem}) exceeded for host \"$host\", memory usage is ${memusage}."
    summary_add "$text"
    status $text
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
      debug $text
      summary_add "$text"
      report=1
    elif [ "$memprevstatus" = "ERROR" ]; then
      text="Host \"$host\" restored from high memory usage."
      debug $text
      summary_add "$text"
      report=1
    fi
  fi

  debug "memusage() finished"

}

memusage_fail() {

  memfail=1
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
  time=$(echo $timenow - $memfailtime | bc)
  if [ "$time" -ge "$memfailreporttime" ]; then
    hostfail=1
    memstatus_check=$memstatus
    debug "Memory failure for host \"$host\" longer than memory failure report time $(date -u -d @$memfailreporttime +"%T"), memory failure time is $(date -u -d @$time +"%T")."
  fi
  
  memerrors=$(echo $memerrors + 1 | bc)

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
    text="SSH command failure for \"$host\": ${sshtext}"
    summary_add "$text"
    status $text
    hddusage_fail "FAIL"
    hddusage_html="<b>HDD:</b> <font color=\"red\">${sshtext}</font><br />"
    return
  fi
  if ! [ "$havedf" -eq 1 ]; then
    text="Missing correct df command for \"$host\"."
    summary_add "$text"
    status $text
    hddusage_fail "FAIL"
    hddusage_html="<b>HDD:</b> <font color=\"red\">Missing DF command!</font><br />"
    return
  fi

  sshresult=$(ssh $options $hostuh $DF -h 2>&1)
  if ! [ $? -eq 0 ]; then
    # Ignore DF command error, sometimes it returns error messages even if there are valid results.
    text="DF command failure for \"$host\": ${sshresult}"
    #summary_add "$text"
    #status $text
    #hddusage_fail "FAIL"
    #hddusage_html="<b>HDD:</b> <font color=\"red\">${sshresult}</font><br />"
    #return
  fi

  IFS_DEFAULT=$IFS
  IFS=$'\n'
  for l in ${sshresult}
  do
    IFS=$IFS_DEFAULT
    hddcount=$(echo $hddcount +1 | bc)
    #if [ "$hddcount" -eq 1 ]; then
      #continue
    #fi
    if [ "$l" = "" ]; then
      continue
    fi
    device=$(echo $l | awk '{print $1}')
    total=$(echo $l | awk '{print $2}')
    used=$(echo $l | awk '{print $3}')
    avail=$(echo $l | awk '{print $4}')
    use=$(echo $l | awk '{print $5}' | sed 's/%//g')
    # | tr -d %
    filesystem=$(echo $l | awk '{print $6}')
    
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

    if [ "$use" -ge "$maxhdd" ]; then
      text="HDD usage threshold (${maxhdd}) exceeded for host \"$host\" on partition \"${filesystem}\", HDD usage is ${use}%."
      summary_add "$text"
      status $text
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

  done

  if [ "$hddfail" -ne 1 ]; then
    hddfailtime=0
    debug "HDD usage for all partitions on host \"$host\" are within threshold."
    if [ "$hddprevstatus" = "FAIL" ]; then
      text="Host \"$host\" restored from HDD status failure."
      summary_add "$text"
      status $text
      report=1
    elif [ "$hddprevstatus" = "ERROR" ]; then
      text="Host \"$host\" restored from high HDD usage."
      summary_add "$text"
      status $text
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
  time=$(echo $timenow - $hddfailtime | bc)
  if [ "$time" -ge "$hddfailreporttime" ]; then
    debug "HDD failure for host \"$host\" partition \"${filesystem}\" longer than HDD failure report time $(date -u -d @$hddfailreporttime +"%T"), HDD failure time is $(date -u -d @$time +"%T")."
    hddstatus_check=$hddstatus
    hostfail=1
  fi
  
  hdderrors=$(echo $hdderrors + 1 | bc)
  if [ "$hddfail" -ne 1 ]; then
    hddhosterrors=$(echo $hddhosterrors + 1 | bc)
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
  changed=0

  entry=$(grep -i "^${host} .*" ${tmpfile})
  if [ "$entry" = "" ]; then
    debug "No entry found for \"$host\"."
    summary_add "This is the first system watch for \"$host\"."
    report=1
    return
  fi

  for token in $entry
  do
   
    if [ $token = "$host" ]; then
      continue
    fi
   
    var=$(echo $token | cut -d'=' -f1)
    data=$(echo $token | cut -d'=' -f2)
    
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
  time=$(echo $timenow - $entrytime | bc)
  debug "Entry with timestamp \"${entrytime}\" ($(date -u -d @${time} +"%T") ago) found for host \"$host\". CPUPrevStatus: $cpuprevstatus CPUFailTime: $cpufailtime MemPrevStatus: $memprevstatus MemFailTime: $memfailtime HDDPrevStatus: $hddprevstatus HDDFailTime: $hddfailtime ReportTime: $reporttime."

  debug "readfile() finished"

}

writefile() {

  debug "writefile()"
  
  # The changed state is not in use anymore, keep it here for now.
  echo "$entry" | grep -i "^${host} CPU=${cpustatus_check} CPUFailTime=.* Mem=${memstatus_check} MemFailTime=.* HDD=${hddstatus_check} .* HDDFailTime=.* ReportTime=.* Time=.*"  >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    changed=0
  else
    changed=1
  fi

  timenow=$(date +%s)
  reporttime_bc=$(echo $timenow - $reporttime | bc)

  if [ "$entry" = "" ]; then
    entrytime=$(date +%s)
    report=1
  fi
  if [ "$hostfail" -eq 1 ] && [ "$reporttime_bc" -ge "$reportfreq" ]; then
    report=1
  fi
  
  if [ "$report" -eq 1 ]; then
    reporttime=$(date +%s)
  fi
  if [ "$entrytime" -le 0 ]; then
    entrytime=$(date +%s)
  fi

  sed -i "s/^${host} .*$//g" ${tmpfile}
  sed -i '/^$/d' ${tmpfile}
  timenow=$(date +%s)
  echo "${host} CPU=${cpustatus_check} CPUFailTime=${cpufailtime} Mem=${memstatus_check} MemFailTime=${memfailtime} HDD=${hddstatus_check} ${hddstatus_line} HDDFailTime=${hddfailtime} ReportTime=${reporttime} Time=${entrytime}" >>${tmpfile}

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

  status "Sending monitor system watch report..."

  scriptend=$(date +%s)
  scripttime=$(echo $scriptend - $scriptstart | bc)
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
  report_add "Script finished in $(date -u -d @${scripttime} +"%T")<br />"
  report_add "New report is sent if status has changed or every $(date -u -d @${reportfreq} +"%T") if there is an error.<br />"
  report_add "</p>"
  report_add "</body>"
  report_add "</html>"

  LANG=en_GB
  EMAIL=$emailfrom mutt -e 'set content_type=text/html' -s "Monitor System Watch" $emailto <<EOT
  $reportdata
EOT

  debug "sendreport() finished"

}

main
exit_safe 0
