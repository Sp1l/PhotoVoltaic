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

// Parameters for Goodwe connection and device
'Goodwe' => array(
    // Will post to Goodwe if true
    'enabled' => true,

    // The ID of the inverter
    // In top-left of www.semsportal.com page for the inverter
    // Looks like: 13600DSU12300045
    'inverterSN' => '',

    // URL where to post data to
    'URL' => 'http://47.254.132.36/Acceptor/Datalog',
), // Goodwe array

// Parameters for PVOutput connection and device
'PVOutput' => array(
    // Will post to PVOutput if true
    // Note that PVOutput requires data very 5 minutes and
    // your inverter has a different update frequency
    'enabled' => true,

    // https://pvoutput.org/account.jsp API key field
    'apiKey' => '',

    // https://pvoutput.org/account.jsp System Id field
    'sysId' => '',

    // URL for posting status
    'URL' => 'https://pvoutput.org/service/r2/addstatus.jsp',
), // PVOutput array

); // config array
