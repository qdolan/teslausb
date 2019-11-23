#! /bin/bash -eu

function setup_progress () {
  local setup_logfile=/boot/teslausb-headless-setup.log
  local headless_setup=${HEADLESS_SETUP:-false}
  if [ $headless_setup = "true" ]
  then
    echo "$( date ) : $1" >> "$setup_logfile"
  fi
  echo $1
}

# install XFS tools if needed
if ! hash mkfs.xfs 2>/dev/null
then
  apt-get -y --assume-yes install xfsprogs
fi

# Will check for USB Drive before running sd card
if [ ! -z "$usb_drive" ]
then
  setup_progress "usb_drive is set to $usb_drive"
  # Check if backingfiles and mutable partitions exist
  if [ /dev/disk/by-label/storage -ef /dev/sda1 ]
  then
    setup_progress "Looks like storage artition already exists. Skipping partition creation."
  else
    setup_progress "WARNING !!! This will delete EVERYTHING in $usb_drive."
    wipefs -afq $usb_drive
    parted $usb_drive --script mktable gpt
    setup_progress "$usb_drive fully erased. Creating partitions..."
    parted -a optimal -m /dev/sda mkpart primary xfs '0%' '100%'
    setup_progress "Storage partition created."

    setup_progress "Formatting partition..."
    # Force creation of filesystems even if previous filesystem appears to exist
    mkfs.xfs -f -m reflink=1 -L storage /dev/sda1
  fi
    
  STORAGE_MOUNTPOINT="$1"
  if grep -q "LABEL=storage" /etc/fstab
  then
    setup_progress "storage already defined in /etc/fstab. Not modifying /etc/fstab."
  else
    echo "LABEL=storage $STORAGE_MOUNTPOINT xfs auto,rw,noatime 0 2" >> /etc/fstab
  fi
  setup_progress "Done."
  exit 0
else
  echo "usb_drive not set. Proceeding to SD card setup"
fi

# If partition 3 is the backingfiles partition, type xfs, and
# partition 4 the mutable partition, type ext4, then return early.
if [ /dev/disk/by-label/storage -ef /dev/mmcblk0p3 ]
then
  # assume these were either created previously by the setup scripts,
  # or manually by the user, and that they're big enough
  setup_progress "using existing partitions"
  return &> /dev/null || exit 0
fi

# partition 3 and 4 either don't exist, or are the wrong type
if [ -e /dev/mmcblk0p3 ]
then
  setup_progress "STOP: partition(s) already exist, but are not as expected"
  setup_progress "please delete them and re-run setup"
  exit 1
fi

STORAGE_MOUNTPOINT="$1"

setup_progress "Checking existing partitions..."

DISK_SECTORS=$(blockdev --getsz /dev/mmcblk0)
LAST_DISK_SECTOR=$(($DISK_SECTORS-1))
# storage partition sits after the root
LAST_ROOT_SECTOR=$(sfdisk -l /dev/mmcblk0 | grep mmcblk0p2 | awk '{print $3}')
FIRST_STORAGE_SECTOR=$((LAST_ROOT_SECTOR+1))
STORAGE_NUM_SECTORS=$((LAST_DISK_SECTOR-FIRST_STORAGE_SECTOR))

ORIGINAL_DISK_IDENTIFIER=$( fdisk -l /dev/mmcblk0 | grep -e "^Disk identifier" | sed "s/Disk identifier: 0x//" )

setup_progress "Modifying partition table for storage partition..."
echo "$FIRST_STORAGE_SECTOR,$STORAGE_NUM_SECTORS" | sfdisk --force /dev/mmcblk0 -N 3

# manually adding the partitions to the kernel's view of things is sometimes needed
if [ ! -e /dev/mmcblk0p3 ]
then
  partx --add --nr 3 /dev/mmcblk0
fi
if [ ! -e /dev/mmcblk0p3 ]
then
  setup_progress "failed to add partition"
  exit 1
fi

NEW_DISK_IDENTIFIER=$( fdisk -l /dev/mmcblk0 | grep -e "^Disk identifier" | sed "s/Disk identifier: 0x//" )

setup_progress "Writing updated partitions to fstab and /boot/cmdline.txt"
sed -i "s/${ORIGINAL_DISK_IDENTIFIER}/${NEW_DISK_IDENTIFIER}/g" /etc/fstab
sed -i "s/${ORIGINAL_DISK_IDENTIFIER}/${NEW_DISK_IDENTIFIER}/" /boot/cmdline.txt

setup_progress "Formatting new partition..."
# Force creation of filesystems even if previous filesystem appears to exist
mkfs.xfs -f -m reflink=1 -L storage /dev/mmcblk0p3

echo "LABEL=storage $STORAGE_MOUNTPOINT xfs auto,rw,noatime 0 2" >> /etc/fstab
