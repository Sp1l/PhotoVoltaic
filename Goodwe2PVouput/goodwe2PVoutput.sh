#!/bin/sh

# goodwe2PVoutput v1.2
# Goodwe portal to PVoutput.org logger
# Web-scraping from http://goodwe-power.com
# Uses the Realtime tab (InverterDetail) as that contains most detail
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
interval=$((4*60)) #seconds
# dusk/dawn margin
margin=$((15*60)) # seconds
# URL to retrieve the source data from
goodweUrl='http://goodwe-power.com/PowerStationPlatform/PowerStationReport/InventerDetail'
# URL to post the target data to
pvoutputUrl='http://pvoutput.org/service/r2/addstatus.jsp'

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
  - outputPath (defaults to current directory)
      where yyyymmdd.csv files will be created
ENDOFUSAGE
}

exitErr () {
echo -e "\033[1;31mERROR: \033[0m\033[1m$*\033[0m"
usage
exit 1
}

loadConfig () {
	confFile="${1:-config.sh}"
	if   [ -f "${confFile}" ] ; then : 
	elif [ -f "${scriptDir}/${confFile}" ] ; then confFile="${scriptDir}/${confFile}"
	else exitErr "Config file ${confFile} not found"
	fi
	. "${confFile}"
	[ ${stationId:-unset} == "unset" ] && exitErr "stationId unset or empty"
	[ ${apiKey:-unset} == "unset" ] && exitErr "apiKey unset or empty"
	[ ${sysId:-unset} == "unset" ] && exitErr "sysId unset or empty"
	[ ${latitude:-unset} == "unset" ] && exitErr "latitude unset or empty"
	[ ${longitude:-unset} == "unset" ] && exitErr "longitude unset or empty"
	outputPath=${outputPath:-.}
}

add () {
	# Add two values with a single digit accuracy
	local one=`echo $1 | tr -d .`
	local two=`echo $2 | tr -d .`
	local out=$((one+two))
	one=${out%[0-9]} ; two=$((out-one*10))
	echo $one.$two
}

splitAdd () {
	# Split 123.4/321.0 and add values
	local input=$1
	local sep=$2
	add ${input%${sep}*} ${input#*${sep}}
}

retrieveData () {
	# Pull data from goodwe-power.com and rip out values
	while : ; do
		payload=`curl -so - -m 10 "${goodweUrl}?ID=${stationId}"`
		[ $? -eq 0 ] && break
		echo "Problem fetching from Goodwe, retry in 60s"
		sleep 60
	done
	source=`echo "$payload" | sed -ne '/<tbody>/,/<\/tbody>/!d;/<td><\/td>/d;s/ //g;s/<\/*td>//gp'`
}

extractData () {
	# Process the values into corresponding variables
	local cnt=0
	for line in $source ; do
		cnt=$((cnt+1))
		case $cnt in
			4)  outPower=${line%W*} ;;
			5)  todayProd=${line%kWh*} ;;
			8)  inVoltage=${line%V*} ;;
			9)  inCurrent=${line%A*} ;;
			10) outVoltage=${line%%/*} ;;
			11) outCurrent=${line%%/*} ;;
			12) outFrequency=${line%%/*} ;;
			13) temperature=${line%℃*} ;;
		esac
	done
	local v1=${inVoltage%/*} ; local v2=${inVoltage#*/} # Split values
	local a1=${inCurrent%/*} ; local a2=${inCurrent#*/}
	inPower=`bc -e "scale=2;($v1*$a1)+($v2*$a2)" -e quit`
	efficiency=`bc -e "scale=2;$outPower / $inPower" -e quit` 
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
		sleep $((sunrise-now-margin))	
	fi
	today=`date '+%Y%m%d'`
}

loadConfig "$*"
today=0
waitTillSunrise # sets today, sunrise, sunset
while : ; do # Infinite loop
	lastStart=`date '+%s'`

	if [ $lastStart -lt $((sunset+margin)) ] ; then
		timestamp=`date '+%Y-%m-%d %H:%M:%S'`
		time=${timestamp#* } ; time=${time%:*} # Extract HH:MM
		retrieveData
		extractData
		echo $timestamp, $todayProd, $inVoltage, $inCurrent, $inPower, \
			  $outVoltage, $outCurrent, $outPower, $temperature \
			  >> ${outputPath}/${today}.csv
		echo $timestamp, $todayProd, $efficiency, $inVoltage, $inCurrent, $inPower, \
			  $outVoltage, $outCurrent, $outPower, $temperature
		v6=`splitAdd $inVoltage /`
		postResp=`curl -s --url "${pvoutputUrl}" \
				-H "X-Pvoutput-Apikey: ${apiKey}" -H "X-Pvoutput-SystemId: ${sysId}" \
				-d "d=${today}" -d "t=${time}" -d "v2=${outPower}" \
				-d "v5=${temperature}" -d "v6=${v6}"`
		RC=$?
		if [ $RC = 0 ] ; then
			lastOKtoday=${today}${time%:*}${time#*:}
		    	now=`date "+%s"`
			echo "Sleep for $((lastStart-now+interval)) seconds"
		    	sleep $((lastStart-now+interval))
		else
			echo Error $postResp
			sleep 60
		fi
	else
		waitTillSunrise
	fi
done
