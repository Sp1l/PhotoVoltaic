# Goodwe2PVoutput

Early 2019, Goodwe killed the original scripts using goodwe-portal.com.

I've switched to the "Intercept" mode as documented in [GoodweIntercept](../GoodweIntercept/README.md)

## SEMS2PVoutput.sh

Goodwe API to PVoutput.org logger

* **Replaces** goodwe2PVoutput.sh
* API-scraping from http://eu.semsportal.com
* Updates current output, voltage, inverter temperature
* Reads settings from config.sh
* No more peculiarities, update pvoutput.org every 5 minutes

### History

 - v3.0 Initial published rewritten version

## goodwe2PVoutput.sh

**NO LONGER WORKS**

Goodwe portal to PVoutput.org logger
 * Web-scraping from http://goodwe-power.com
 * Uses the Realtime tab (InverterDetail) as that contains most detail
 * Updates current output, voltage, inverter temperature
 * Reads settings from config.sh

### History

* v1.0 Initial published version
* v1.1 Adds dusk/dawn margin
* v1.2 Move config to config.sh for -hist version

### Peculiarities

* The inverter updates goodwe-power.com every 8 minutes
* The table that can be downloaded from /mobile only has values per 10 minutes and thus misses measurements
* Update PVoutput every 4 minutes to capture all changes (and set update frequency to 5 minutes)

## goodwe2PVoutput-hist.sh

**NO LONGER WORKS**

Goodwe portal "History" to PVoutput.org logger

* Accepts date in the past
  * 90 days if you've donated
  * 14 days if you have not donated
* Web scraping from http://goodwe-power.com
* Updates current output, voltage, inverter temperature
* Reads settings from config.sh

### History

* v1.0 2016-03-13 Initial published version

## pvoutput.sh

**NO LONGER WORKS**

Simpler Goodwe mobile to PVoutput.org logger

* Web-scraping from the Mobile UI pages (json)
* Uses Mobile/GetPacLineChart resource for data (10 min interval)
* Only Power output added

### History
 - v1.0 Not published
 - v1.1 Adds dusk/dawn margin
 
## TODO

* The inverter has a Web-UI -> find out how to access the read-outs from there
* The USB port exposes a serial interface, find out how to use it
* The web-server is Ralink httpd
* Vulnerabilities seem to exist in this Ralink platform [https://forum.openwrt.org/viewtopic.php?id=42142]
