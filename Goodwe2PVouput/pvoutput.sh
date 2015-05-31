#!/bin/sh

# User Specific Settings
interval=$((10*60)) #seconds
margin=$((20*60))
stationId='<your Goodwe-power.com stationID>'
apiKey='<your PVoutput.org API key>' 
sysId='<This systems PVoutput.org system number'
latitude=<latitude of your installation>
longitude=-<longitude of your installation>
outputPath='<Where to store the csv>'

# Global settings
goodweUrl='http://www.goodwe-power.com/Mobile/GetPacLineChart'
pvoutputUrl='http://pvoutput.org/service/r2/addstatus.jsp'

retrieveData () {
	local payload
	while : ; do
		payload=`curl -qo - "${goodweUrl}?stationId=${stationId}&date=${today2}"`
		[ $? -eq 0 ] && break
		sleep 60
	done
	echo $payload
}

today=0
# Infinite loop
while : ; do
	# Check if we have a new day
	nowYMD=`date '+%Y%m%d'` 
	if [ $nowYMD -gt $today ] ; then
		today=$nowYMD 
		today2=`date +'%Y-%m-%d'`
		lastOKtoday=0
		sunrise=`sscalc -a $latitude -o $longitude -f '%s'`
		sunset=${sunrise#*  }
		sunrise=${sunrise%  *}
		now=`date '+%s'`
		sleep $((sunrise-now-margin)) # sleep till sunrise
	fi
	# Sunrise! Let's start!
	lastStart=`date "+%s"`

	if [ $lastStart -gt $sunrise -a $lastStart -lt $((sunset+margin)) ] ; then
		goodweCSV=`retrieveData | sed -E 's/},{/|/g;s/\[{//;s/}\]//;s/"Hour(Num|Power)"://g;s/:0"/:00"/g;s/"//g' | tr '|' '\n' | grep -v ',0$'`
		echo ${goodweCSV} > ${outputPath}/${today2}.csv
		for line in $goodweCSV ; do
			time=${line%,*}
			power=${line#*,}
			[ ${today}${time%:*}${time#*:} -lt $lastOKtoday ] && continue
			postResp=`curl -s --url "${pvoutputUrl}" \
					-H "X-Pvoutput-Apikey: ${apiKey}" -H "X-Pvoutput-SystemId: ${sysId}" \
					-d "d=${today}" -d "v2=${power}" -d "t=${time}" `
			RC=$?
			if [ $RC = 0 ] ; then
				lastOKtoday=${today}${time%:*}${time#*:}
			else
				echo Error $postResp
			fi
		done
	fi
	now=`date "+%s"`
	sleep $((lastStart+interval-now))
done
