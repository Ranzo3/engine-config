#!/bin/sh
#================================================================================
# File:         configure_engine.sh
# Type:         bash script
# Date:         22-April 2019
# Author:       Marcin Przepiorowski Jul 2017
#               Updated by Mouhssine SAIDI Jul 2017v
#               Updated by  Carlos Cuellar - Delphix Professional Services April 2019
#               Updated by  Carlos Cuellar - Delphix Professional Services June 2019 - To work with 5.3.3+
#               Updated by  Ranzo Taylor - Delphix Professional Services Jan 2021
# Ownership:    This script is owned and maintained by the user, not by Delphix
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright (c) 2019 by Delphix. All rights reserved.
#
# Description:
#
#       Script to be used to configure a Delphix Engine
#
# Prerequisites:
#   Delphix Engine should have already OVA/AMI/Cloud Image loaded and should have Network  configured with an IP assigned to it.
#   This script does not handle networking:  DHCP On/Off, Static IP, Hostname, DNS, Gateway, DHCP
#
# Usage
#   ./configure_engine.sh <DELPHIX_ENGINE_IP> <DELPHIX_HOSTNAME> <SYSADMIN_NEW_PASSWD> <SYSADMIN_EMAILADDRESS> <ADMIN_NEW_PASSWD> <ADMIN_EMAILADDRESS> <NTP_SERVER(S)> <TIME_ZONE> <ENGINE_TYPE>
#
#	ENGINE_TYPE could be VIRTUALIZATION or MASKING
#
# Example
#   ./configure_engine.sh 172.16.126.153 DelphixEngine sysadminpw m@m.com adminpw m@m.com "timesvr1.me.com, timesvr2.me.com" "America/New_York" MASKING
#================================================================================
#





# The guest running this script should have curl binary

###############################
#         Var section         #
###############################
DE=$1
HOSTNAME=$2
SYSADMIN_NEW_PASSWD=$3
SYSADMIN_EMAILADDRESS=$4
ADMIN_NEW_PASSWD=$5
ADMIN_EMAILADDRESS=$6
NTPSERVER=$7  #You can specify multiple servers with quotes: "timesvr1.me.com,timesvr2.me.com"
TIMEZONE=$8  #Timezones are like Europe/Rome, America/New_York, UTC, Asia/Tokyo, etc.
ENGTYPE=$9 # Must be VIRTUALIZATION or MASKING


URL=http://${DE}
SYSADMIN_USR=sysadmin
SYSADMIN_DEFAULT_PASSWD=sysadmin

export URL


# Use curl to POST an API CALL. Checks success, reports and exists the script upon error.
function post
{
	eval APICALL="$1"
	eval PAYLOAD="$2"

	echo
	#echo POST $APICALL
	echo POST ${URL}/$APICALL $PAYLOAD
	OUTPUT=`curl -S -s -X POST -k -d @- ${URL}/${APICALL} -b ~/cookies.txt -c ~/cookies.txt -H "Content-Type: application/json" <<EOF
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
	echo
}

echo "Creating API Session"
APICALL="resources/json/delphix/session"
read -r -d '' PAYLOAD <<EOF
{
    "type": "APISession",
    "version": {
        "type": "APIVersion",
        "major": 1,
        "minor": 11,
        "micro": 0
    }
}
EOF
post "\${APICALL}" "\${PAYLOAD}"

echo "Authenticating to $DE..."
APICALL="resources/json/delphix/login"
read -r -d '' PAYLOAD <<EOF
{
        "type": "LoginRequest",
        "username": "$SYSADMIN_USR",
        "password": "$SYSADMIN_DEFAULT_PASSWD"
}
EOF
post "\${APICALL}" "\${PAYLOAD}"


echo "Check whether the engine has already been configured"
echo GET ${URL}/resources/json/delphix/about
ABOUT=$(curl -s -k -l -X GET ${URL}/resources/json/delphix/about -b ~/cookies.txt -H "Content-Type: application/json")
echo $ABOUT | grep '"configured":true'
if [ $? == 0 ]; then
	echo
	echo $1 is already configured aborting.;
	#exit 1
fi


#echo "Running storage test - it can run up to 3 hours"
#curl -s -X POST -k --data @- ${URL}/resources/json/delphix/storage/test \
#    -b ~/cookies.txt -H "Content-Type: application/json" <<EOF
#    {
#        "type": "StorageTestParameters",
#        "tests": "ALL"
#    }
#EOF


echo "Start Delphix Configuration"
printf "."; sleep 1; printf  "."; sleep 1; printf  "."; sleep 1

echo "Set new password for sysadmin"
APICALL="resources/json/delphix/user/USER-1/updateCredential"
read -r -d '' PAYLOAD <<EOF
{
			"type": "CredentialUpdateParameters",
			"newCredential": {
					"type": "PasswordCredential",
					"password": "$SYSADMIN_NEW_PASSWD"
			}
}
EOF
post "\${APICALL}" "\${PAYLOAD}"


echo "Set sysadmin to not ask for new password after change"
APICALL="resources/json/delphix/user/USER-1"
read -r -d '' PAYLOAD <<EOF
	{
			"type": "User",
			"passwordUpdateRequested": false,
			"emailAddress": "$SYSADMIN_EMAILADDRESS"
	}
EOF
post "\${APICALL}" "\${PAYLOAD}"

echo "Set new password for admin"
APICALL="resources/json/delphix/user/USER-2/updateCredential"
read -r -d '' PAYLOAD <<EOF
{
			"type": "CredentialUpdateParameters",
			"newCredential": {
					"type": "PasswordCredential",
					"password": "$ADMIN_NEW_PASSWD"
			}
}
EOF
post "\${APICALL}" "\${PAYLOAD}"


echo "Set admin to not ask for new password after change"
APICALL="resources/json/delphix/user/USER-2"
read -r -d '' PAYLOAD <<EOF
	{
			"type": "User",
			"passwordUpdateRequested": false,
			"emailAddress": "$ADMIN_EMAILADDRESS"
	}
EOF
post "\${APICALL}" "\${PAYLOAD}"


echo "Grab a list of disk devices"
echo
POSTDEVICES="{\"type\": \"SystemInitializationParameters\",\"defaultUser\":\"admin\", \"defaultPassword\": \"$ADMIN_NEW_PASSWD\", \"devices\": ["

disks=`curl -s -X GET ${URL}/resources/json/delphix/storage/device -b ~/cookies.txt -H "Content-Type: application/json"`
#echo $disks

# line split
lines=`echo $disks | cut -d "[" -f2 | cut -d "]" -f1 | awk -v RS='},{' -F: '{print $0}'`
#echo $lines

# add non configured devices to intialization string
while read -r line ; do
type=`echo $line | sed -e 's/[{}]/''/g' | sed s/\"//g | awk -v RS=',' -F: '$1=="configured"{print $2}'`
#echo $type;
if [[ "$type" == "false" ]]; then
	POSTDEVICES+="\""
	dev=`echo $line | sed -e 's/[{}]/''/g' | sed s/\"//g | awk -v RS=',' -F: '$1=="reference"{print $2}'`
	POSTDEVICES+=$dev
	POSTDEVICES+="\","
fi
done <<< "echo $lines"

POSTDEVICES=${POSTDEVICES::${#POSTDEVICES}-1}
POSTDEVICES+="]}"
#echo $POSTDEVICES
echo
echo "Kick off configuration"
APICALL="resources/json/delphix/domain/initializeSystem"
post "\${APICALL}" "\${POSTDEVICES}"
#echo $POSTDEVICES | curl -s -X POST -k --data @- ${URL}/resources/json/delphix/domain/initializeSystem \
#	-b ~/cookies.txt -H "Content-Type: application/json"
echo

echo "The storage pool is being configured and management services restarting, I will wait 2 minutes and reconnect"
for ((i = 10; i > 0; --i)); do
  printf "$i "
done

echo "Creating API Session"
APICALL="resources/json/delphix/session"
read -r -d '' PAYLOAD <<EOF
{
    "type": "APISession",
    "version": {
        "type": "APIVersion",
        "major": 1,
        "minor": 11,
        "micro": 0
    }
}
EOF
post "\${APICALL}" "\${PAYLOAD}"

echo "Authenticating to $DE..."
APICALL="resources/json/delphix/login"
read -r -d '' PAYLOAD <<EOF
{
        "type": "LoginRequest",
        "username": "$SYSADMIN_USR",
        "password": "$SYSADMIN_NEW_PASSWD"
}
EOF
post "\${APICALL}" "\${PAYLOAD}"

echo "Set NTP"
APICALL="resources/json/delphix/service/time"
read -r -d '' PAYLOAD <<EOF
	{
		"type": "TimeConfig",
		"systemTimeZone": "$TIMEZONE",
		"ntpConfig": {
			"type": "NTPConfig",
			"enabled": true,
			"servers": [
					"$NTPSERVER"
			]
	}
}
EOF
post "\${APICALL}" "\${PAYLOAD}"

#echo "Set hostname"
#echo
#ssh sysadmin@$DE "system;update; set hostname=\"$HOSTNAME\"; commit"


echo "Register appliance"
APICALL="resources/json/delphix/registration/status"
read -r -d '' PAYLOAD <<EOF
	{
		"status":"REGISTERED",
		"type":"RegistrationStatus"
	}
EOF
post "\${APICALL}" "\${PAYLOAD}"

# # Create API session
# curl -s -X POST -k --data @- ${URL}/resources/json/delphix/session \
# 	-c ~/cookies.txt -H "Content-Type: application/json" <<EOF
# {
# 	"type": "APISession",
# 	"version": {
# 			"type": "APIVersion",
# 			"major": 1,
# 			"minor": 10,
# 			"micro": 5
# 	}
# }
# EOF
# echo
#
#
# echo "Authenticating to $DE..."
# echo
# # Authenticate to the DelphixEngine
# curl -s -X POST -k --data @- ${URL}/resources/json/delphix/login \
# 			-b ~/cookies.txt -c ~/cookies.txt -H "Content-Type: application/json" <<EOF1
# {
# 			"type": "LoginRequest",
# 			"username": "admin",
# 			"password": "${ADMIN_NEW_PASSWD}"
# }
# EOF1
# echo




# sleep 100
#
# # Create API session
# curl -s -X POST -k --data @- ${URL}/resources/json/delphix/session \
# 	-c ~/cookies.txt -H "Content-Type: application/json" <<EOF
# {
# 	"type": "APISession",
# 	"version": {
# 			"type": "APIVersion",
# 			"major": 1,
# 			"minor": 10,
# 			"micro": 5
# 	}
# }
# EOF
# echo
#
#
# echo "Authenticating to $DE..."
# echo
# # Authenticate to the DelphixEngine
# curl -s -X POST -k --data @- ${URL}/resources/json/delphix/login \
# 			-b ~/cookies.txt -c ~/cookies.txt -H "Content-Type: application/json" <<EOF1
# {
# 			"type": "LoginRequest",
# 			"username": "sysadmin",
# 			"password": "${SYSADMIN_NEW_PASSWD}"
# }
# EOF1
# echo

echo "Set engine type"
APICALL="resources/json/delphix/system"
read -r -d '' PAYLOAD <<EOF
{
 "type": "SystemInfo",
 "engineType": "$ENGTYPE"
}
EOF
post "\${APICALL}" "\${PAYLOAD}"

#SMTP
#LDAP




exit 0
