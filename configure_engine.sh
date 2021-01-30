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
# DE=$1
# HOSTNAME=$2
# SYSADMIN_NEW_PASSWD=$3
# SYSADMIN_EMAILADDRESS=$4
# ADMIN_NEW_PASSWD=$5
# ADMIN_EMAILADDRESS=$6
# NTPSERVER=$7  #You can specify multiple servers with quotes: "timesvr1.me.com,timesvr2.me.com"
# TIMEZONE=$8  #Timezones are like Europe/Rome, America/New_York, UTC, Asia/Tokyo, etc.
# ENGTYPE=$9 # Must be VIRTUALIZATION or MASKING


SYSADMIN_USR=sysadmin
SYSADMIN_DEFAULT_PASSWD=sysadmin
ADMIN_USR=admin
ADMIN_DEFAULT_PASSWD=admin

source config.shlib

#export URL


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


function login {
	eval USERNAME="$1"
	eval PASSWORD="$2"

	echo "Creating API Session"
	APICALL="resources/json/delphix/session"
	read -r -d '' PAYLOAD <<-EOF
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
	read -r -d '' PAYLOAD <<-EOF
	{
					"type": "LoginRequest",
					"username": "$USERNAME",
					"password": "$PASSWORD"
	}
	EOF
	post "\${APICALL}" "\${PAYLOAD}"
}

function initialize
	{
	echo "Login as SYSADMIN with DEFAULT PASSWORD"
	login $SYSADMIN_USR $SYSADMIN_DEFAULT_PASSWD

	echo "Check whether the engine has already been configured"
	echo GET ${URL}/resources/json/delphix/about
	ABOUT=$(curl -s -k -l -X GET ${URL}/resources/json/delphix/about -b ~/cookies.txt -H "Content-Type: application/json")
	echo $ABOUT | grep '"configured":true'
	if [ $? == 0 ]; then
		echo
		echo $1 is already configured aborting.;
		exit 1
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
	read -r -d '' PAYLOAD <<-EOF
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
	read -r -d '' PAYLOAD <<-EOF
		{
				"type": "User",
				"passwordUpdateRequested": false,
				"emailAddress": "$SYSADMIN_EMAILADDRESS"
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

	echo "Login as SYSADMIN with DEFAULT PASSWORD"
	login $SYSADMIN_USR $SYSADMIN_DEFAULT_PASSWD

	echo "Register appliance"
	APICALL="resources/json/delphix/registration/status"
	read -r -d '' PAYLOAD <<-EOF
		{
			"status":"REGISTERED",
			"type":"RegistrationStatus"
		}
	EOF
	post "\${APICALL}" "\${PAYLOAD}"


	echo "Set engine type"
	APICALL="resources/json/delphix/system"
	read -r -d '' PAYLOAD <<-EOF
	{
	 "type": "SystemInfo",
	 "engineType": "$ENGTYPE"
	}
	EOF
	post "\${APICALL}" "\${PAYLOAD}"


	echo "Login as ADMIN with DEFAULT PASSWORD"
	login $ADMIN_USR $ADMIN_DEFAULT_PASSWD

	echo "Set new password for admin"
	APICALL="resources/json/delphix/user/USER-2/updateCredential"
	read -r -d '' PAYLOAD <<-EOF
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
	read -r -d '' PAYLOAD <<-EOF
		{
				"type": "User",
				"passwordUpdateRequested": false,
				"emailAddress": "$ADMIN_EMAILADDRESS"
		}
	EOF
	post "\${APICALL}" "\${PAYLOAD}"

}



function set_time
{
	echo "Login as SYSADMIN with NEW PASSWORD"
	login $SYSADMIN_USR $SYSADMIN_NEW_PASSWD
	debug "TIMEZONE: "$TIMEZONE
	debug "NTPSERVER: "$NTPSERVER
	echo "Set NTP"
	APICALL="resources/json/delphix/service/time"
	read -r -d '' PAYLOAD <<-EOF
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
}


function set_mail
{
	echo "Login as SYSADMIN with NEW PASSWORD"
	login $SYSADMIN_USR $SYSADMIN_NEW_PASSWD
	debug "SMTP_SERVER: "$SMTP_SERVER
	debug "SMTP_SERVER: "$SMTP_PORT
	echo "Set SMTP Server"
	APICALL="resources/json/delphix/service/smtp"
	read -r -d '' PAYLOAD <<-EOF
		{
			"type": "SMTPConfig",
			"enabled": true,
			"sendTimeout": 60,
			"server": "$SMTP_SERVER",
			"port": $SMTP_PORT
		}
	}
	EOF
	post "\${APICALL}" "\${PAYLOAD}"
}

function set_ldap
{
	echo "Login as SYSADMIN with NEW PASSWORD"
	login $SYSADMIN_USR $SYSADMIN_NEW_PASSWD
	debug "LDAP_SERVER: "$LDAP_SERVER
	debug "LDAP_PORT: "$LDAP_PORT
	echo "Set LDAP Server"
	APICALL="resources/json/delphix/service/ldap/server"
	read -r -d '' PAYLOAD <<-EOF
		{
			"type": "LdapServer",
			"host": "$LDAP_SERVER",
			"port": $LDAP_PORT,
			"authMethod": "SIMPLE",
			"useSSL": false
		}
	}
	EOF
	post "\${APICALL}" "\${PAYLOAD}"
}


function set_webproxy
{
	echo "Login as SYSADMIN with NEW PASSWORD"
	login $SYSADMIN_USR $SYSADMIN_NEW_PASSWD
	debug "PROXY_SERVER: "$PROXY_SERVER
	debug "PROXY_USERNAME: "$PROXY_USERNAME
	debug "PROXY_PASSWORD: "$PROXY_PASSWORD
	echo "Set Proxy Server"
	APICALL="resources/json/delphix/service/proxy"
	read -r -d '' PAYLOAD <<-EOF
	{
		"type": "ProxyService",
		"https": {
			"type": "ProxyConfiguration",
			"enabled": true,
			"host": "$PROXY_SERVER",
			"username": "$PROXY_USERNAME",
			"password": "$PROXY_PASSWORD"
		}
	}
	EOF
	post "\${APICALL}" "\${PAYLOAD}"
}



function usage
{
	echo "Usage..."
}

function debug
{
	MESSAGE="$1"
	if [[ "$DEBUG" == "true" ]]; then
		echo "DEBUG: "$MESSAGE
	fi
}

function exit_abnormal
{
	echo "ERROR: Something went wrong"
	usage
	exit 1
}

CONFIGURE_ONLY=false
TIME=false
MAIL=false
LDAP=false
KERBEROS=false
WEBPROXY=false
DEBUG=false

while getopts "cmlkwhdat" OPTION; do
		case $OPTION in
		c)
				CONFIGURE_ONLY=true  #Skips disk init, (SYS)ADMIN password changes and email, register, and engine type
				;;
		m)
				MAIL=true
				;;
		t)
				TIME=true
				;;
		# l)
		#     TYPE=$OPTARG
		#     if [ $TYPE != "source" ] && [ $TYPE != "target" ]; then
		#         echo "-t Type must be \"source\" or \"target\""
		#         exit_abnormal
		#     fi
		#     ;;
		l)
				LDAP=true
				;;
		k)
				KERBEROS=true
				;;
		w)
				WEBPROXY=true
				;;
		# a)
		#     AUTHTYPE=$OPTARG
		#     if [ $AUTHTYPE != "key" ] && [ $AUTHTYPE != "passwd" ]; then
		#         echo "-a Authorization Type must be \"key\" or \"passwd\""
		#         exit_abnormal
		#     fi
		#     ;;
		h)
				usage
				exit 0
				;;
		d)
				DEBUG=true
				;;
		a)
				MAIL=true
				LDAP=true
				KERBEROS=true
				WEBPROXY=true
				TIME=true
				;;
		:)
				echo "Missing option argument for -$OPTARG" >&2
				exit_abnormal
				;;
		*)
				echo "Incorrect options provided"
				exit_abnormal
				;;
		esac
done

#Eliminate flags and set $@ to remaining arguments
shift $((OPTIND-1))

#Check parameters

#Define Mandatory Parameters

if [ $# -ne 1 ]; then
	echo "You must provide one arguments:  IP Address (or resolvable hostname) of DE"
	exit_abnormal
fi

# if [ -z "$TYPE" ]; then
#   echo "You must specify -t <source|target>"
#   exit_abnormal
# fi
#
# #Define Invalid Parameter Combinations
# if [ ${TYPE} = "source" ] && [ ${KERNEL} = "true" ]; then
#    echo "It's an invalid combination to use -k and -t source."
#    exit_abnormal
# fi
#
# if [ -n "${AUTHTYPE}" ]; then
#   if [ ${AUTHTYPE} = "passwd" ] && [ ${QUIET} = "true" ]; then
#    echo "It's an invalid combination to use -a passwd and -q (quiet) because the passwd function is interactive."
#    exit_abnormal
#   fi
# fi

#Set variables based on user input
DE=$1
debug "DE: "$DE

#Show variables from config.cfg
echo "User Values from config.cfg"
cat config.cfg


URL=https://${DE}
debug "URL: "$URL

SYSADMIN_NEW_PASSWD="$(config_get SYSADMIN_NEW_PASSWD)"
SYSADMIN_EMAILADDRESS="$(config_get SYSADMIN_EMAILADDRESS)"
ADMIN_NEW_PASSWD="$(config_get ADMIN_NEW_PASSWD)"
ADMIN_EMAILADDRESS="$(config_get ADMIN_EMAILADDRESS)"
NTPSERVER="$(config_get NTPSERVER)"
TIMEZONE="$(config_get TIMEZONE)"
ENGTYPE="$(config_get ENGTYPE)"
SMTP_SERVER="$(config_get SMTP_SERVER)"
SMTP_PORT="$(config_get SMTP_PORT)"
LDAP_SERVER="$(config_get LDAP_SERVER)"
LDAP_PORT="$(config_get LDAP_PORT)"
PROXY_SERVER="$(config_get PROXY_SERVER)"
PROXY_USERNAME="$(config_get PROXY_USERNAME)"
PROXY_PASSWORD="$(config_get PROXY_PASSWORD)"

# SYSADMIN_EMAILADDRESS=$4
# ADMIN_NEW_PASSWD=$5
# ADMIN_EMAILADDRESS=$6
# NTPSERVER=$7  #You can specify multiple servers with quotes: "timesvr1.me.com,timesvr2.me.com"
# TIMEZONE=$8  #Timezones are like Europe/Rome, America/New_York, UTC, Asia/Tokyo, etc.
# ENGTYPE=$9 # Must be VIRTUALIZATION or MASKING



#Main action
if [[ "$CONFIGURE_ONLY" == "false" ]]; then
	initialize
fi

if [[ "$TIME" == "true" ]]; then
	set_time
fi
if [[ "$MAIL" == "true" ]]; then
	set_mail
fi
if [[ "$LDAP" == "true" ]]; then
	set_ldap
fi
if [[ "$KERBEROS" == "true" ]]; then
	echo "KERBEROS NOT YET IMPLEMENTED IN THIS SCRIPT"
#	set_kerberos
fi
if [[ "$WEBPROXY" == "true" ]]; then
	set_webproxy
fi





exit 0
