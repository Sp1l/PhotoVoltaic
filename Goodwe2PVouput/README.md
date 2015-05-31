# pvoutput.sh
Goodwe mobile to PVoutput.org logger
 * Web-scraping from the Mobile UI pages (json)
 * Uses Mobile/GetPacLineChart resource for data (10 min interval)

## History
 - v1.0 Not published
 - v1.1 Adds dusk/dawn margin

# goodwe2PVoutput.sh
Goodwe portal to PVoutput.org logger
 * Web-scraping from http://goodwe-power.com
 * Uses the Realtime tab (InverterDetail) as that contains most detail
 * Updates current output, voltage, inverter temperature

## History
 - v1.0 Initial published version
 - v1.1 Adds dusk/dawn margin
 
Peculiarities
 * The inverter updates goodwe-power.com every 8 minutes
 * The table that can be downloaded from /mobile only has values per 10 minutes and thus misses measurements
 * Update PVoutput every 4 minutes to capture all changes (and set update frequency to 5 minutes)
 
# TODO
 * The inverter has a Web-UI -> find out how to access the read-outs from there
 * The USB port exposes a serial interface, find out how to use it
 * The web-server is Ralink httpd
 * Vulnerabilities seem to exist in this Ralink platform [https://forum.openwrt.org/viewtopic.php?id=42142]
 
