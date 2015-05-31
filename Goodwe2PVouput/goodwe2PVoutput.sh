#!/bin/sh

# goodwe2PVoutput v1.0
# Goodwe portal to PVoutput.org logger
# Web-scraping from http://goodwe-power.com
# Uses the Realtime tab (InverterDetail) as that contains most detail
# Source at https://github.com/Sp1l/
# Created by Bernard Spil (spil.oss@gmail.com)

# Requirements:
#  * Any shell (only uses basic shell functions)
#  * cURL (http://curl.haxx.se/) for down-/uploading
#  * bc (arbitrary precision calculator)
#  * sscalc (http://www.icehouse.net/kew/) for sunrise/-set

# The Goodwe inverter updates the InverterDetail page every 8 minutes
# We report every 4 minutes so set PVoutput to 5 minute interval so
# you capture all available measurements

# User Specific Settings
stationId='<your Goodwe-power.com stationID>'
apiKey='<your PVoutput.org API key>' 
sysId='<This systems PVoutput.org system number'
latitude=<latitude of your installation>
longitude=-<longitude of your installation>
outputPath='<Where to store the csv>'

# Global settings
interval=$((4*60)) #seconds
margin=$((20*60))
goodweUrl='http://goodwe-power.com/PowerStationPlatform/PowerStationReport/InventerDetail'
pvoutputUrl='http://pvoutput.org/service/r2/addstatus.jsp'

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
		payload=`curl -qo - -m 10 "${goodweUrl}?ID=${stationId}"`
		[ $? -eq 0 ] && break
		sleep 60
	done
	source=`echo "$payload" | sed -ne '/<tr class="DG_Item">/,/<\/tr>/!d;/<td><\/td>/d;s/ //g;s/<\/*td>//gp'`
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
			13) temperature=${line%â„ƒ*} ;;
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
	if [ $now -lt $sunrise ] && sleep $((sunrise-now))
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
			sleep $((lastStart-now+interval))
		else
			echo Error $postResp
			sleep 60
		fi
	else
		waitTillSunrise
	fi
done
