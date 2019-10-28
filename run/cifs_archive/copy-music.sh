#!/bin/bash -eu

log "Syncing music from archive..."

ARCHIVE_MOUNT=${STORAGE_MOUNT:-/mnt/musicarchive}
MUSIC_MOUNT=${ARCHIVE_MOUNT:-/mnt/music}

num_files=$(rsync -rtvhL --timeout=60 --no-perms --stats --log-file=/tmp/music-rsync-cmd.log "$ARCHIVE_MOUNT"/ "$MUSIC_MOUNT" | awk '/files transferred/{print $NF}')

if (( num_files > 0 ))
then
  log "Successfully synced $num_files files through rsync."
  /root/bin/send-push-message "TeslaUSB:" "Synced $num_files music file(s)."
else
  log "No files synced."
fi
