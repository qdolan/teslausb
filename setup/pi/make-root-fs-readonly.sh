#!/bin/bash

# Adapted from https://github.com/adafruit/Raspberry-Pi-Installer-Scripts/blob/master/read-only-fs.sh

function log_progress () {
  if typeset -f setup_progress > /dev/null; then
    setup_progress "make-root-fs-readonly: $1"
  fi
  echo "make-root-fs-readonly: $1"
}

log_progress "start"

function append_cmdline_txt_param() {
  local toAppend="$1"
  sed -i "s/\'/ ${toAppend}/g" /boot/cmdline.txt >/dev/null
}

log_progress "Removing unwanted packages..."
apt-get remove -y --auto-remove --assume-yes --purge triggerhappy logrotate dphys-swapfile
# Replace log management with busybox (use logread if needed)
log_progress "Installing busybox-syslogd..."
apt-get -y --assume-yes install busybox-syslogd; dpkg --purge rsyslog

log_progress "Configuring system..."

# Add fastboot, noswap and/or ro to end of /boot/cmdline.txt
append_cmdline_txt_param fastboot
append_cmdline_txt_param noswap
append_cmdline_txt_param ro

if ! findmnt --mountpoint /mutable
then
    log_progress "Mounting the mutable partition..."
    mount /mutable
    log_progress "Mounted."
fi
if [ ! -e "/mutable/etc" ]
then
    mkdir -p /mutable/etc
fi

# Create a configs directory for others to use
if [ ! -e "/mutable/configs" ]
then
    mkdir -p /mutable/configs
fi

# Move /var/spool to /tmp
rm -rf /var/spool
ln -s /tmp /var/spool

# Change spool permissions in var.conf (rondie/Margaret fix)
sed -i "s/spool\s*0755/spool 1777/g" /usr/lib/tmpfiles.d/var.conf >/dev/null

# Update /etc/fstab
# make /boot read-only
# make / read-only
# tmpfs /var/log tmpfs nodev,nosuid 0 0
# tmpfs /var/tmp tmpfs nodev,nosuid 0 0
# tmpfs /tmp     tmpfs nodev,nosuid 0 0
if ! grep -P -q "/boot\s+vfat\s+.+?(?=,ro)" /etc/fstab
then
  sed -i -r "s@(/boot\s+vfat\s+\S+)@\1,ro@" /etc/fstab
fi

if ! grep -P -q "/\s+ext4\s+.+?(?=,ro)" /etc/fstab
then
  sed -i -r "s@(/\s+ext4\s+\S+)@\1,ro@" /etc/fstab
fi

if ! grep -w -q "/var/log" /etc/fstab
then
  echo "tmpfs /var/log tmpfs nodev,nosuid 0 0" >> /etc/fstab
fi

if ! grep -w -q "/var/tmp" /etc/fstab
then
  echo "tmpfs /var/tmp tmpfs nodev,nosuid 0 0" >> /etc/fstab
fi

if ! grep -w -q "/tmp" /etc/fstab
then
  echo "tmpfs /tmp    tmpfs nodev,nosuid 0 0" >> /etc/fstab
fi

log_progress "done"
