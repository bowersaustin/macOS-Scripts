#!/bin/bash
#
# Name: CreateLocalUser.sh
# Author: Austin Bowers abowers3@verabradley.com
# Date: April 13, 2022
#
# Notes:
# Allows the Helpdesk to create a new local user from Self Service.
#
# Version Info:
# 1.0 - Initial script (AB)

# Define Variables
secureTokenAcct=$4
secureTokenAcctPass=$5


messageBoxTitle="VRA Technology Department"

messageBoxMessage="Please enter the username of the user you wish to create"
newUser="$(/usr/bin/osascript -e 'display dialog "'"$messageBoxMessage"'" default answer "" with title "'"$messageBoxTitle"'" with text buttons {"Enter"} default button 1' -e 'text returned of result')"

messageBoxMessage="Please enter the Full Name (e.g. Greg DuVall) of the user you wish to create"
newUserFullName="$(/usr/bin/osascript -e 'display dialog "'"$messageBoxMessage"'" default answer "" with title "'"$messageBoxTitle"'" with text buttons {"Enter"} default button 1' -e 'text returned of result')"

messageBoxMessage="Please enter the password of the user you wish to create"
newUserPass="$(/usr/bin/osascript -e 'display dialog "'"$messageBoxMessage"'" default answer "" with title "'"$messageBoxTitle"'" with text buttons {"Enter"} default button 1 with hidden answer' -e 'text returned of result')"

# Obtains the last UID created by this script and sets the new UID to be one greater to avoid conflict
if [ -e /var/log/UIDlog.txt ];
then
	lastUID=$(tail -1 /var/log/UIDlog.txt)
	nextUID=$((lastUID+1))
	echo "$nextUID" >> /var/log/UIDlog.txt
else
	nextUID=600
	echo "$nextUID" >> /var/log/UIDlog.txt
	chflags hidden /var/log/UIDlog.txt
fi

# Create $newUser
echo "Creating $newUser.." | tee -a $outLog

dscl . -create "/Users/$newUser"
dscl . -create "/Users/$newUser" UserShell /bin/bash
dscl . -create "/Users/$newUser" RealName "$newUserFullName"
dscl . -create "/Users/$newUser" UniqueID "$nextUID"
dscl . -create "/Users/$newUser" PrimaryGroupID 20
dscl . -create "/Users/$newUser" NFSHomeDirectory /Users/$newUser
dscl . -passwd "/Users/$newUser" $newUserPass

# Update Variable
newUserExist=$(dscl . -ls /Users | grep -i $newUser)

# Verify creation was successful
if [[ $newUserExist == $newUser ]];
then
	echo "$newUser successfully created." | tee -a $outLog
else
	echo "$newUser creation failed." | tee -a $outLog
    exit 1
fi

sysadminctl -secureTokenOn $newUser -password $newUserPass -adminUser $secureTokenAcct -adminPassword $secureTokenAcctPass