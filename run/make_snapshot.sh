#!/bin/bash -eu

if [ "$BASH_SOURCE" != "$0" ]
then
  echo "$BASH_SOURCE must be executed, not sourced"
  return 1 # shouldn't use exit when sourced
fi

typeset -f log > /dev/null || log() { echo "make_snapshot: $1"; }

STORAGE_MOUNT=${STORAGE_MOUNT:-/backingfiles}

if [ "${FLOCKED:-}" != "$0" ]
then
  mkdir -p "${STORAGE_MOUNT}"/snapshots
  if FLOCKED="$0" flock -E 99 "${STORAGE_MOUNT}"/snapshots "$0" "$@" || case "$?" in
  99) echo "failed to lock snapshots dir"
      exit 99
      ;;
  *)  exit $?
      ;;
  esac
  then
    # success
    exit 0
  fi
fi

function linksnapshotfiletorecents() {
  local file=$1
  local recents="${STORAGE_MOUNT}"/TeslaCam/RecentClips

  filename=$(basename "$file")
  filedate=$(echo "$filename" | cut -c -10)
  if [ ! -d "$recents/$filedate" ]
  then
    mkdir -p "$recents/$filedate"
  fi
  ln -sf "$file" "$recents/$filedate"
}

function linkrecentfiles() {
  for f
  do
    linksnapshotfiletorecents "$f"
  done
}

function linksnapshotfiles() {
  local path=$1;
  shift;
  for f
  do
    linksnapshotfiletorecents "$f"
    # also link it into a SavedClips folder
    local eventtime=$(basename "$(dirname "$f")")
    if [ ! -d "$path/$eventtime" ]
    then
      mkdir -p "$path/$eventtime"
    fi
    ln -sf "$f" "$path/$eventtime"
  done
}

function delete_dead_links() {
  # delete all dead links
  find "${STORAGE_MOUNT}"/TeslaCam/ -xtype l -exec 'rm' '-f' '{}' \;
  # delete all Sentry folders that are now empty
  rmdir --ignore-fail-on-non-empty "${STORAGE_MOUNT}"/TeslaCam/*/* || true
}

function make_links_for_snapshot() {
  local saved="${STORAGE_MOUNT}"/TeslaCam/SavedClips
  local sentry="${STORAGE_MOUNT}"/TeslaCam/SentryClips
  mkdir -p "$saved"
  mkdir -p "$sentry"
  local mnt="$1"
  log "making links for $mnt"
  if stat "$mnt"/TeslaCam/RecentClips/* > /dev/null 2>&1
  then
    log " - linking recent clips"
    linkrecentfiles "$mnt"/TeslaCam/RecentClips/*
  fi
  # also link in any files that were moved to SavedClips
  if stat "$mnt"/TeslaCam/SavedClips/*/* > /dev/null 2>&1
  then
    log " - linking saved clips"
    linksnapshotfiles "$saved" "$mnt"/TeslaCam/SavedClips/*/*
  fi
  # and the same for SentryClips
  if stat "$mnt"/TeslaCam/SentryClips/*/* > /dev/null 2>&1
  then
    log " - linking sentry clips"
    linksnapshotfiles "$sentry" "$mnt"/TeslaCam/SentryClips/*/*
  fi
  log "made all links for $mnt"
}

function check_freespace() {
  # Only take a snapshot when there is a free space buffer of at least 2GB.
  # Delete older snapshots if necessary to achieve that
  # space requirement, to delete old snapshots just before running out
  # of space and thus make better use of space
  while true
  do
    local freespace=$(($(stat --file-system --format='%f*%S' "${STORAGE_MOUNT}"/cam_disk.bin)))
    local reserved=$(($(stat -c "%s-(%b*%B)" "${STORAGE_MOUNT}"/cam_disk.bin)))
    local buffer=$(((2048 * 1024 * 1024)))
    
    if (( freespace > (reserved + buffer) ))
    then
      break
    fi
    if ! stat "${STORAGE_MOUNT}"/snapshots/snap-*/snap.bin > /dev/null 2>&1
    then
      log "warning: low space for snapshots"
      break
    fi
    oldest=$(ls -ldC1 "${STORAGE_MOUNT}"/snapshots/snap-* | head -1)
    log "low space, deleting $oldest"
    /root/bin/release_snapshot.sh "$oldest/mnt"
    rm -rf "$oldest"
  done
  delete_dead_links
}

function snapshot() {
  check_freespace

  local oldnum=-1
  local newnum=0
  if stat "${STORAGE_MOUNT}"/snapshots/snap-*/snap.bin > /dev/null 2>&1
  then
    oldnum=$(ls -lC1 "${STORAGE_MOUNT}"/snapshots/snap-*/snap.bin | tail -1 | tr -c -d '[:digit:]' | sed 's/^0*//' )
    newnum=$((oldnum + 1))
  fi
  local oldname="${STORAGE_MOUNT}"/snapshots/snap-$(printf "%06d" $oldnum)/snap.bin
  local newsnapdir="${STORAGE_MOUNT}"/snapshots/snap-$(printf "%06d" $newnum)
  local newname=$newsnapdir/snap.bin
  local tmpsnapdir="${STORAGE_MOUNT}"/snapshots/newsnap
  local tmpsnapname=$tmpsnapdir/snap.bin
  local tmpsnapmnt=$tmpsnapdir/mnt
  log "taking snapshot of cam disk: $newname"
  rm -rf "$tmpsnapdir"
  /root/bin/mount_snapshot.sh "${STORAGE_MOUNT}"/cam_disk.bin "$tmpsnapname" "$tmpsnapmnt"
  fstrim "$tmpsnapmnt"
  log "took snapshot"

  # check whether this snapshot is actually different from the previous one
  find "$tmpsnapmnt/TeslaCam" -type f -printf '%s %P\n' > "$tmpsnapname.toc"
  log "comparing $oldname.toc and $tmpsnapname.toc"
  if [[ ! -e "$oldname.toc" ]] || diff "$oldname.toc" "$tmpsnapname.toc" | grep -e '^>'
  then
    mv "$tmpsnapdir" "$newsnapdir"
    make_links_for_snapshot "$newsnapdir/mnt"
  else
    log "new snapshot is identical to previous one, discarding"
    /root/bin/release_snapshot.sh "$tmpsnapmnt"
    rm -rf "$tmpsnapdir"
  fi
}

function relink_snapshots() {
  local links_file=/tmp/.snapshots_links.$$
  ls -1lR "$STORAGE_MOUNT"/TeslaCam/ > "$links_file"
  for mnt in "$STORAGE_MOUNT"/snapshots/snap-*/mnt
  do
  if ! grep -q "$mnt" "$links_file"
  then
    make_links_for_snapshot "$mnt"
  fi
  done
  rm "$links_file"
}

if ! snapshot
then
  log "failed to take snapshot"
fi

# WARNING: This could take a long time with lots of snapshots
if [ -e /tmp/relink_snapshots ]
then
  rm /tmp/relink_snapshots
  relink_snapshots
fi