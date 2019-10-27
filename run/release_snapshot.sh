#!/bin/sh

STORAGE_MOUNT=${STORAGE_MOUNT:-/backingfiles}

# for some reason "umount -d" doesn't remove the loop device, so we have to remove it ourselves
MNT=$(echo "$1" | sed 's/\/$//')
LOOP=$(mount | grep -w "$MNT" | awk '{print $1}' | sed 's/p1$//')
SNAP=$(losetup -l --noheadings $LOOP | awk '{print $6}')
umount $MNT
losetup -d $LOOP
# delete all dead links
find "${STORAGE_MOUNT}"/TeslaCam/ -xtype l -exec 'rm -f' '{}' \;
# delete all Sentry folders that are now empty
rmdir --ignore-fail-on-non-empty "${STORAGE_MOUNT}"/TeslaCam/*/* || true
