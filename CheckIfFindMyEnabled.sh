#!/bin/bash
#
# Name: CheckIfFindMyEnabled.sh
# Author: Austin Bowers abowers3@verabradley.com
# Date: February 1, 2022
#
# Description:
# This script checks to see if Find My Mac is enabled.
#
# Version Info:
# 1.0 - Initial Script (AB)

# Define Variables
plistBud="/usr/libexec/PlistBuddy"
currentUser=$( /usr/bin/stat -f "%Su" /dev/console )

# Checks .plist file to see if iCloud is signed in, if yes, check FMM status
for User in $(ls /Users)
do
    if [[ -e "/Users/$User/Library/Preferences/MobileMeAccounts.plist" ]]; then
        FindMyMac=`$plistBud -c 'print ":Accounts:0:Services:12:Enabled"' /Users/$User/Library/Preferences/MobileMeAccounts.plist`

        # Check FMM Status
        if [[ $FindMyMac == "true" ]];
        then
            echo "Find My Mac is enabled for user $User."
            exit 1
        else
            echo "Find My Mac is not enabled for user $User."
        fi
    else
        echo "iCloud is not signed in."
    fi
done