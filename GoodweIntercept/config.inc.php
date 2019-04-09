<?php

if (!defined('SAFE_ENTRY')) {
    http_response_code(403);
    die('Go away!');
}

$config = array(

// Global parameters
//
// Where the logfiles will be written
'outputPath' => '/var/log/goodwe',

// The logging level (emergency, alert, critical, error, warning, notice, info, debug)
'logLevel' => 'debug',

// DNS servers to query for www.goodwe-power.com
'DNSServers' => array('1.0.0.1', '1.1.1.1', '8.8.4.4', '8.8.8.8', '9.9.9.9', '149.112.112.112'),

// Parameters for Goodwe connection and device
'Goodwe' => array(
//
// The ID of the inverter
// In top-left of www.semsportal.com page for the inverter
// Looks like: 13600DSU12300045
'inverterSN' => '',

// URL where to post data to
'URL' => 'http://47.254.132.36/Acceptor/Datalog',
), // Goodwe array

// Parameters for PVOutput connection and device
'PVOutput' => array(
//
// https://pvoutput.org/account.jsp API key field
'apiKey' => '',

// https://pvoutput.org/account.jsp System Id field
'sysId' => '',

// URL for posting status
'URL' => 'https://pvoutput.org/service/r2/addstatus.jsp',
), // PVOutput array

); // config array
