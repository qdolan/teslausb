#! /bin/bash -eu

function log_progress () {
  if typeset -f setup_progress > /dev/null; then
    setup_progress "configure-systemd: $1"
  fi
  echo "configure-systemd: $1"
}

if [ ! -e /etc/systemd/network/10-usb0.network ]
then
  log_progress "configuring usb0"
  cat <<EOF >/etc/systemd/network/10-usb0.network
[Match]
Name=usb0

[Network]
LinkLocalAddressing=ipv4
EOF
fi

if [ ! -e /etc/systemd/network/10-wlan0.network ]
then
    log_progress "configuring wlan0"
    cat <<EOF >/etc/systemd/network/10-wlan0.network
[Match]
Name=wlan0

[Network]
DHCP=ipv4
EOF
fi

if [ ! -e /etc/wpa_supplicant/wpa_supplicant-wlan0.conf ]
then
    cat <<EOF >/etc/wpa_supplicant/wpa_supplicant-wlan0.conf
ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
update_config=0
country=AU

network={
    ssid="$SSID"
    psk="$WIFIPASS"
    key_mgmt=WPA-PSK
    priority=10
}
EOF
    chmod 600 /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
fi

if [ ! -e /etc/systemd/network/10-eth0.network ]
then
    log_progress "configuring eth0"
    cat <<EOF >/etc/systemd/network/10-eth0.network
[Match]
Name=eth0

[Network]
DHCP=ipv4
EOF
fi

if [ ! -L /var/lib/systemd ]
then
  if ! findmnt --mountpoint /mutable
  then
    mount /mutable
  fi
  mkdir -p /mutable/varlib
  mv /var/lib/systemd /mutable/varlib
  ln -s /mutable/varlib/systemd /var/lib/systemd
fi

log_progress "removing packages"
apt -y remove --purge --auto-remove ntp dhcpcd5 fake-hwclock ifupdown isc-dhcp-client isc-dhcp-common openresolv

killall dhcpcd || true
#killall wpa_supplicant || true

systemctl daemon-reload
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

if systemctl is-active otg_mass_storage | grep -q inactive
then
    log_progress "adding OTG Mass Storage service"
    cat <<EOF > /etc/systemd/system/otg_mass_storage.service
[Unit]
Description=Starts kernel modules for USB OTG
DefaultDependencies=false
After=local-fs.service backingfiles.mount

[Service]
Type=simple
ExecStart=/opt/otgmassstorage/start.sh
WorkingDirectory=/opt/otgmassstorage/

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p /opt/otgmassstorage/
    cat <<EOF > /opt/otgmassstorage/start.sh
#! /bin/sh -e
modprobe g_mass_storage
EOF
    chmod +x /opt/otgmassstorage/start.sh
    systemctl enable otg_mass_storage
fi
if systemctl is-active fstrim.timer | grep -q inactive
then
    log_progress "enabling fstrim.timer service"
    cat <<EOF > /etc/systemd/system/fstrim.timer
[Unit]
Description=Discard unused blocks once on bootup
Documentation=man:fstrim

[Timer]
OnBootSec=50
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl enable fstrim.timer
fi

if ! systemctl is-active bluetooth | grep -q inactive
then
    log_progress "disabling bluetooth"
    systemctl disable bluetooth
    systemctl stop bluetooth
fi
if systemctl is-active systemd-networkd | grep -q inactive
then
    log_progress "enabling systemd-networkd"
    systemctl enable systemd-networkd
    systemctl restart systemd-networkd
fi
if systemctl is-active systemd-resolved | grep -q inactive
then
    log_progress "enabling systemd-resolved"
    systemctl enable systemd-resolved
    systemctl restart systemd-resolved
fi
if systemctl is-active systemd-timesyncd | grep -q inactive
then
    log_progress "enabling systemd-timesyncd"
    systemctl enable systemd-timesyncd
    systemctl restart systemd-timesyncd
fi
if systemctl is-active wpa_supplicant@wlan0 | grep -q inactive
then
    log_progress "enabling wpa_supplicant@wlan0"
    systemctl enable wpa_supplicant@wlan0
    systemctl restart wpa_supplicant@wlan0
fi
#systemctl enable ssh.socket
