<?php

define('SAFE_ENTRY', true);
define('VERSION'   , '2019-03-31_1');

/** Define ABSPATH as this file's directory */
if ( ! defined( 'ABSPATH' ) ) {
    define('ABSPATH', dirname( __FILE__ ) . '/' );
}

define( "LOGLEVEL", array('emergency' => 0, 'alert' => 1, 'critical' => 2, 
    'error' => 3, 'warning' => 4, 'notice' => 5, 'info' => 6,'debug' => 7));

// Load configuration
require_once( ABSPATH . "config.inc.php");

// DNS functions
include_once('dns.inc.php');

function logthis ($severity, $message) {
// Log errors to file
    global $today, $now, $config;
    if ( is_null(LOGLEVEL[strtolower($severity)]) || 
         LOGLEVEL[strtolower($severity)] > LOGLEVEL[strtolower($config['logLevel'])] ) { 
        return; // Don't log, loglevel is lower than severity
    }
    try {
        file_put_contents($config['outputPath'].'/error.log', $today.' '.$now.' '
            .strtoupper($severity).': '.$message.PHP_EOL, FILE_APPEND);
    } catch (Exception $e) {
        http_response_code(500);
        print 'Cannot create file '.$config['outputPath'].'/error.log';
        return;
    }
}

function logPayload ($datapath, $payload) {
// base64 encoded binary blob to a raw.bin
    global $today, $now;
    try {
        file_put_contents( $datapath.'/raw.bin', $today.' '.$now.'|'.base64_encode($payload).PHP_EOL, FILE_APPEND);
    } catch (Exception $e) {
        http_response_code(500);
        die('Cannot create file '.$datapath.'/raw.bin');
    }
    logthis('Debug', 'Request-Body: '.base64_encode($payload));
}

function logData ($datapath, $Datalog) {
// Write data to daily csv file
    global $today, $now;
    $csvFile = $datapath.'/'.$today.'.csv';
    if ( !is_file($csvFile) ) {
        try {
            file_put_contents($csvFile,'# Date Time, TodaykWh, inVolt, inAmp, inWatt, outVolt, outAmp, outWatt, Temp'.PHP_EOL);
        } catch (Exception $e) {
            http_response_code(500);
            die('Cannot create file '.$csvFile);
        }
    }
    $csvFormat = '%s %s, %01.1f, %01.1f, %01.1f, %01.1f, %01.1f, %01.1f, %s, %01.1f';
    $csvString = sprintf($csvFormat, $today, $now, $Datalog['todaykWh'], 
        $Datalog['Vpv'], $Datalog['Ipv'], $Datalog['Ppv'], $Datalog['Vac'], 
        $Datalog['Iac'], $Datalog['Pac'], $Datalog['Temp']).PHP_EOL;
    file_put_contents($csvFile, $csvString, FILE_APPEND);
    logthis('Debug','Values: '.$csvString);
}

function QueryA ($hostname) {
    global $DNSServers;
    shuffle($DNSServers); // randomize what DNS host we query
    foreach ( $DNSServers as $DNShost ) {
        $DNSQuery = new DNSQuery($DNShost, 53, 1);
        $result = $DNSQuery->Query($hostname, 'A');
        if ( ($result===false) || ($DNSQuery->error!=0) ) { continue; }
        $result_count=$result->count; // number of results returned
        for ($a=0; $a<$result->count; $a++) { $records[] = $result->results[$a]->data; }
        shuffle($records); // randomize the IP-address we return
        return($records[0]);
    }
}

function postGoodwe ($config, $payload) {
// Post data to Goodwe 
    // Content-Length is prefixed with a 0
    $contentLength = sprintf("%03d",strlen($payload));
    // Headers can be unset by providing empty headers
    // No spaces between : and value in the original output
    // Host header is set as last header, cURL doesn't actually do that!
    $headers = array('Content-Type: ','Accept: ', 
        'Connection:Close',
        'Content-Length:'.$contentLength,
        'Host:www.goodwe-power.com');

    $ch = curl_init();

    logthis('Debug', 'Goodwe Headers: '.json_encode($headers));
    curl_setopt($ch, CURLOPT_URL,$config['URL']);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);

    $req_output = curl_exec($ch);
    $req_info = curl_getinfo($ch);

    curl_close ($ch);
    logthis('Debug', 'Goodwe Response: '.base64_encode($req_output));
    logthis('Debug', 'Goodwe cURL info: '.json_encode($req_info));
    return $req_output;
    file_put_contents('/var/log/goodwe/goodwe.out', $req_info['http_code'].'|'.$req_output.PHP_EOL, FILE_APPEND);
}

function postPVOutput ($config, $Datalog) {
// Post data to PVOutput
    global $today, $now;
    $ch = curl_init();

    $headers = array('X-Pvoutput-Apikey: '.$config['apiKey'], 
        'X-Pvoutput-SystemId: '.$config['sysId'],
        'X-Rate-Limit: 1'); 
    $today = str_replace('-','',$today); // yyyy-mm-dd to yyyymmdd
    $now = substr($now,0,5); // hh:mm:ss to hh:mm
    $postBody = "d=${today}&t=${now}&v2=${Datalog['Pac']}&v5=${Datalog['Temp']}&v6=${Datalog['Vpv']}";
    logthis('Debug', 'PVOutput Headers: '.json_encode($headers));
    logthis('Debug', 'PVOutput Body: '.$postBody);

    curl_setopt($ch, CURLOPT_URL,$config['URL']);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $postBody);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    
    $req_output = curl_exec($ch);
    $req_info = curl_getinfo($ch);

    curl_close ($ch);
    logthis('Debug', 'PVOutput Response: '.$req_output);
    logthis('Debug', 'PVOutput cURL info: '.json_encode($req_info));
    if ($req_info['http_code'] > 299) {
        logthis('Error','PVOutput: '.$req_info['http_code'].'|'.$req_output);
    }
    file_put_contents('/var/log/goodwe/goodwe.out', $req_info['http_code'].'|'.$req_output.'|'.$postBody.PHP_EOL, FILE_APPEND);
//   return $req_output;
}

function process66 ($payload, &$Datalog) {
// Get relevant strings/values from binary payload
    // See https://brnrd.eu/misc/2019-03-23/killing-the-internet-of-shit.html
    try {
        $values = unpack("A16inverterID/A3Mode/nVpv1/nVpv2/nIpv1/nIpv2/nVac/nIac/nFac/nPac/nDummy1/nTemp/lDummy2/ltotalkWh/ltotalHours/A10Dummy3/ntodaykWh",$payload,1);
    } catch (Exception $e) {
        http_response_code(500);
        die('Not a valid Goodwe payload');
    }

    // Convert (natural) numbers to correct (real) value
    $Datalog['inverterID'] = $values["inverterID"];
    $Datalog['Vpv'] = ($values["Vpv1"] + $values["Vpv2"]) * 0.1;
    $Datalog['Ipv'] = ($values["Ipv1"] + $values["Ipv2"]) * 0.1;
    $Datalog['Vac'] = $values["Vac"] * 0.1;
    $Datalog['Iac'] = $values["Iac"] * 0.1;
    $Datalog['Fac'] = $values["Fac"] * 0.01;
    $Datalog['Pac'] = $values["Pac"];
    $Datalog['Temp'] = $values["Temp"] * 0.1;
    $Datalog['todaykWh'] = $values["todaykWh"] * 0.1;

    $Datalog['Ppv'] = (($values["Vpv1"]*$values["Ipv1"])+($values["Vpv2"]*$values["Ipv2"]))*0.01;
    $Datalog['efficiency'] = $Pac/$Ppv;

    logthis('Debug', 'Parsed values: '.json_encode($Datalog));
} // function process66

function process43 ($payload, &$Datalog) {
    try {
        $values = unpack("A16inverterID",$payload,1);
    } catch (Exception $e) {
        http_response_code(500);
        die('Not a valid Goodwe payload');
    }
    $Datalog['inverterID'] = $values["inverterID"];
} // function process43

date_default_timezone_set('CET');
$now = date("H:i:s");
$today = date("Y-m-d");

$payload = file_get_contents("php://input");
// Log payload irrespective of content
logPayload($config['outputPath'], $today, $now, $payload);

if ($_SERVER['REQUEST_METHOD'] != 'POST') {
    http_response_code(501);
    die('HTTP Method "'.$_SERVER['REQUEST_METHOD'].'" not implemented');
}
if (strlen($payload) < 17) {
// Need the inverterID at minimum
    http_response_code(501);
    die('Post body too short: '.strlen($payload).' sent, minimum 17 required');
} elseif (strlen($payload) < 66) {
// First payload of the day is short (43 char)
    process43($payload, $Datalog);
    // Don't know what the rest of the payload is... taken from capture
    print($Datalog['inverterID'].hex2bin('00000000037a'));
} else {
// Full payload
    process66($payload, $Datalog);
#    $responseBody = postGoodwe($config['Goodwe'], $payload);
    postPVOutput($config['PVOutput'], $Datalog);
    logData($config['outputPath'], $Datalog);
    // Echo response from Goodwe to the client
    print($responseBody);
}

?>
