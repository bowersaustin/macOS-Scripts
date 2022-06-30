#!/bin/bash

# Name: AllowSysPrefsPanes.sh
# Author: Matt Krause mkrause@hccsc.k12.in.us
# Date: August 14, 2019
#
# Notes:
# This script opens specific System Preference panes for standard users.
#
# Version Info:
# 1.0 - Initial script (MK) [8-14-19]
# 2.0 - Updated for VB (AB) [11-9-21]


# First, enable changes to specific panes
security authorizationdb write system.preferences allow

# Allow Date and Time
security authorizationdb write system.preferences.datetime allow

# Allow Network Preferences
security authorizationdb write system.preferences.network allow
security authorizationdb write system.services.systemconfiguration.network allow
/usr/libexec/airportd prefs RequireAdminNetworkChange=NO RequireAdminIBSS=NO

# Allow Printers
security authorizationdb write system.preferences.printing allow
security authorizationdb write system.print.operator allow
dseditgroup -o edit -n /Local/Default -a everyone -t group lpadmin