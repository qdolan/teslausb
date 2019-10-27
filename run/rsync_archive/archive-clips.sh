#!/bin/bash -eu

log "Archiving through rsync..."

STORAGE_MOUNT=${STORAGE_MOUNT:-/backingfiles}
source /root/.teslaCamRsyncConfig

num_files=$(rsync -rtvhL --timeout=60 --no-perms --stats --log-file=/tmp/archive-rsync-cmd.log "$STORAGE_MOUNT"/TeslaCam/SentryClips/* "$STORAGE_MOUNT"/TeslaCam/SavedClips/* $user@$server:$path | awk '/files transferred/{print $NF}')

if (( num_files > 0 ))
then
  log "Successfully synced $num_files files through rsync."
  /root/bin/send-push-message "TeslaUSB:" "Synced $num_files dashcam file(s)."
else
  log "No files archived."
fi
