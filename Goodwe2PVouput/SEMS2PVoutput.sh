#!/bin/sh

# goodwe2PVoutput v3.0
# Goodwe API to PVoutput.org logger
# Scraping from http://eu.semsportal.com
# Source at https://github.com/Sp1l/PhotoVoltaic
# Created by Bernard Spil (spil.oss@gmail.com)

# Requirements:
#  * Any shell (only uses basic shell functions)
#  * cURL (http://curl.haxx.se/) for down-/uploading
#  * bc (arbitrary precision calculator)
#  * sscalc (http://www.icehouse.net/kew/) for sunrise/-set

# The Goodwe inverter updates the InverterDetail page every 8 minutes
# We report every 4 minutes so set PVoutput to 5 minute interval so
# you capture all available measurements.
# Power is also generate at dawn and dusk when the sun isn't even
# above the horizon yet.
# Add your User Specific Settings in config.sh

# Global settings
# Refresh values using this interval
interval=$((5*60)) #seconds
# dusk/dawn margin
margin=$((15*60)) # seconds
# URL to retrieve the source data from
goodweLoginURL='https://eu.semsportal.com/api/v1/Common/CrossLogin'
goodweDataURL='https://eu.semsportal.com/api/v1/PowerStation/GetMonitorDetailByPowerstationId'
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
   [ ${stationId:-unset} == "unset" ] && exitErr "stationId unset or empty"
   [ ${apiKey:-unset} == "unset" ] && exitErr "apiKey unset or empty"
   [ ${sysId:-unset} == "unset" ] && exitErr "sysId unset or empty"
   [ ${latitude:-unset} == "unset" ] && exitErr "latitude unset or empty"
   [ ${longitude:-unset} == "unset" ] && exitErr "longitude unset or empty"
}

add () {
   # Add two values with a single digit accuracy
   local left right one two out
   left=${1%.*} ; right=${1#*.}
   one=${left}${right}
   [ ${left} -eq 0 ] && one=${right}
   left=${2%.*} ; right=${2#*.}
   two=${left}${right}
   [ ${left} -eq 0 ] && two=${right}
   out=$((one+two))
   if [ $out -lt 10 ] ; then
      echo "0.${out}"
   else
      left=${out%[0-9]} ; right=$((out-left*10))
      echo "${left}.${right}"
   fi
}

loginGoodwe () {
   # See http://globalapi.sems.com.cn:82/swagger/ui/index#!/CommonController/CommonController_CrossLogin_0
   # for a description and test UI
   local payload
   payload=`curl -s ${goodweLoginURL} \
      --header 'Content-Type: application/json' \
      --header 'Accept: application/json' \
      --header 'token: {"uid": "","timestamp": 0,"token": "","client": "web","version": "","language": "en" }' \
      --data-binary '{
            "account": "'${username}'",
            "pwd": "'${password}'",
            "is_local": true,
            "agreement_agreement": 0
         }' | tr -d '\r\n '`
   # The new-lines in the POST body are REQUIRED (WTFBBQ!!!)

   # Extract data JSON element from long string
   token="${payload#*\"data\":}"
   token="${token%%\},*}}"
}

retrieveData () {
   # Pull data from semsportal.com and pre-process
   # See http://globalapi.sems.com.cn:82/swagger/ui/index#!/PowerStationController/PowerStationController_GetMonitorDetailByPowerstationId_0
   local payload
   while : ; do
      payload=`curl -s -m 10 ${goodweDataURL} \
      --header 'Content-Type: application/json' \
      --header 'Accept: application/json' \
      --header 'token: '"${token}" \
      --data-binary '{"powerStationId": "'"${stationId}"'"}' | tr -d '\r'`
      if [ $? -gt 0 ] ; then
         logOut "Problem fetching from Goodwe, retry in 60s"
         sleep 60
      elif [ "${payload}" != "${payload#*authorization has expired}" ] ; then
         # Refresh token
         logOut "Goodwe token expired, get a new one and retry"
         loginGoodwe
      else
         # Success! break out of loop
         break;
      fi
   done
   # We're only intereseted in the "invert_full" object in the output
   payload="${payload#*\"invert_full\": \{}"
   inverterDetail="${payload%%\},*}"
}

extractData () {
   # Extend this list when you want to extract more values (different model inverter)
   # Use shell built-ins wherever possible (fast!)
   local key value
   for key in pac vpv1 vpv2 ipv1 ipv2 vac1 iac1 fac1 tempperature eday \
            status turnon_time last_time; do
      value=${inverterDetail#*\"${key}\": }
      value=${value%%,*}
      eval local $key=$value
   done
   [ "${status}" != '1' ] && return
   todayProd=${eday}
   inVoltage=`add ${vpv1} ${vpv2}`
   inCurrent=`add ${ipv1} ${ipv2}`
   inPower=`bc -e "scale=2;($vpv1*$ipv1)+($vpv2*$ipv2)" -e quit`
   outVoltage=${vac1}
   outCurrent=${iac1}
   outPower=${pac}
   temperature=${tempperature}
}

uploadPVOutput () {
   # Upload the data to PVOutput.org
   # See https://pvoutput.org/help.html#api-addstatus
   local postResp=`curl -si --url "${pvoutputURL}" \
      -H "X-Pvoutput-Apikey: ${apiKey}" -H "X-Pvoutput-SystemId: ${sysId}" \
      -H "X-Rate-Limit: 1" -d "d=${today}" -d "t=${time}" \
      -d "v2=${outPower}" -d "v5=${temperature}" -d "v6=${inVoltage}" | tr '\r' ','`
   if [ $? -eq 0 ] ; then
      ratelimitRemain=${postResp#*X-Rate-Limit-Remaining: }
      ratelimitRemain=${ratelimitRemain%%,*}
      ratelimitPerHour=${postResp#*X-Rate-Limit-Limit: }
      ratelimitPerHour=${ratelimitPerHour%%,*}
      ratelimitReset=${postResp#*X-Rate-Limit-Reset: }
      ratelimitReset=${ratelimitReset%%,*}
      logOut "PVOutput Rate Limit Remaining: ${ratelimitRemain}"
   else
      logErr "PVOutput Error: $postResp"
      sleep 60
   fi
}

waitTillSunrise () {
   # No need to poll or push when the sun isn't shining
   now=`date '+%s'`
   sunrise=`sscalc -a $latitude -o $longitude -f '%s'`
   sunset=${sunrise#*  }
   sunrise=${sunrise%  *}
   [ $now -lt $sunrise ] && sleep $((sunrise-now))
   if [ $now -gt $sunset ] ; then
      local tomorrow=`date -v +1d '+%m-%d'` 
      sunrise=`sscalc -d ${tomorrow#*-} -m ${tomorrow%-*} \
             -a $latitude -o $longitude -f '%s'`
      sunset=${sunrise#*  }
      sunrise=${sunrise%  *}
      local waitSeconds=$((sunrise-now-margin))
      logOut "Waiting for sunrise (${waitSeconds})"
      [ -z "${ONESHOT}" ] && sleep ${waitSeconds}
   fi
   today=`date '+%Y%m%d'`
}

loadConfig "$*"

# Redirect output and error to file
exec 1<&-
exec 2<&-
exec 1>>${outputPath}/${logFile}.out
exec 2>>${outputPath}/${logFile}.err

loginGoodwe # sets token initially

today=0
waitTillSunrise # sets today, sunrise, sunset

while : ; do # Infinite loop
   lastStart=`date '+%s'`
   if [ $lastStart -lt $((sunset+margin)) ] ; then
      timestamp=`date '+%F %T'` # ISO-8601 yyyy-mm-dd hh:mm:ss
      time=${timestamp#* } ; time=${time%:*} # Extract HH:MM
      retrieveData
      extractData
      echo $timestamp, $todayProd, $inVoltage, $inCurrent, $inPower, \
           $outVoltage, $outCurrent, $outPower, $temperature \
           >> ${outputPath}/${today}.csv
      logOut $timestamp, $todayProd, $inVoltage, $inCurrent, $inPower, \
             $outVoltage, $outCurrent, $outPower, $temperature
      uploadPVOutput
      now=`date "+%s"`
      logOut "Sleep for $((lastStart-now+interval)) seconds"
      [ "${ONESHOT}" ] && exit 0
      sleep $((lastStart-now+interval))
   else
      [ "${dailyRestart}" ] && exit 0
      waitTillSunrise
   fi
done
