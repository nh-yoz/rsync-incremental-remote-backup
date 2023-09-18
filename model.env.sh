#!/bin/bash
# This file contains the environmental variables for the script ssh_rsync_backup
# Copy as a new filename (e.g. raspberry.env.sh) and change it to fit your needs

# SSH connection
SSH_HOST="mydomain.com" # The distant server to connect to (domain name or ip-address)
SSH_PORT="22" # The ssh port on the distant server
SSH_LOGIN="my_login" # username on distant server
SSH_ID_PATH="/path/to/.ssh/id_ed25519" # Private key file (for which the public key is known by distant server)

# Files/paths
DESTINATION_ROOT="/path/to/destination" # Absolute path and don't include a final "/"
DISTANT_FOLDERS=("/path/to/a/folder" "/path/to/another/folder) # list remote folder (absolute paths and do not include a final "\")
EXCLUDE="{'*.log', '*@eaDir*'}" # List of files/folders to exclude. Separate with comma

# Number of backups to keep
MAX_INCREMENT=10 # The maximum number of incremental backups (< 1 = no limit)

# Email and alert options
EMAIL_HOST="mail.mydomain.com"
EMAIL_USERNAME="my_email_username"
EMAIL_PASSWORD="I_will_not_tell_you_if_you_ask"
EMAIL_PROTOCOL="smtps" # smtp / smtps
EMAIL_PORT=465 # smtp (usually port 25) or smtps (usually port 465)
EMAIL_FROM="your_email@mydomain.com" # email of sender
EMAIL_RECIPIENT="another_email@mydomain.com" # Recipient of report email
SEND_REPORT="A" # A=Always send report; F=Failure (send only if error occurred); N=Never (don't send email)
ALERT_DISK_MOUNT_POINT='/mnt/whatever' # Mount-point of partition to check - If none (""), don't check/alert by email
ALERT_DISK_SPACE='50000000000' # Alert if available space (in bytes) is < to this value
