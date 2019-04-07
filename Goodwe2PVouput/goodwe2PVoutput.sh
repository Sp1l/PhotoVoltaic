#!/bin/sh

# goodwe2PVoutput v2.1.1
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
# for non-EU installations the host is goodwe-power.com
goodweUrl='https://eu.goodwe-power.com/PowerStationPlatform/PowerStationReport/InventerDetail'
# URL to post the target data to
pvoutputUrl='https://pvoutput.org/service/r2/addstatus.jsp'

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
 - username  (for goodwe-power.com login)
 - password  (for goodwe-power.com login)
 - apiKey    (your PVOutput apiKey)
 - sysId     (your PVOutput System ID)
 - latitude  (of your solar installation)
 - longitude (of your solar installation)
config-file can additionally contain these variables:
 - cookieFile (defaults to current directory goodwe.cookies)
      where Goodwe's session cookies will be stored
 - dailyRestart if set, script will exit after sunset
 - donation     to set rate-limit for PVoutput user
      add a daily cronjob to start it
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
	cookieFile=${cookieFile:-goodwe.cookies}
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

kilo2unit () {
	# 0.9 becomes 900, 20.80 becomes 20800
	local input=$1 ; local sep=$2 ; local digit=0
	local kilo=${input%${sep}*}
	local fraction=${input#*${sep}}
	local digits=${#fraction}
	for digit in 1 2 3 ; do
	[ ${digit} -gt ${digits} ] && fraction=${fraction}0
	done
	echo ${kilo}${fraction}
}

loginGoodwe () {
	echo Logging in with goodwe-power.com
	local curlOpts="-d username=${username} -d password=${password}"
	local httpResp=`curl -c ${cookieFile} -s -o/dev/null -w "%{http_code}" \
		-d "username=${username}" -d "password=${password}" \
		"http://goodwe-power.com/User/Login"`
		echo Login status ${httpResp}
	[ ${httpResp}0 -eq 3020 ] && echo Goodwe login successful
}

retrieveData () {
	local inverterDetail="http://goodwe-power.com/PowerStationPlatform/PowerStationReport/InventerDetail"
	# Pull data from goodwe-power.com and rip out values
	while : ; do
		payload=`curl -so - -c ${cookieFile} -m 10 \
		"${inverterDetail}?ID=${stationId}&InventerType=GridInventer&HaveAdverseCurrentData=0&HaveEnvironmentData=0"`
		[ $? -eq 0 ] && break
		echo "Problem fetching from Goodwe, retry in 60s"
		sleep 60
		loginGoodwe
	done
	sourceTable=`echo "$payload" | sed -e '/<tbody>/,/<\/tbody>/!d' \
		-e 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]*<\/t/<\/t/g' \
		-e 's/ scope="col"//g;s/<\/*span[^>]*>//g;s/ /_/g' | \
	tr -d '\n' | \
	sed -e 's/\(<\/t[dh]>\)/\1|/g' \
		-e 's/<\/*tr>//g;s/<\/*tbody>//;s/><\/t/>dummy<\/t/g' | \
	tr '|' '\n'`
# /<tbody>/,/<\/tbody>/!d : Delete everything but between the tbody
# s/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]*<t/<t/g # remove whitespace
# s/ scope="col"//g : Delete attribute
# s/<\/*span[^>]*>//g' : Delete <span> tags
# tr -d \\n : Remove newlines
# s/\(<\/t[dh]>\)/\1|/g : add a '|' after closing tag
# 's/<\/*tr>//g;s/<tbody>//' : Delete tr and tbody tags
# s/><\/t/>dummy<\/t/g : Fill empty td/tr with dummy value
# tr '|' '\n' : Replace pipe with newline
# Now we have separate lines with either th or td elements
}

extractData () {
	local headers="" ; local header=""
	local values=""  ; local value=""
	local status="unknown"
	# Extract column names <th> from source
	headers=`echo "${sourceTable}" | sed -n 's/<th>\(.*\)<\/th>/\1/p'`
	# Extract values <td> from source
	values=`echo "${sourceTable}"  | sed -n 's/<td>\(.*\)<\/td>/\1/p' | tr '\n' ' '`

	for header in ${headers} ; do
		value=${values%% *} # Store first value
		values=${values#* } # Remove first value
		case "${header}" in
			Status)  status=${value} ;;
			PGrid)   outPower=${value%W} ;;
			EDay)    todayProd=${value%kWh} ;;
			Vpv)     inVoltage=${value%V} ;;
			Ipv)     inCurrent=${value%A} ;;
			Vac)     outVoltage=${value%%/*} ;;
			Iac)     outCurrent=${value%%/*} ;;
			Fac)     outFrequency=${value%%/*} ;;
			Temper*) temperature=${value%℃*} ;;
		esac
	done

	# Prevent errors, bail out if inverter is offline
	[ "${status}" = "Offline" ] && return

	local inV1=0 ; local inV2=0 ; local inI1=0 ; local inI2=0
	[ "${inVoltage}" != "empty" ] && \
		inV1=${inVoltage%V/*} ; inV2=${inVoltage#*/} # Split values
	[ "${inCurrent}" != "empty" ] && \
		inI1=${inCurrent%A/*} ; inI2=${inCurrent#*/}
	inPower=`bc -e "scale=2;($inV1*$inI1)+($inV2*$inI2)" -e quit`
	[ "${outPower}" != "empty" -a ${inPower%.*} -gt 0 ] &&
		efficiency=`bc -e "scale=2;${outPower} / ${inPower}" -e quit`
	Vpv=`add $inV1 $inV2`
	Ipv=`add $inI1 $inI2`
	todayProd=`kilo2unit ${todayProd} .`
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

exitErr "This script no longer works"

loadConfig "$*"

# Redirect output and error to file
exec 1<&-
exec 2<&-
exec 1>>${outputPath}/goodwe2PVoutput.out
exec 2>>${outputPath}/goodwe2PVoutput.err

# Make sure we have a valid session with Goodwe
loginGoodwe

today=0
waitTillSunrise # sets today, sunrise, sunset
while : ; do # Infinite loop
	lastStart=`date '+%s'`

	if [ $lastStart -lt $((sunset+margin)) ] ; then
		timestamp=`date '+%Y-%m-%d %H:%M:%S'`
		time=${timestamp#* } ; time=${time%:*} # Extract HH:MM
		retrieveData
		extractData
		if [ "${status}" == "Offline" ] ; then
			echo "${timestamp} Inverter Offline"
			sleep $((lastStart-now+interval))
			continue
		fi
		echo "$timestamp, $todayProd, $inVoltage, $inCurrent, $inPower," \
			  "$outVoltage, $outCurrent, $outPower, $temperature" \
			  >> ${outputPath}/${today}.csv
		echo "$timestamp, $todayProd, $efficiency, $inVoltage, $inCurrent, $inPower," \
			  "$outVoltage, $outCurrent, $outPower, $temperature"
		postResp=`curl -si --url "${pvoutputUrl}" \
				-H "X-Pvoutput-Apikey: ${apiKey}" -H "X-Pvoutput-SystemId: ${sysId}" \
				-H "X-Rate-Limit: 1" -d "d=${today}" -d "t=${time}" \
				-d "v2=${outPower}" -d "v5=${temperature}" -d "v6=${Vpv}"`
				# -d "v1=${todayProd}" Not used by PVOutput, uses calculated value
		RC=$?
		if [ $RC = 0 ] ; then
			lastOKtoday=${today}${time%:*}${time#*:}
			limitLeft=`echo "${postResp}" | sed -n 's/^X-Rate-Limit-Remaining: \([0-9]*\)/\1/p'`
		    	now=`date "+%s"`
			echo "Rate Limit Remaining: ${limitLeft}; Sleep for $((lastStart-now+interval)) seconds"
		 	sleep $((lastStart-now+interval))
		else
			echo Error $postResp
			sleep 60
		fi
	else
		[ "${dailyRestart}" ] && exit 0
		waitTillSunrise
	fi
done
