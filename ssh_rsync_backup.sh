#!/bin/bash
######################################################
#
# FILENAME: ssh_rsync_backup.sh
#
# AUTHOR: Niklas HOOK
#
# DESCRIPTION
# Incremental backup of a list of remote folders to a local folder
#
# LICENCE: WTFPL - comes with no warranty
#
# Options
# -v verbose output (affects rsync and curl)
# -d dry run (don't copy/delete files)
# -e <environment file> (required)
#
# VERSIONS (number | date | author | Description)
# 1 | 2023-08-27 | Niklas HOOK | Creation
#
######################################################

Usage() {
    echo -e "Usage: ssh_rsync_backup.sh [-v] [-d] -e <environment file>\n-v: verbose\n-d: dry-run\n"
}

RSYNC_OPTIONS=()
DRY_RUN=0

while getopts "vde:" opt
do
    case $opt in
    v) RSYNC_OPTIONS+=(-v); VERBOSE='-v' ;;
    d) RSYNC_OPTIONS+=(--dry-run); DRY_RUN=1 ;;
    e) ENV_FILE=${OPTARG} ;;
    *) Usage; exit 1 ;;
    esac
done

if [ -z ${ENV_FILE+x} ]; then Usage; exit 1; fi
if [ ! -f ${ENV_FILE} ]; then echo -e "The file '${ENV_FILE}' doesn't exist.\n"; exit 2; fi

# Loading environment
. ${ENV_FILE}

# Initializing constants;
TMP_FILE=$(mktemp)
RSYNC_OPTIONS+=(-a --stats --delete --delete-excluded --log-file="${TMP_FILE}")
FILENAME="$(basename $0)"
ENV_FILENAME="$(basename ${ENV_FILE})"
LOG_FILE="$(realpath ${ENV_FILE}).log"
SUCCESS_COUNT=0
FAILURE_COUNT=0

for EX in ${EXCLUDE[@]}
do
    RSYNC_OPTIONS+=(--exclude=${EX})
done

Log() { # Print argument on one line to $TMP_LOG and to stout.
      echo -e "${1}" | tee -a "$TMP_FILE"
}

Cancel() { # Removes interrupted backup folder
    # Get the last destination folder
    if [ $RUNNING == "True" ]
    then
        Log "CAUGHT EXIT SIGNAL"
        DEST_FOLDER=$(grep 'Destination: ' "$TMP_FILE" | tail -1 | sed 's/Destination: //')
        Log "Deleting interrupted backup folder: $DEST_FOLDER..."
        rm -rf "$DEST_FOLDER"
        [ $? -eq 0 ] && Log "Done" || Log "Error"
        cat "$TMP_FILE" >> "$LOG_FILE"
    fi
    rm -f "$TMP_FILE"
}

trap "Cancel" EXIT

GetDateTime() {
    echo "$(date '+%Y-%m-%d_%Hh%Mm%Ss')" # The current date and time
}

Log "**************************************
**  Running script "$FILENAME" $([ $DRY_RUN -eq 1 ] && echo "(Dry run)")
**  Date: $(GetDateTime)
**  Env-file: ${ENV_FILE}
**************************************"

# Check if destination is mounted and folder exists
[ ! -d "$DESTINATION_ROOT" ] && Log "ERROR: Destination $DESTINATION_ROOT is not mounted or folder is missing." && FAILURE_COUNT=1

# Trying ssh connection
ssh -i "$SSH_ID_PATH" -p $SSH_PORT -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=no $SSH_LOGIN@$SSH_HOST exit
[ $? -ne 0 ] && Log "ERROR: Impossible to connect to distant serveur!" && FAILURE_COUNT=1

# Create folder structure and run rsync for each folder
RUNNING=True
[ $FAILURE_COUNT -eq 0 ] && for _PATH in "${DISTANT_FOLDERS[@]}"
do
   DESTINATION_PATH="${DESTINATION_ROOT}${_PATH}"
   LATEST_LINK="${DESTINATION_PATH}/latest"
   RSYNC_DEST_PATH="${DESTINATION_PATH}/$(GetDateTime)"
   mkdir -p "${RSYNC_DEST_PATH}"
   [ ! $? -eq 0 ] && Log "ERROR: Cannot create folder ${RSYNC_DEST_PATH}" && ((FAILURE_COUNT+=1))
   Log "\n***** $(GetDateTime): Running rsync for ${_PATH}..."
   if [ ! -d "${LATEST_LINK}" ] # Symbolic link to latest doesn't exist -> first run
   then
      Log "First run for folder ${_PATH}"
      LINK_DEST_OPTION=""
   else
      LINK_DEST_OPTION="--link-dest ${LATEST_LINK}"
   fi
   Log "Source: ${SSH_LOGIN}@${SSH_HOST}:${_PATH}/"
   Log "Destination: ${RSYNC_DEST_PATH}/"
   rsync ${RSYNC_OPTIONS[@]} ${LINK_DEST_OPTION} -e "ssh -i ${SSH_ID_PATH} -p ${SSH_PORT} -o StrictHostKeyChecking=no" ${SSH_LOGIN}@${SSH_HOST}:${_PATH}/ "${RSYNC_DEST_PATH}/"

   EXIT_CODE=$?
   Log "* rsync exited with status code $EXIT_CODE"
   if [ $EXIT_CODE -eq 0 ]
   then # rsync succeded
        ((SUCCESS_COUNT+=1))
        if [ $DRY_RUN -ne 1 ]
        then
            Log "* Deleteing old symbolic link to latest (if exists)"
            # Delete symbolic link latest
            rm -f "${LATEST_LINK}"
	    Log "* Creating new symbolic link to latest"
            # Create symbolic link to the recent created folder
            ln -s "${RSYNC_DEST_PATH}" "${LATEST_LINK}"
        fi
    else
        ((FAILURE_COUNT+=1))
        rm -rf "${RSYNC_DEST_PATH}"
    fi
    [ $DRY_RUN -eq 1 ] && rm -rf "$RSYNC_DEST_PATH" > /dev/null 2>&1

    # Delete old backups
    if [ $MAX_INCREMENT -gt 0 ]
    then
        Log "* Deleting old backups (keep last ${MAX_INCREMENT})"
        COUNT=0
        while read FOLDERNAME; do
            ((COUNT+=1))
            if [ $COUNT -gt $MAX_INCREMENT ]
            then
                [ ! $DRY_RUN -eq 1 ] && rm -rf "$FOLDERNAME"
                [ $? -eq 0 ] || [ $DRY_RUN -eq 1 ] && Log "Deleted folder: ${FOLDERNAME}" || Log "ERROR deleting ${FOLDERNAME}" && ((FAILURE_COUNT+=1))
            fi
        done < <(find "${DESTINATION_PATH}" -maxdepth 1 -type d -regex "${DESTINATION_PATH}/20[2-5][0-9]-[01][0-9]-[0-3][0-9]_[0-2][0-9]h[0-5][0-9]m[0-5][0-9]s" | sort -r)
    fi
    Log "***** $(GetDateTime): Completed rsync for ${_PATH}."
done
RUNNING=False

# Append log
[ $DRY_RUN -ne 1 ] && cat "$TMP_FILE" >> "$LOG_FILE"

SendEmail() { # Sends mail using declared constants. Requires one argument: The message file
    curl "$EMAIL_PROTOCOL://$EMAIL_HOST:$EMAIL_PORT" --mail-rcpt "$EMAIL_RECIPIENT" --upload-file "$1" --user "$EMAIL_USERNAME:$EMAIL_PASSWORD" $VERBOSE
    if [ $? -eq 0 ]
    then
        echo "Email sent to $EMAIL_RECIPIENT" | tee -a "$LOG_FILE"
    else
        echo "ERROR sending email" | tee -a "$LOG_FILE"
    fi
}

# Send email
if [ $SEND_REPORT == "A" ] || { [ $SEND_REPORT == "F" ] && [ $FAILURE_COUNT -gt 0 ]; }
then
    echo -e "\n# Sending report by email..." | tee -a "$LOG_FILE"
    [ $FAILURE_COUNT -gt 0 ] && SUBJECT="$FILENAME ($ENV_FILENAME) - FAILURE \($FAILURE_COUNT\)" || SUBJECT="$FILENAME ($ENV_FILENAME) - SUCCESS"
    sed -i "1iFrom: $EMAIL_USERNAME <$EMAIL_FROM>\nTo: $EMAIL_RECIPIENT\nSubject: $SUBJECT\n\n" "$TMP_FILE"
    SendEmail "$TMP_FILE"
fi

# Send alert for low disk space
if [ ! $ALERT_DISK_MOUNT_POINT == "" ]
then
    DISK_SPACE=$(df -B1 $ALERT_DISK_MOUNT_POINT | awk 'NR==2 {print $4}')
    if [ $DISK_SPACE -lt $ALERT_DISK_SPACE ]
    then
        echo -e  "From: $EMAIL_USERNAME <$EMAIL_FROM>\nTo: $EMAIL_RECIPIENT\nSubject: $FILENAME: Disk space alert\n\nYou are running out of disk space on $ALERT_DISK_MOUNT_POINT \(< $DISK_SPACE bytes\)" > "$TMP_FILE"
        SendEmail "$TMP_FILE"
    fi
fi

# Delete tmp file
rm -f "$TMP_FILE"
