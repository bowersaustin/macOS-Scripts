#!/bin/bash
#
# Name: EnsureUserAndBothAdminsHaveASecureToken.sh
# Author: Austin Bowers abowers3@verabradley.com
# Date: November 11, 2021
#
# Notes:
# This script ensures that three users have Secure Tokens. 1 being a normal
# local admin ($localAdminUser), 2 being a secondary local admin ($secureTokenAcct)
# that isn't used other than managing password changes for $localAdminUser, and 3 being
# the currently logged in user. For situations that involve needing the end user's 
# password, an osascript is utilized to collect it. A pop-up will appear asking the 
# user for their password. This script checks and resolves these three situations,
# with the end goal being all 3 users having a Secure Token:
#
# 1. $localAdminUser is the only user with a Secure Token.
# 2. $secureTokenAcct is the only user with a Secure Token.
# 3. $currentUser is the only user with a Secure Token.
#
# Prerequisites:
# 1. Assign variables 4, 5, 6, and 7 in Jamf / FileWave before running this 
# script, and customize the variables below to your liking. 
#
# Variable descriptions:
# $4 is the secondary local admin username
# $5 is the secondary local admin password
# $6 is the primary local admin username
# $7 is the primary local admin password
#
# Recommendations:
# 1. Generate a random string of uppercase, lowercase, and numbers 
# to be used for $5. Symbols get a little weird sometimes in macOS. Do not share 
# that password with anyone, but keep it noted somewhere in case it's needed 
# again. (Which it will be if you plan on changing $6's password again in the future.)
# 2. Do not use $4 in any way except for this script.
# 3. Do not enter data into the $4-$7 variables below. I highly recommend
# that you hide the variables in FileWave / Jamf to prevent the credentials
# from being on the computer at any time. The only variables you may want to 
# change is $outLog, $messageBoxTitle, $messageBoxMessage, and $nonJamfSystemEventErrorNotification. 
# 4. Jamf notifications are built in, but FW is not. If not using Jamf,
# modify the $nonJamfSystemEventErrorNotification variable with a 
# command that will cause a notification to appear when there's an error
# involving the System Event pop-up asking the user for their password. 
#
# Version Info:
# 1.0 - Initial script (AB)

# Define Variables
outLog=/var/log/jamf.log
messageBoxTitle="VRA Technology Department"
nonJamfSystemEventErrorNotification="No third party notification software set."

# ******* Do not modify these two variables *******
currentUser=$( /usr/bin/stat -f "%Su" /dev/console )
fullName=$( /usr/bin/id -F "$currentUser" )
# *************************************************

# Feel free to customize this variable
messageBoxMessage="Hello $fullName! Please enter your password to finish setup."

# ************************************************* #
# *** Do not modify anything below this comment *** #
# ************************************************* #

exec 1>>$outLog
exec 2>>$outLog

# Define Variables
secureTokenAcct=$4
secureTokenAcctPass=$5
localAdminUser=$6
localAdminPass=$7
acctExists=$(dscl . -ls /Users | grep -i $secureTokenAcct)
localAdmins=$(dscl . -read /Groups/admin GroupMembership)

# Check that $secureTokenAcct exists. If not, create it.
if [[ $secureTokenAcct == $acctExists ]];
then
    echo "$secureTokenAcct already exists, checking Secure Token Status.." >> $outLog
    sysadminctl -secureTokenStatus $secureTokenAcct
    secureTokenAcctSecureTokenStatus=`tail -1 $outLog`
    if [[ $secureTokenAcctSecureTokenStatus == *"DISABLED"* ]];
    then
    	echo "$secureTokenAcct does not have a Secure Token. Will attempt to grant.." >> $outLog
    else
    	echo "$secureTokenAcct has a Secure Token." >> $outLog
    	secureTokenAcctHasSecureToken="Yes"
    fi
else
	# Obtains the last UID created by this script and sets the new UID to be one greater to avoid conflict.
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

	# Create $secureTokenAcct
    echo "Account $secureTokenAcct does not exist, creating.." >> $outLog
    dscl . -create "/Users/$secureTokenAcct"
    dscl . -create "/Users/$secureTokenAcct" UserShell /bin/bash
    dscl . -create "/Users/$secureTokenAcct" RealName "$secureTokenAcct"
    dscl . -create "/Users/$secureTokenAcct" UniqueID "$nextUID"
    dscl . -create "/Users/$secureTokenAcct" PrimaryGroupID 20
    dscl . -create "/Users/$secureTokenAcct" NFSHomeDirectory /Users/$secureTokenAcct
    dscl . -create "/Users/$secureTokenAcct" IsHidden 1
    dscl . -passwd "/Users/$secureTokenAcct" $secureTokenAcctPass
    dscl . -append "/Groups/admin" GroupMembership $secureTokenAcct

    # Verify creation was successful
    acctExists=$(dscl . -ls /Users | grep -i $secureTokenAcct)
    if [[ $secureTokenAcct == $acctExists ]];
    then
    	echo "$secureTokenAcct creation successful." >> $outLog
    else
    	echo "$secureTokenAcct creation failed. Exiting.." >> $outLog
    	exit 1
    fi
fi

# Exit if $localAdminUser is currently logged in. 
if [[ $currentUser == $localAdminUser ]];
then
	if [ -e /usr/local/jamf/bin/jamf ];
	then
		echo "$localAdminUser is currently logged in. Run this script when the user is logged in. Exiting.." >> $outLog
		exit 0
	else
		echo "$localAdminUser is currently logged in. Run this script when the user is logged in. Exiting.." >> $outLog
		exit 18
	fi
fi

# Check which situation the computer is in involving Secure Tokens
sysadminctl -secureTokenStatus $currentUser
currentUserSecureTokenStatus=`tail -1 $outLog`
if [[ $currentUserSecureTokenStatus == *"DISABLED"* ]];
then
	echo "$currentUser does not have a Secure Token. Checking if $secureTokenAcct has one.." >> $outLog
	sysadminctl -secureTokenStatus $secureTokenAcct
	secureTokenAcctSecureTokenStatus=`tail -1 $outLog`
	if [[ $secureTokenAcctSecureTokenStatus == *"DISABLED"* ]];
	then
		echo "$secureTokenAcct also does not have a Secure Token. checking if $localAdminUser has one.." >> $outLog
		sysadminctl -secureTokenStatus $localAdminUser
		localAdminSecureTokenStatus=`tail -1 $outLog`
		if [[ $localAdminSecureTokenStatus == *"DISABLED"* ]];
		then
			echo "$secureTokenAcct, $currentUser, nor $localAdminUser has a Secure Token. Exiting.." >> $outLog
			exit 2
		else
			echo "$localAdminUser has a Secure Token, but $currentUser and $secureTokenAcct do not. Continuing.."
			secureTokenSituation="1"
		fi
	else
		echo "$secureTokenAcct has a Secure Token, and $currentUser does not. Continuing.." >> $outLog
		secureTokenSituation="2"
	fi
else
	echo "$currentUser has a Secure Token. Checking to see if $secureTokenAcct has one.." >> $outLog
	sysadminctl -secureTokenStatus $secureTokenAcct
	secureTokenAcctSecureTokenStatus=`tail -1 $outLog`
	if [[ $secureTokenAcctSecureTokenStatus == *"DISABLED"* ]];
	then
		echo "$currentUser has a Secure Token, and $secureTokenAcct does not. Continuing.." >> $outLog
		secureTokenSituation="3"
	else
		echo "$currentUser has a Secure Token, and $secureTokenAcct also does. Checking if $localAdminUser has one.." >> $outLog
		sysadminctl -secureTokenStatus $localAdminUser
		localAdminSecureTokenStatus=`tail -1 $outLog`
		if [[ $localAdminSecureTokenStatus == *"DISABLED"* ]];
		then
			echo "$localAdminUser does not have a Secure Token. Will attempt to grant.." >> $outLog
			sysadminctl -secureTokenOn $localAdminUser -password $localAdminPass -adminUser $secureTokenAcct -adminPassword $secureTokenAcctPass
			sysadminctl -secureTokenStatus $localAdminUser
			localAdminSecureTokenStatus=`tail -1 $outLog`
			if [[ $localAdminSecureTokenStatus == *"DISABLED"* ]];
			then
				echo "Secure Token grant failed. Exiting.." >> $outLog
				exit 17
			else
				echo "Secure Token grant successful. Exiting.." >> $outLog
				exit 0
			fi
		else
			echo "$secureTokenAcct, $currentUser, and $localAdminUser all have Secure Tokens. All is well. Exiting.." >> $outLog
			exit 0
		fi
	fi
fi

# Pop up message box, collect user password
currentUserPass="$(/usr/bin/osascript -e 'display dialog "'"$messageBoxMessage"'" default answer "" with title "'"$messageBoxTitle"'" with text buttons {"Enter"} default button 1 with hidden answer' -e 'text returned of result')"
systemEventFail=`tail -1 $outLog`

# Check for System Event failures
if [[ $systemEventFail == *"-600"* ]];
then
	echo "System Events stuck. Quitting System Events, then trying again.."
	killall "System Events"

	# Pop up message box, collect user password
	echo "Attempting to collect currentUserPass" >> $outLog
	currentUserPass="$(/usr/bin/osascript -e 'display dialog "'"$messageBoxMessage"'" default answer "" with title "'"$messageBoxTitle"'" with text buttons {"Enter"} default button 1 with hidden answer' -e 'text returned of result')"
	systemEventFail=`tail -1 $outLog`

	if [[ $systemEventFail == *"Not authorized to send Apple"* ]];
	then
		echo "System Events are not authorized in privacy settings. Rerun script after user approves privacy setting. Exiting.." >> $outLog
		open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
		if [ -e /usr/local/jamf/bin/jamf ];
		then
			/usr/local/jamf/bin/jamf displayMessage -message "Please check the System Events box next to jamf on the right in System Preferences."
		else
			$nonJamfSystemEventErrorNotification
		fi
		exit 3
	else
		if [[ $systemEventFail == *"-600"* ]];
		then
			echo "Attempting to collect currentUserPass" >> $outLog
			currentUserPass="$(/usr/bin/osascript -e 'display dialog "'"$messageBoxMessage"'" default answer "" with title "'"$messageBoxTitle"'" with text buttons {"Enter"} default button 1 with hidden answer' -e 'text returned of result')"
			systemEventFail=`tail -1 $outLog`

			if [[ $systemEventFail == *"-600"* ]];
			then
				echo "System Events enabled, but still stuck. Recommend restarting computer. Exiting.."
				exit 4
			else
				if [[ $systemEventFail == *"Not authorized to send Apple"* ]];
				then
					echo "System Events are not authorized in privacy settings. Rerun script after user approves privacy setting. Exiting.." >> $outLog
					open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
					if [ -e /usr/local/jamf/bin/jamf ];
					then
						/usr/local/jamf/bin/jamf displayMessage -message "Please check the System Events box next to jamf on the right in System Preferences."
					else
						$nonJamfSystemEventErrorNotification
					fi
					exit 5
				fi
			fi
		else
			if [[ $systemEventFail == *"Not authorized to send Apple"* ]];
			then
				echo "System Events are not authorized in privacy settings. Rerun script after user approves privacy setting. Exiting.." >> $outLog
				open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
				if [ -e /usr/local/jamf/bin/jamf ];
				then
					/usr/local/jamf/bin/jamf displayMessage -message "Please check the System Events box next to jamf on the right in System Preferences."
				else
					$nonJamfSystemEventErrorNotification
				fi
				exit 6
			fi
		fi
	fi
else
	if [[ $systemEventFail == *"Not authorized to send Apple"* ]];
	then
		echo "System Events are not authorized in privacy settings. Rerun script after user approves privacy setting. Exiting.." >> $outLog
		open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
		if [ -e /usr/local/jamf/bin/jamf ];
		then
			/usr/local/jamf/bin/jamf displayMessage -message "Please check the System Events box next to jamf on the right in System Preferences."
		else
			$nonJamfSystemEventErrorNotification
		fi
		exit 7
	fi
fi

# Situation 1 ($localAdminUser is the only user with a Secure Token)
# Grant $secureTokenAcct Secure Token
if [[ $secureTokenSituation == "1" ]];
then
	# Grant $secureTokenAcct Secure Token
	echo "Granting Secure Token for $secureTokenAcct" >> $outLog
	sysadminctl -secureTokenOn $secureTokenAcct -password $secureTokenAcctPass -adminUser $localAdminUser -adminPassword $localAdminPass
	sysadminctl -secureTokenStatus $secureTokenAcct
	secureTokenAcctSecureTokenStatus=`tail -1 $outLog`
	if [[ $secureTokenAcctSecureTokenStatus == *"DISABLED"* ]];
	then
		echo "Secure Token grant failed. Exiting.." >> $outLog
		exit 8
	else
		echo "Secure Token successfully granted to $secureTokenAcct." >> $outLog
	fi

	# Revoke $localAdminUser Secure Token
	#echo "Revoking Secure Token from $localAdminUser.." >> $outLog
	#sysadminctl -secureTokenOff $localAdminUser -password $localAdminPass -adminUser $secureTokenAcct -adminPassword $secureTokenAcctPass
	#sysadminctl -secureTokenStatus $localAdminUser
	#localAdminSecureTokenStatus=`tail -1 $outLog`
	#if [[ $localAdminSecureTokenStatus == *"DISABLED"* ]];
	#then
	#	echo "Local Admin Secure Token revoke successful. Continuing.." >> $outLog
	#else
	#	echo "Local Admin Secure Token revoke failed. Exiting.." >> $outLog
	#	exit 9
	#fi

	# Grant $currentUser Secure Token (Attempt 1/3)
	echo "Granting Secure Token for $currentUser" >> $outLog
	sysadminctl -secureTokenOn $currentUser -password $currentUserPass -adminUser $secureTokenAcct -adminPassword $secureTokenAcctPass
	sysadminctl -secureTokenStatus $currentUser
	currentUserSecureTokenStatus=`tail -1 $outLog`
	if [[ $currentUserSecureTokenStatus == *"DISABLED"* ]];
	then
		echo "Secure Token grant failed. Trying again.." >> $outLog

		# Pop up message box, collect user password
		messageBoxMessage="You may have incorrectly typed in your password. Please try again."
		currentUserPass="$(/usr/bin/osascript -e 'display dialog "'"$messageBoxMessage"'" default answer "" with title "'"$messageBoxTitle"'" with text buttons {"Enter"} default button 1 with hidden answer' -e 'text returned of result')"

		# Grant $currentUser Secure Token (Attempt 2/3)
		sysadminctl -secureTokenOn $currentUser -password $currentUserPass -adminUser $secureTokenAcct -adminPassword $secureTokenAcctPass

		# Checks to see if successful
		sysadminctl -secureTokenStatus $currentUser
		currentUserSecureTokenStatus=`tail -1 $outLog`
		if [[ $currentUserSecureTokenStatus == *"DISABLED"* ]];
		then
			echo "2nd attempt failed, trying again.." >> $outLog

			# Pop up message box, collect user password
			messageBoxMessage="You may have incorrectly typed in your password. Please try again."
			currentUserPass="$(/usr/bin/osascript -e 'display dialog "'"$messageBoxMessage"'" default answer "" with title "'"$messageBoxTitle"'" with text buttons {"Enter"} default button 1 with hidden answer' -e 'text returned of result')"

			# Grant $currentUser Secure Token (Attempt 3/3)
			sysadminctl -secureTokenOn $currentUser -password $currentUserPass -adminUser $secureTokenAcct -adminPassword $secureTokenAcctPass

			# Checks to see if successful
			sysadminctl -secureTokenStatus $currentUser
			currentUserSecureTokenStatus=`tail -1 $outLog`
			if [[ $currentUserSecureTokenStatus == *"DISABLED"* ]];
			then
				echo "3 attempts have failed. Exiting.." >> $outLog
				exit 10
			else
				echo "3rd attempt successful. $secureTokenAcct, $currentUser, and $localAdminUser have Secure Tokens. Exiting.." >> $outLog
				exit 0
			fi
		else
			echo "2nd attempt successful. $secureTokenAcct, $currentUser, and $localAdminUser have Secure Tokens. Exiting.." >> $outLog
			exit 0
		fi
	else
		echo "1st attempt successful. $secureTokenAcct, $currentUser, and $localAdminUser have Secure Tokens. Exiting.." >> $outLog
		exit 0
	fi			
fi

# Situation 2 ($secureTokenAcct is the only user with a Secure Token)
if [[ $secureTokenSituation == "2" ]];
then
	# Grant $currentUser Secure Token (3 attempts) (Attempt 1/3)
	echo "Granting $currentUser Secure Token.." >> $outLog
	sysadminctl -secureTokenOn $currentUser -password $currentUserPass -adminUser $secureTokenAcct -adminPassword $secureTokenAcctPass

	# Checks to see if successful
	sysadminctl -secureTokenStatus $currentUser
	currentUserSecureTokenStatus=`tail -1 $outLog`
	if [[ $currentUserSecureTokenStatus == *"DISABLED"* ]];
	then
		echo "$currentUser does not have a Secure Token. User may have put in the wrong password. 2 Attempts left.." >> $outLog
		messageBoxMessage="You may have incorrectly typed in your password. Please try again."

		# Pop up message box, collect user password
		currentUserPass="$(/usr/bin/osascript -e 'display dialog "'"$messageBoxMessage"'" default answer "" with title "'"$messageBoxTitle"'" with text buttons {"Enter"} default button 1 with hidden answer' -e 'text returned of result')"

		# Grant $currentUser Secure Token
		sysadminctl -secureTokenOn $currentUser -password $currentUserPass -adminUser $secureTokenAcct -adminPassword $secureTokenAcctPass

		# Checks to see if successful (Attempt 2/3)
		sysadminctl -secureTokenStatus $currentUser
		currentUserSecureTokenStatus=`tail -1 $outLog`
		if [[ $currentUserSecureTokenStatus == *"DISABLED"* ]];
		then
			echo "$currentUser does not have a Secure Token. User may have put in the wrong password. 1 Attempt left.." >> $outLog

			# Pop up message box, collect user password
			currentUserPass="$(/usr/bin/osascript -e 'display dialog "'"$messageBoxMessage"'" default answer "" with title "'"$messageBoxTitle"'" with text buttons {"Enter"} default button 1 with hidden answer' -e 'text returned of result')"

			# Grant $currentUser Secure Token
			sysadminctl -secureTokenOn $currentUser -password $currentUserPass -adminUser $secureTokenAcct -adminPassword $secureTokenAcctPass

			# Checks to see if successful (Attempt 3/3)
			sysadminctl -secureTokenStatus $currentUser
			currentUserSecureTokenStatus=`tail -1 $outLog`
			if [[ $currentUserSecureTokenStatus == *"DISABLED"* ]];
			then
				echo "3 attempts have failed to grant $currentUser Secure Token." >> $outLog
				exit 11
			else
				echo "Attempt 3 successful. Continuing.." >> $outLog
			fi
		else
			echo "Attempt 2 successful. Continuing.." >> $outLog
		fi
	else
		echo "Attempt 1 successful. Continuing.." >> $outLog
	fi

	# Check $localAdminUser Secure Token Status
	echo "Checking if $localAdminUser has a Secure Token.." >> $outLog
	sysadminctl -secureTokenStatus $localAdminUser
	localAdminSecureTokenStatus=`tail -1 $outLog`
	if [[ $localAdminSecureTokenStatus == *"DISABLED"* ]];
	then
		echo "$localAdminUser does not have a Secure Token. Will attempt to grant.." >> $outLog
		sysadminctl -secureTokenOn $localAdminUser -password $localAdminPass -adminUser $secureTokenAcct -adminPassword $secureTokenAcctPass
		sysadminctl -secureTokenStatus $localAdminUser
		localAdminSecureTokenStatus=`tail -1 $outLog`
		if [[ $localAdminSecureTokenStatus == *"DISABLED"* ]];
		then
			echo "Secure Token grant failed. Exiting.." >> $outLog
			exit 15
		else
			echo "Secure Token grant successful." >> $outLog
		fi
	else
		echo "$localAdminUser already has a Secure Token."
	fi
	exit 0
fi

# Situation 3 ($currentUser is the only user with a Secure Token)
if [[ $secureTokenSituation == "3" ]];
then
	# Temporarily grant admin rights to $currentUser
	if [[ $localAdmins == *$currentUser* ]];
	then
		echo "$currentUser is already a local admin. Continuing.." >> $outLog
		wasAdminBefore="Yes"
	else
		echo "Granting $currentUser temporary admin rights.." >> $outLog
		dscl . -append "/Groups/admin" GroupMembership $currentUser
	fi

	# Grant $secureTokenAcct Secure Token (3 attempts) (Attempt 1/3)
	echo "Granting $secureTokenAcct Secure Token.." >> $outLog
	sysadminctl -secureTokenOn $secureTokenAcct -password $secureTokenAcctPass -adminUser $currentUser -adminPassword $currentUserPass

	# Checks to see if successful
	sysadminctl -secureTokenStatus $secureTokenAcct
	secureTokenAcctSecureTokenStatus=`tail -1 $outLog`
	if [[ $secureTokenAcctSecureTokenStatus == *"DISABLED"* ]];
	then
		echo "$secureTokenAcct does not have a Secure Token. User may have put in the wrong password. 2 Attempts left.." >> $outLog
		messageBoxMessage="You may have incorrectly typed in your password. Please try again."

		# Pop up message box, collect user password
		currentUserPass="$(/usr/bin/osascript -e 'display dialog "'"$messageBoxMessage"'" default answer "" with title "'"$messageBoxTitle"'" with text buttons {"Enter"} default button 1 with hidden answer' -e 'text returned of result')"

		# Grant $secureTokenAcct Secure Token
		sysadminctl -secureTokenOn $secureTokenAcct -password $secureTokenAcctPass -adminUser $currentUser -adminPassword $currentUserPass

		# Checks to see if successful (Attempt 2/3)
		sysadminctl -secureTokenStatus $secureTokenAcct
		secureTokenAcctSecureTokenStatus=`tail -1 $outLog`
		if [[ $secureTokenAcctSecureTokenStatus == *"DISABLED"* ]];
		then
			echo "$secureTokenAcct does not have a Secure Token. User may have put in the wrong password. 1 Attempt left.." >> $outLog

			# Pop up message box, collect user password
			currentUserPass="$(/usr/bin/osascript -e 'display dialog "'"$messageBoxMessage"'" default answer "" with title "'"$messageBoxTitle"'" with text buttons {"Enter"} default button 1 with hidden answer' -e 'text returned of result')"

			# Grant $secureTokenAcct Secure Token
			sysadminctl -secureTokenOn $secureTokenAcct -password $secureTokenAcctPass -adminUser $currentUser -adminPassword $currentUserPass

			# Checks to see if successful (Attempt 3/3)
			sysadminctl -secureTokenStatus $secureTokenAcct
			secureTokenAcctSecureTokenStatus=`tail -1 $outLog`
			if [[ $secureTokenAcctSecureTokenStatus == *"DISABLED"* ]];
			then
				echo "3 attempts have failed to grant $secureTokenAcct Secure Token." >> $outLog
				threeFailures="Yes"
			else
				echo "Attempt 3 successful. Continuing.." >> $outLog
			fi
		else
			echo "Attempt 2 successful. Continuing.." >> $outLog
		fi
	else
		echo "Attempt 1 successful. Continuing.." >> $outLog
	fi

	# Check $localAdminUser Secure Token Status
	echo "Checking if $localAdminUser has a Secure Token.." >> $outLog
	sysadminctl -secureTokenStatus $localAdminUser
	localAdminSecureTokenStatus=`tail -1 $outLog`
	if [[ $localAdminSecureTokenStatus == *"DISABLED"* ]];
	then
		echo "$localAdminUser does not have a Secure Token. Will attempt to grant.." >> $outLog
		sysadminctl -secureTokenOn $localAdminUser -password $localAdminPass -adminUser $secureTokenAcct -adminPassword $secureTokenAcctPass
		sysadminctl -secureTokenStatus $localAdminUser
		localAdminSecureTokenStatus=`tail -1 $outLog`
		if [[ $localAdminSecureTokenStatus == *"DISABLED"* ]];
		then
			echo "Secure Token grant failed. Exiting.." >> $outLog
			exit 16
		else
			echo "Secure Token grant successful." >> $outLog
		fi
	else
		echo "$localAdminUser already has a Secure Token."
	fi

	# Revoke admin rights
	if [[ $wasAdminBefore == "Yes" ]];
	then
		if [[ $threeFailures == "Yes" ]];
		then
			echo "$currentUser was a local admin before this script ran, will not revoke. $secureTokenAcct does not have a Secure Token. Exiting.." >> $outLog
			exit 12
		else
			echo "$currentUser was a local admin before this script ran. Will not revoke." >> $outLog
		fi
	else
		dscl . -delete "Groups/admin" GroupMembership $currentUser
		localAdmins=$(dscl . -read /Groups/admin GroupMembership)
		if [[ $localAdmins == *"$currentUser"* ]];
		then
			echo "Admin revoke failed. Exiting.." >> $outLog
			exit 13
		else
			if [[ $threeFailures == "Yes" ]];
			then
				echo "Admin revoke successful, but $secureTokenAcct does not have a Secure Token. Exiting.." >> $outLog
				exit 14
			else
				echo "Admin revoke successful. Exiting.." >> $outLog
			fi
		fi
	fi
fi