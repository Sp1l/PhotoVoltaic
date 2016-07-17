#!/bin/sh
# Original: Kire Pudsje, march 2016
# Modified: Bernard Spil, 13 March 2016

usage () {
cat << END_OF_USAGE
Usage: $0 <start-date>
       $0 <start-date> <end-date>
Date format: YYYY-MM-DD
END_OF_USAGE
}

add () {
	# Add two values with a _single_ digit accuracy
	local one=${1%.*}${1#*.} # remove decimal sep
	local two=${2%.*}${2#*.} # without forks
	local out=$((one+two))   # use shell integer math
	one=${out%[0-9]} ; two=$((out-one*10))
	echo $one.$two
}

processDate () {
# The actual workhorse of the script

queryDate="$1"

# Timeseries received from Goodwe 
# PGrid(W) Vpv1(V) Vpv2(V) Ipv1(A) Ipv2(A) 
# Vac1(V) Vac2(V) Vac3(V) Iac1(A) Iac2(A) Iac3(A) Fac1(Hz) Fac2(Hz) Fac3(Hz) 
# Temperature(?) ETotal(kWh) HTotal(h) EDay(kWh) Vbattery1(V) Ibattery1(A) SOC1(%)
# PVTotal(kWh) LoadPower(W) E_Load_Day(kWh) E_Total_Load(kWh) InverterPower(W) Vload(V) Iload(A)

# 1. Retrieve data from Goodwe
# 2. Strip out unneeded output
# 3. One line per timeseries
timeSeries=`curl -s -d "InventerSN=${inverterSN}&QueryType=0&DateFrom=${queryDate}&PowerStationID=${stationId}" \
	http://www.goodwe-power.com/PowerStationPlatform/PowerStationReport/QueryTypeChanged \
	| sed 's/quot;//g;s/{"YAxis":"{name://;s/{name:/|/g;s/}[,]*//g;s/","XAxis":".*//' \
	| tr '|' '\n'`
# Returns a set of lines like
# PGrid(W),data:[0,0,0,0,63,93,111,176,205,...]
# Temperature(?),data:[0,0,0,0,9.6,10.1,10.9,11.9,...]
# Each data-point is an increment of 10 minutes starting with 00:00
# (24*6) 144 data-points per day 

# Extract relevant timeseries from the list of timeseries
# and remove prefix and suffix
PGrid=`echo -e "$timeSeries" | sed -n 's/^PGrid(W),data:\[\(.*\)]$/\1/p' | tr ',' ' '`
Vpv1=`echo  -e "$timeSeries" | sed -n 's/^Vpv1(V),data:\[\(.*\)]$/\1/p'`
Vpv2=`echo  -e "$timeSeries" | sed -n 's/^Vpv2(V),data:\[\(.*\)]$/\1/p'`
Temperature=`echo -e "$timeSeries" | sed -n 's/^Temperature(.),data:\[\(.*\)]$/\1/p'`
# Each timeseries is a list of values separated by a ',' (comma)
# Except for PGrid which is separated by ' ' for splitting with `for`

outputDate=`date -j -f '%Y-%m-%d' ${queryDate} '+%Y%m%d'`

local hour=00
local minute=00
local n=0
for outPower in ${PGrid} ; do
	# Get first value in timeseries and remove first value
	local v1=${Vpv1%%,*} ; Vpv1=${Vpv1#*,}
	local v2=${Vpv2%%,*} ; Vpv2=${Vpv2#*,}
	local temperature=${Temperature%%,*} ; Temperature=${Temperature#*,}
	inVoltage=`add $v1 $v2`
	if [ ${outPower} -ne 0 ] ; then
		data="${data}${outputDate},${hour}:${minute},-1,${outPower},-1,-1,${temperature},${inVoltage};"
		# Insert space for posting max 30 per call
		[ $((n+=1)) -ge ${batchSize} ] && { n=0 ; data="${data} " ; }
	fi

	# Increase minute (and hour)
	minute=$((minute+10))
	if [ ${minute} -eq 60 ] ; then
		hour=${hour#0} ; hour=$((hour+1))
		[ ${hour} -le 9 ] && hour=0${hour}
		minute=00
	fi
done

for postData in $data ; do
	response=`curl -s -i -o- -d "data=$postData" \
					-H "X-Pvoutput-Apikey: ${apiKey}" -H "X-Pvoutput-SystemId: ${sysId}" -H "X-Rate-Limit: 1" \
					http://pvoutput.org/service/r2/addbatchstatus.jsp | tr -d '\r'`
	respStatus=`echo "${response}" | sed -n 's/^HTTP[^ ]* \([0-9]*\) .*/\1/p' | tail -n 1`
	[ ${respStatus} -ge 300 ] && { echo -e "Error when sending data to PVOutput:\n${response}" ; exit 1 ; }
	limitLeft=`echo "${response}" | sed -n 's/^X-Rate-Limit-Remaining: \([0-9]*\)/\1/p'`
	if [ ${limitLeft} -lt ${backoff} ] ; then
		limitReset=`echo "${response}" | sed -n 's/^X-Rate-Limit-Reset: \([0-9]*\)/\1/p'`
		waitSec=$((limitReset-`date '+%s'`+5))
		echo "Rate limit almost reached, waiting ${waitSec} seconds"
		sleep ${waitSec}
	fi
done

} # processDate 

TMPFILE=`mktemp -t $(basename $0).XXXXXX`

. ./config.sh

case ${donation} in
	[Yy][Ee][Ss] )
			rateLimit=300
			backoff=50
			batchSize=30
		;;
	* )
			rateLimit=60
			backoff=20
			batchSize=30
		;;
esac

case $# in
  1 ) date -j -f '%Y-%m-%d' "$1" 1>/dev/null 2>&1 || { echo "Error: Date \"$1\" invalid, format YYYY-MM-DD"; exit 1; }
		processDate $1
    ;;
  2 ) date -j -f '%Y-%m-%d' "$1" 1>/dev/null 2>&1 || { echo "Error: Date \"$1\" invalid, format YYYY-MM-DD"; exit 1; }
		date -j -f '%Y-%m-%d' "$2" 1>/dev/null 2>&1 || { echo "Error: Date \"$2\" invalid, format YYYY-MM-DD"; exit 1; }
		startEpoch=`date -j -f '%Y-%m-%d' "$1" '+%s'`
		endEpoch=`date -j -f '%Y-%m-%d' "$2" '+%s'`
		[ ${startEpoch} -gt ${endEpoch} ] && { echo "Error: Start date later than end date" ; usage ; exit 1 ; }
		processEpoch=${startEpoch}
		while [ ${processEpoch} -le ${endEpoch} ] ; do
			processDate=`date -j -f '%s' ${processEpoch} '+%Y-%m-%d'`
			echo "processing ${processDate}..."
			processDate $processDate
			processEpoch=`date -j -v+1d -f '%s' ${processEpoch} '+%s'`
		done
    ;;
  * ) usage ;;
esac
