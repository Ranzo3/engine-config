#!/bin/sh
#================================================================================
# File:         configure_engine.sh
# Type:         bash script
# Date:         22-April 2019
# Author:       Marcin Przepiorowski Jul 2017
#               Updated by Mouhssine SAIDI Jul 2017v
#               Updated by  Carlos Cuellar - Delphix Professional Services April 2019
#               Updated by  Carlos Cuellar - Delphix Professional Services June 2019 - To work with 5.3.3+
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
#   Delphix Engine should have already OVA loaded, storage disks created and should have Network  configured with an IP assigned to it.
#   For the HOSTNAME update operation, you need to configure passwordless SSH connection between server where script is run
#   and Delphix engine --> https://docs.delphix.com/docs-old/reference/command-line-interface-guide/cli-cookbook-common-workflows-tasks-and-examples/cli-cookbook-authentication-and-users/cli-cookbook-configuring-key-based-ssh-authentication-for-automation
#
# Usage
#   ./configure_engine.sh <DELPHIX_ENGINE_IP>  <DELPHIX_HOSTNAME> <PASSWORD_TO_SET> <NTP_SERVER> <TIME_ZONE> <ENGINE_TYPE>
#
#	ENGINE_TYPE could be VIRTUALIZATION or MASKING
#
# Example
#   ./configure_engine.sh 172.16.126.153 DelphixEngine delphix m@m.com 172.16.126.2 "US/Eastern" MASKING
#================================================================================
#





# The guest running this script should have curl binary

###############################
#         Var section         #
###############################
DE=$1
HOSTNAME=$2
PASSWORD=$3
EMAILADDRESS=$4
NTPSERVER=$5
TIMEZONE=$6
ENGTYPE=$7


URL=http://${DE}

export URL

# Create API session
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/session \
  -c ~/cookies.txt -H "Content-Type: application/json" <<EOF
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
echo


echo "Authenticating to $DE..."
echo
# Authenticate to the DelphixEngine
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/login \
      -b ~/cookies.txt -c ~/cookies.txt -H "Content-Type: application/json" <<EOF1
{
      "type": "LoginRequest",
      "username": "sysadmin",
      "password": "sysadmin"
}
EOF1
echo


echo "Running storage test - it can run up to 3 hours"
#curl -s -X POST -k --data @- ${URL}/resources/json/delphix/storage/test \
#    -b ~/cookies.txt -H "Content-Type: application/json" <<EOF
#    {
#        "type": "StorageTestParameters",
#        "tests": "ALL"
#    }
#EOF


echo "Start Delphix Configuration"

echo "Set new password for sysadmin"
echo
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/user/USER-1/updateCredential \
  -b ~/cookies.txt -H "Content-Type: application/json" <<EOF
  {
      "type": "CredentialUpdateParameters",
      "newCredential": {
          "type": "PasswordCredential",
          "password": "$PASSWORD"
      }
  }
EOF
echo

echo "Set sysadmin to not ask for new password after change"
echo
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/user/USER-1 \
  -b ~/cookies.txt -H "Content-Type: application/json" <<EOF
  {
      "type": "User",
      "passwordUpdateRequested": false,
      "emailAddress": "$EMAILADDRESS"
  }
EOF


#POSTDEVICES="{\"type\": \"ControlNodeInitializationParameters\",\"devices\": ["
POSTDEVICES="{\"type\": \"SystemInitializationParameters\",\"defaultUser\":\"admin\", \"defaultPassword\": \"$PASSWORD\", \"devices\": ["

echo "Grab a list of disk devices"
echo
disks=`curl -s -X GET ${URL}/resources/json/delphix/storage/device -b ~/cookies.txt -H "Content-Type: application/json"`
#echo $disks

# line split
#lines=`echo $disks | cut -d "[" -f2 | cut -d "]" -f1 | awk -v RS='},{}' -F: '{print $0}'`
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
echo $POSTDEVICES | curl -s -X POST -k --data @- ${URL}/resources/json/delphix/domain/initializeSystem \
  -b ~/cookies.txt -H "Content-Type: application/json"
echo

sleep 60

echo "Create API session"
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/session \
  -c ~/cookies.txt -H "Content-Type: application/json" <<EOF
{
  "type": "APISession",
  "version": {
      "type": "APIVersion",
      "major": 1,
      "minor": 10,
      "micro": 4
  }
}
EOF
echo


echo "Authenticating to $DE..."
echo
# Authenticate to the DelphixEngine
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/login \
      -b ~/cookies.txt -c ~/cookies.txt -H "Content-Type: application/json" <<EOF1
{
      "type": "LoginRequest",
      "username": "sysadmin",
      "password": "$PASSWORD"
}
EOF1
echo

echo "Set NTP"
echo
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/service/time \
  -b ~/cookies.txt -H "Content-Type: application/json" <<EOF
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


echo "Set hostname"
echo
ssh sysadmin@$DE "system;update; set hostname=\"$HOSTNAME\"; commit"


echo "Register appliance"
echo
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/registration/status \
  -b ~/cookies.txt -H "Content-Type: application/json" <<EOF
  {
    "status":"REGISTERED",
    "type":"RegistrationStatus"
  }
EOF
echo

# Create API session
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/session \
  -c ~/cookies.txt -H "Content-Type: application/json" <<EOF
{
  "type": "APISession",
  "version": {
      "type": "APIVersion",
      "major": 1,
      "minor": 10,
      "micro": 5
  }
}
EOF
echo


echo "Authenticating to $DE..."
echo
# Authenticate to the DelphixEngine
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/login \
      -b ~/cookies.txt -c ~/cookies.txt -H "Content-Type: application/json" <<EOF1
{
      "type": "LoginRequest",
      "username": "admin",
      "password": "$PASSWORD"
}
EOF1
echo


echo "Set admin to not ask for new password after change"
echo
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/user/USER-2 \
  -b ~/cookies.txt -H "Content-Type: application/json" <<EOF
  {
      "type": "User",
      "passwordUpdateRequested": false,
      "emailAddress": "$EMAILADDRESS"
  }
EOF

sleep 100

# Create API session
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/session \
  -c ~/cookies.txt -H "Content-Type: application/json" <<EOF
{
  "type": "APISession",
  "version": {
      "type": "APIVersion",
      "major": 1,
      "minor": 10,
      "micro": 5
  }
}
EOF
echo


echo "Authenticating to $DE..."
echo
# Authenticate to the DelphixEngine
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/login \
      -b ~/cookies.txt -c ~/cookies.txt -H "Content-Type: application/json" <<EOF1
{
      "type": "LoginRequest",
      "username": "sysadmin",
      "password": "$PASSWORD"
}
EOF1
echo

echo "Set engine type"
echo
curl -s -X POST -k --data @- ${URL}/resources/json/delphix/system \
     -b ~/cookies.txt -H "Content-Type: application/json" <<EOF1
{
 "type": "SystemInfo",
 "engineType": "$ENGTYPE"
}
EOF1



exit 0
