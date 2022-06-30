#!/bin/bash
#
# Name: MacLAPS.sh (LocalAdminSecureTokenPasswordChangev3.0.sh)
# Author: Austin Bowers abowers3@verabradley.com
# Date: April 5, 2022
#
# Notes:
# Technically this script is version 3.0 of my LocalAdminSecureTokenPasswordChange.sh 
# script, but it has been renamed since it's purpose has been drastically changed. 
#
# This script changes the local admin password. If it has a Secure Token, the script
# will assign a Secure Token to a new user specified in the $6 variable, then use that
# to change the local admin password. This script is designed to be ran on a schedule, 
# preferably every 30 days or more. 
#
# Prerequisites:
# Assign variables 4-9 in Jamf before running script, and
# change the $outLog variable if you wanted the output to go somewhere else. 
#
# Variable descriptions:
# $4 is the local admin username
# $5 is the ssl password to decrypt the string located at $encodedPasswordLocation
# $6 is the ***NOT TO BE USED OR SHARED*** local admin with a Secure Token
# $7 is the new Secure Token local admin account password
# $8 is the password that was last used before this script was implemented
# $9 is the location for the encrypted password to be stored (e.g. /usr/local/etc/MacLAPS.txt)
#
# Reccomendations:
# 1. Generate a random string of uppercase, lowercase, and numbers 
# to be used for $7. Symbols get a little weird sometimes in macOS. Do not share 
# that password with anyone, but keep it noted somewhere.
# 2. Do not use $6 in any way except for this script.
# 3. Do not enter data into the 4-9 variables below. I highly reccomend
# that you hide the variables in Jamf to prevent the credentials
# from being on the computer at any time. The only variable you may want to 
# change is $outLog.
#
# Version Info:
# 1.0 - Initial script (AB)
# 2.0 - Updated to not remove the Secure Token from $localAdminUser (AB)
# 3.0 - Updated to randomize the local admin password, encrypt it, and send it to a 
# folder for decryption later via a Jamf Extension Attribute. (AB)
# 3.1 - Added an output to the $encodedPasswordLocation file in case the password is 
# unknown. This way it's not possible for an encoded password to appear in Jamf. 

# Log output
outLog=/var/log/jamf.log

# ************************************************* #
# *** Do not modify anything below this comment *** #
# ************************************************* #

# Define Variables
localAdminUser=$4
sslPassword=$5
secureTokenAcct=$6
secureTokenAcctPass=$7
preimplementationPassword=$8
encodedPasswordLocation=$9
acctExists=$(dscl . -ls /Users | grep -i $secureTokenAcct)
date=`date "+%Y%m%d"`
lastChangedFile="/var/log/$localAdminUser.txt"

# Current Password

# If this script hasn't run before, will encode the current local
# admin password ($preimplementationPassword) to start the process
if [[ ! -e $encodedPasswordLocation ]];
then
	preimplementationPasswordEncoded=`echo $preimplementationPassword | openssl aes-256-cbc -a -salt -pass pass:$sslPassword`
	echo $preimplementationPasswordEncoded > $encodedPasswordLocation
	currentEncodedPassword=`cat $encodedPasswordLocation`
	oldLocalAdminPass=`echo $currentEncodedPassword | openssl aes-256-cbc -d -a -pass pass:$sslPassword`
else
	currentEncodedPassword=`cat $encodedPasswordLocation`
	oldLocalAdminPass=`echo $currentEncodedPassword | openssl aes-256-cbc -d -a -pass pass:$sslPassword`
fi

# New Password
randomWord=`cat /usr/share/dict/web2 | sort -R | head -1`
randomNumber=`echo $RANDOM`
newLocalAdminPass="$randomWord$randomNumber"
newEncodedPassword=`echo $newLocalAdminPass | openssl aes-256-cbc -a -salt -pass pass:$sslPassword`

exec 1>>$outLog
exec 2>>$outLog

# Verify whether or not Secure Token is enabled for local admin
# If no, will change $localAdminUser's password
# Will try $oldLocalAdminPass first, if fail, try $olderLocalAdminPass
sysadminctl -secureTokenStatus $localAdminUser
localAdminSecureTokenStatus=`tail -1 $outLog`
if [[ $localAdminSecureTokenStatus == *"DISABLED"* ]];
then
	echo "SecureToken is not enabled for local admin. Changing password, and exiting.." >> $outLog
	dscl . -passwd "/Users/$localAdminUser" $oldLocalAdminPass $newLocalAdminPass > /var/log/passwdlog.txt
	passwdResult=$(tail -1 /var/log/passwdlog.txt)
	if [[ $passwdResult == *"AuthFailed"* ]];
	then
		echo "First attempt failed, password may already be set correctly. Checking.." >> $outLog
		dscl . -passwd "/Users/$localAdminUser" $newLocalAdminPass $newLocalAdminPass > /var/log/passwdlog.txt
		passwdResult=$(tail -1 /var/log/passwdlog.txt)
		if [[ $passwdResult == *"AuthFailed"* ]];
		then
			echo "Second attempt failed, password is unknown. Exiting.." >> $outLog
			error="Password Unknown"
			encodedError=`echo $error | openssl aes-256-cbc -a -salt -pass pass:$sslPassword`
			echo $encodedError > $encodedPasswordLocation
			exit 1
		fi
	fi
	echo "$localAdminUser's password has been changed." >>$outLog
	echo $date > $lastChangedFile
	echo $newEncodedPassword > $encodedPasswordLocation
	chmod 700 $encodedPasswordLocation
	/usr/local/bin/jamf recon
	exit 0
fi

# Create SecureTokenAdmin User if it doesn't already exist
if [[ $secureTokenAcct = $acctExists ]];
then
    echo "$secureTokenAcct already exists, double checking Secure Token Status.." >> $outLog
    sysadminctl -secureTokenStatus $secureTokenAcct
    secureTokenAcctSecureTokenStatus=`tail -1 $outLog`
    if [[ $secureTokenAcctSecureTokenStatus == *"DISABLED"* ]];
    then
    	echo "$secureTokenAcct does not have a Secure Token.. for some reason. Will attempt to grant.." >> $outLog
    else
    	echo "$secureTokenAcct has a Secure Token. Continuing.." >> $outLog
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
    echo "$secureTokenAcct creation successful" >> $outLog

    sysadminctl -secureTokenStatus $secureTokenAcct
    secureTokenAcctSecureTokenStatus=`tail -1 $outLog`
fi

# Grant $secureTokenAcct Secure Token
if [[ $secureTokenAcctSecureTokenStatus == *"DISABLED"* ]];
then
	echo "Granting Secure Token for $secureTokenAcct" >> $outLog
	sysadminctl -secureTokenOn $secureTokenAcct -password $secureTokenAcctPass -adminUser $localAdminUser -adminPassword $oldLocalAdminPass
	sysadminctl -secureTokenStatus $secureTokenAcct
	secureTokenAcctSecureTokenStatus=`tail -1 $outLog`
	if [[ $secureTokenAcctSecureTokenStatus == *"DISABLED"* ]];
	then
		echo "First attempt failed, password set for $localAdminUser must be already set. Trying the new password.." >> $outLog
		sysadminctl -secureTokenOn $secureTokenAcct -password $secureTokenAcctPass -adminUser $localAdminUser -adminPassword $newLocalAdminPass
		sysadminctl -secureTokenStatus $secureTokenAcct
		secureTokenAcctSecureTokenStatus=`tail -1 $outLog`
		if [[ $secureTokenAcctSecureTokenStatus == *"DISABLED"* ]];
		then
			echo "Second attempt failed, password set for $localAdminUser must be an older one. Trying the older password.." >> $outLog
			sysadminctl -secureTokenOn $secureTokenAcct -password $secureTokenAcctPass -adminUser $localAdminUser -adminPassword $olderLocalAdminPass
			sysadminctl -secureTokenStatus $secureTokenAcct
			secureTokenAcctSecureTokenStatus=`tail -1 $outLog`
			if [[ $secureTokenAcctSecureTokenStatus == *"DISABLED"* ]];
			then 
				echo "$localAdminUser's password isn't the current, the old, or the older password. Password is unknown. Exiting.." >> $outLog
				exit 2
			fi
		fi
	fi
	echo "Secure Token successfully granted to $secureTokenAcct." >> $outLog
fi

# Reset $localAdminUser password
echo "Resetting $localAdminUser's password.." >> $outLog
sysadminctl -resetPasswordFor $localAdminUser -newPassword $newLocalAdminPass -adminUser $secureTokenAcct -adminPassword $secureTokenAcctPass

# Check to see if password change was successful
wasPasswordChangeSuccessful=`tail -1 $outLog`
if [[ $wasPasswordChangeSuccessful == *"Done"* ]];
then
	echo "Password reset successful." >> $outLog
	echo $newEncodedPassword > $encodedPasswordLocation
	echo $date > $lastChangedFile
	chmod 700 $encodedPasswordLocation
	/usr/local/bin/jamf recon
	exit 0
else
	echo "Password reset failed." >> $outLog
	exit 3
fi