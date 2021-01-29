#!/bin/bash
#
# To be run only on an unconfigured Delphix platform and will disable http, set timezone to Italy
# and initialise the system using all unused disks
#
# Usage: $0 <hostname or IP of unconfigured engine>
#
# Written by stuart williams, the POSTDEVICES creation is updated from code written by marcin przepiorowski
#

URL=http://${1}
USR=sysadmin
PASS=sysadmin

# Use curl to POST an API CALL. Checks success, reports and exists the script upon error.
function post
{
	eval APICALL="$1"
	eval PAYLOAD="$2"

	echo
	echo POST $APICALL
	OUTPUT=`curl -S -s -X POST -k -d @- ${APICALL} -b ~/cookies.txt -c ~/cookies.txt -H "Content-Type: application/json" <<EOF
		${PAYLOAD}
		EOF`
	if [ $? != 0 ]; then
		echo CURL FAILURE EXITING;
		exit 1;
	fi
	echo $OUTPUT | grep -q OKResult
	if [ $? != 0 ]; then
		 echo API call failed $OUTPUT;
		 exit 1;
		 else echo $OUTPUT;
	 fi
}


# Create an API session to the Delphix Engine
APISESSION='{ "type": "APISession", "version": { "type": "APIVersion", "major": 1, "minor": 10, "micro": 0 } }'
post "\${URL}/resources/json/delphix/session" "\${APISESSION}"

# Authenticate the API session (using escaped double quotes as there's variables in the payload)
LOGIN="{ \"type\": \"LoginRequest\", \"username\": \"${USR}\", \"password\": \"${PASS}\" }"
post "\${URL}/resources/json/delphix/login" "\${LOGIN}"

# Check whether the engine has already been configured
echo
echo GET /resources/json/delphix/about
ABOUT=$(curl -s -k -l -X GET ${URL}/resources/json/delphix/about -b ~/cookies.txt -H "Content-Type: application/json")
echo $ABOUT | grep '"configured":true'
if [ $? == 0 ]; then
	echo
	echo $1 is already configured aborting.;
	exit 1
fi

# Mark the appliance registered
STATUS='{ "status":"REGISTERED", "type":"RegistrationStatus" }'
post "\${URL}/resources/json/delphix/registration/status" "\${STATUS}"

# Disable HTTP, allowing only HTTPS
#HTTPCONN='{ "type": "HttpConnectorConfig", "httpMode": "HTTPS_ONLY" }'
#post "\${URL}/resources/json/delphix/service/httpConnector" "\${HTTPCONN}"

# Change the timezone to Italy
TIMEZONE='{"type": "TimeConfig", "systemTimeZone": "Europe/Rome" }'
post "\${URL}/resources/json/delphix/service/time" "\${TIMEZONE}"

# Initialise the Delphix engine using all unconfigured disks

# Start building the API payload
POSTDEVICES="{\"defaultUser\":\"delphix_admin\",\"defaultPassword\":\"delphix\",\"devices\":["
# Get the list of disks allocated
DISKS=`curl -s -k -l -X GET ${URL}/resources/json/delphix/storage/device -b ~/cookies.txt -H "Content-Type: application/json"`
# line split
lines=`echo $DISKS | cut -d "[" -f2 | cut -d "]" -f1 | awk -v RS='},{}' -F: '{print $0}'`
# add non configured devices to initialisation string
while read -r line ; do
  type=`echo $line | sed -e 's/[{}]/''/g' | sed s/\"//g | awk -v RS=',' -F: '$1=="configured"{print $2}'`
  if [[ "$type" == "false" ]]; then
    POSTDEVICES+="\""
    dev=`echo $line | sed -e 's/[{}]/''/g' | sed s/\"//g | awk -v RS=',' -F: '$1=="reference"{print $2}'`
    POSTDEVICES+=$dev
    POSTDEVICES+="\","
  fi
done <<< "echo $lines"
# Complete the API payload
POSTDEVICES=${POSTDEVICES::${#POSTDEVICES}-1}
POSTDEVICES+="],\"type\":\"SystemInitializationParameters\"}"

# Initialise the engine
post "\${URL}/resources/json/delphix/domain/initializeSystem" "\${POSTDEVICES}"

echo
echo "The storage pool is being configured and management services starting, will be ready in a few minutes"
