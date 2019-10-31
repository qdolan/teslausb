#! /bin/bash -eu

log "syncing clips to archive..."

STORAGE_MOUNT=${STORAGE_MOUNT:-/backingfiles}
ARCHIVE_MOUNT=${ARCHIVE_MOUNT:-/mnt/archive}

num_files=$(rsync -rtvhL --timeout=60 --no-perms --stats "$STORAGE_MOUNT"/TeslaCam/SentryClips "$STORAGE_MOUNT"/TeslaCam/SavedClips "$ARCHIVE_MOUNT"/ | awk '/files transferred/{print $NF}')

if (( num_files > 0 ))
then
  log "Successfully synced $num_files files through rsync."
  /root/bin/send-push-message "TeslaUSB:" "Synced $num_files dashcam file(s)."
else
  log "No files archived."
fi
