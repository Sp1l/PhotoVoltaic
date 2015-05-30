Goodwe portal to PVoutput.org logger
 * Web-scraping from http://goodwe-power.com
 * Uses the Realtime tab (InverterDetail) as that contains most detail
 
Peculiarities
 * The inverter updates goodwe-power.com every 8 minutes
 * The table that can be downloaded from /mobile only has values per 10 minutes and thus misses measurements
 * Update PVoutput every 4 minutes to capture all changes (and set update frequency to 5 minutes)
 
TODO
 * The inverter has a Web-UI -> find out how to access the read-outs from there
 * The USB port exposes a serial interface, find out how to use it
 * The web-server is Ralink httpd
 * Vulnerabilities seem to exist in this Ralink platform [https://forum.openwrt.org/viewtopic.php?id=42142]
 


