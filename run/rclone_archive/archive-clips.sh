#!/bin/bash -eu

log "Moving clips to rclone archive..."

STORAGE_MOUNT=${STORAGE_MOUNT:-/backingfiles}
source /root/.teslaCamRcloneConfig

FILE_COUNT=$(cd "$STORAGE_MOUNT"/TeslaCam && find . -maxdepth 3 -path './SavedClips/*' -type f -o -path './SentryClips/*' -type f | wc -l)

if [ -d "$STORAGE_MOUNT"/TeslaCam/SavedClips ]
then
  rclone --config /root/.config/rclone/rclone.conf copy "$STORAGE_MOUNT"/TeslaCam/SavedClips "$drive:$path"/SavedClips/ --create-empty-src-dirs >> "$LOG_FILE" 2>&1 || echo ""
fi

if [ -d "$STORAGE_MOUNT"/TeslaCam/SentryClips ]
then
  rclone --config /root/.config/rclone/rclone.conf copy "$STORAGE_MOUNT"/TeslaCam/SentryClips "$drive:$path"/SentryClips/ --create-empty-src-dirs >> "$LOG_FILE" 2>&1 || echo ""
fi

#FILES_REMAINING=$(cd "$STORAGE_MOUNT"/TeslaCam && find . -maxdepth 3 -path './SavedClips/*' -type f -o -path './SentryClips/*' -type f | wc -l)
NUM_FILES=$FILE_COUNT

log "Synced $NUM_FILES file(s)."
/root/bin/send-push-message "TeslaUSB:" "Synced $NUM_FILES dashcam file(s)."

log "Finished syncing clips to rclone archive"
