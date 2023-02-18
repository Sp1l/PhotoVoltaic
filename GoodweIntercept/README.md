# GoodweIntercept

PHP service that decodes the calls issued by the Goodwe Inverter

* Work in progress
* Has captured the outputs successfully for my Goodwe DS-3600

## goodwe.php

PHP script to intercept the calls from the inverter to goodwe-portal.com

Find a complete description of the reversing of the Goodwe inverter calling Goodwe's data-logging service [on my personal blog](https://brnrd.eu/misc/2019-03-23/killing-the-internet-of-shit.html).

* Has some basic stuff setup to forward to original Goodwe data-logging service.
* Has some stuff to post the data to a PVOutput.org account

Both forwarding and posting to PVOutput can be enabled/disabled in config.

## config.inc.php

Configuration parameters for the logging and PVOutput account are stored in this file.

Descriptions of the parameters are embedded in the file.

## HOW-TO

You must have control of your DNS or be able to route the IP-address of www.goodwe-portal.com to your webserver.

### DNS method

I use unbound and it was trivial to get it to respond with an IP-address of my choosing (see earlier linked blog-post).

    local-data: "www.goodwe-power.com. IN A 192.0.2.8"

and reload the configuration, test if this does what it says on the tin.

    :::shell
    service unbound reload
    host www.goodwe-power.com
    www.goodwe-power.com has address 192.0.2.8

Any traffic from the inverter should now go to my web-server.

### Updating PVOutput

There are 2 ways to feed the data to PVOutput, configurable via `config.inc.php`:

1. PREFERRED: Run a [separate script](PVoutput.sh) to upload the data.
2. Let the PHP script upload the data.

Note that PVOutput expects data every 5, 10 or 15 minutes. My model inverter updates ca. every 8 minutes. Updating with the PHP script will create gaps in measurement. The `PVoutput.sh` script will upload data every 5 minutes.

## `PVoutput.sh` shell script

The script expects to run continuously, or be started every day before sunrise. You configure this using `dailyRestart` in `config.sh`. See the annotated version in [Goodwe2PVoutput](../Goodwe2PVoutput/config.sh) as well as the documentation there.
