#!/bin/sh

# Global settings
# Refresh values using this interval
interval=$((5*60)) #seconds
# dusk/dawn margin
margin=$((15*60)) # seconds
# URL to post the target data to
pvoutputURL='http://pvoutput.org/service/r2/addstatus.jsp'

scriptDir="${0%/*}"
scriptName="${0##*/}"

usage () {
cat <<ENDOFUSAGE
Usage: $0 [config-file]
config-file must be
 - an absolute path
 - in the current directory
 - in the directory with the script
config-file must contain at minimum the following variables:
 - stationId (your GoodWe stationId)
 - apiKey    (your PVOutput apiKey)
 - sysId     (your PVOutput System ID)
 - latitude  (of your solar installation)
 - longitude (of your solar installation)
config-file can additionally contain these variables:
 - dailyRestart if set, script will exit after sunset
      add a daily cronjob to start it
 - outputPath (defaults to current directory)
      where yyyymmdd.csv files will be created
 - DEBUG (default empty)
      if not empty, log some additional output to goodwe2PVoutput
 - ONESHOT (default empty)
      run only once
ENDOFUSAGE
}

logErr () {
    echo "$*" >> ${outputPath}/${logFile}.err
}

logOut () {
    [ -z "${DEBUG}" ] && return
    echo "$*" >> ${outputPath}/${logFile}.log
} 

exitErr () {
    [ "${outputPath}" ] && logErr $*
    echo -e "\033[1;31mERROR: \033[0m\033[1m$*\033[0m"
    usage
    exit 1
} 

loadConfig () {
    local confFile="${1:-config.sh}"
    [ "${confFile}" = "${confFile%/*}" ] && confFile=`pwd`"/${confFile}"
    if   [ -f "${confFile}" ] ; then confFile="${confFile}"
    elif [ -f "${scriptDir}/${confFile}" ] ; then confFile="${scriptDir}/${confFile}"
    else exitErr "Config file ${confFile} not found"
    fi
    . "${confFile}"
    outputPath=${outputPath:-.}
    [ ${logFile:-unset} == "unset" ] && logFile="${scriptName%.*}"
    [ ${apiKey:-unset} == "unset" ] && exitErr "apiKey unset or empty"
    [ ${sysId:-unset} == "unset" ] && exitErr "sysId unset or empty"
    [ ${latitude:-unset} == "unset" ] && exitErr "latitude unset or empty"
    [ ${longitude:-unset} == "unset" ] && exitErr "longitude unset or empty"
    [ ${CSVdir:-unset} == "unset" ] && exitErr "CSVdir unset or empty"
    [ -n "${timezone}" ] && export TZ=${timezone}
}

loadPVOutput () {
    # Parse the stored payload
    [ ! -f "${CSVdir}/${today}.csv" ] && return 1
    for item in $(tail -n1 "${CSVdir}/${today}.csv"); do
        cnt=$((cnt+1))
        case "$cnt" in
            1) logdate=${item};;
            2) logtime=${item%,};;
            3) todaykWh=${item%,};;
            4) inVolt=${item%,};;
            5) inAmp=${item%,};;
            6) inWatt=${item%,};;
            7) outVolt=${item%,};;
            8) outAmp=${item%,};;
            9) temperature=${item%,};;
        esac
    done
}

uploadPVOutput () {
    # Upload the data to PVOutput.org
    # See https://pvoutput.org/help.html#api-addstatus

    # Transform YYYY-MM-DD to YYYMMDD
    year=${today%%-*}
    month=${today#*-}; month=${month%-*}
    day=${today##*-}
    date="${year}${month}${day}"

    # POST data to PVOutput
    local postResp=$(curl -si --url "${pvoutputURL}" \
        -H "X-Pvoutput-Apikey: ${apiKey}" -H "X-Pvoutput-SystemId: ${sysId}" \
        -H "X-Rate-Limit: 1" -d "d=${date}" -d "t=${time}" \
        -d "v2=${outAmp}" -d "v5=${temperature}" -d "v6=${inVolt}")
    if [ $? -eq 0 ] ; then
        ratelimitRemain=${postResp#*X-Rate-Limit-Remaining: }
        ratelimitRemain=${ratelimitRemain%%,*}
        ratelimitPerHour=${postResp#*X-Rate-Limit-Limit: }
        ratelimitPerHour=${ratelimitPerHour%%,*}
        ratelimitReset=${postResp#*X-Rate-Limit-Reset: }
        ratelimitReset=${ratelimitReset%%,*}
        logOut "PVOutput Rate Limit Remaining: ${ratelimitRemain}"
    else
        logErr "PVOutput Error: ${postResp}"
        sleep 60
    fi
}

waitTillSunrise () {
    # No need to poll or push when the sun isn't shining
    now=$(date '+%s')
    sunrise=$(sscalc -a $latitude -o $longitude -f '%s')
    sunset=${sunrise#*  }
    sunrise=${sunrise%  *}
    if   [ $now -lt $sunrise ] ; then
        sleep $((sunrise-now))
    elif [ $now -gt $sunset ] ; then
        local tomorrow=$(date -v +1d '+%m-%d')
        sunrise=$(sscalc -d ${tomorrow#*-} -m ${tomorrow%-*} \
               -a $latitude -o $longitude -f '%s')
        sunset=${sunrise#*  }
        sunrise=${sunrise%  *}
        local waitSeconds=$((sunrise-now-margin))
        logOut "Waiting for sunrise (${waitSeconds})"
        [ -z "${ONESHOT}" ] && sleep ${waitSeconds}
    fi
    today=$(date '+%Y-%m-%d')
}

loadConfig "$*"

# Redirect output and error to file
exec 1<&-
exec 2<&-
exec 1>>${outputPath}/${logFile}.out
exec 2>>${outputPath}/${logFile}.err

waitTillSunrise # sets today, sunrise, sunset
nextStart=$(date '+%s') # Initialize

while : ; do # Infinite loop
    nextStart=$((nextStart+interval))
    if [ $lastStart -lt $((sunset+margin)) ] ; then
        time=$(date '+%H:%M')

        loadPVOutput && uploadPVOutput

        now=`date "+%s"`
        logOut "Sleep for $((nextStart-now)) seconds"
        [ "${ONESHOT}" ] && exit 0
        sleep $((nextStart-now))
    else
        [ "${dailyRestart}" ] && exit 0
        waitTillSunrise
    fi
done
