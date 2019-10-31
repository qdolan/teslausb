#! /bin/bash -eu

typeset -f setup_progress || setup_progress() { echo "$*"; }

function log_progress () {
  setup_progress "configure-ap: $*"
}

if [ -z "${AP_SSID+x}" ]
then
  log_progress "AP_SSID not set"
  exit 1
fi

if [ -z "${AP_PASS+x}" ] || [ "$AP_PASS" = "password" ]
then
  log_progress "AP_PASS not set or not changed from default"
  exit 1
fi

if [ -e /etc/hostapd/hostapd-ap0.conf ]
then
  log_progress "AP mode already configured"
  exit 0
fi

IP=${AP_IP:-"192.168.66.1"}

# install required packages
log_progress "installing hostapd"
apt-get -y --assume-yes install hostapd

log_progress "configuring AP '$AP_SSID' with IP $IP"

cat <<EOF >/etc/udev/rules.d/70-ap-interface.rules
SUBSYSTEM=="net", KERNEL=="wlan*", ACTION=="add", RUN+="/sbin/iw dev %k interface add ap%n type __ap"
EOF

cat <<EOF >/etc/systemd/network/20-ap0.network
[Match]
Name=ap0

[Network]
Address=${IP}/28
DHCPServer=yes
EOF

udevadm trigger --action=add /sys/class/net/wlan0
cat <<EOF >/etc/systemd/system/hostapd@.service
[Unit]
Description=Advanced IEEE 802.11 AP and IEEE 802.1X/WPA/WPA2/EAP Authenticator
Requires=sys-subsystem-net-devices-%i.device
After=sys-subsystem-net-devices-%i.device
Before=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/hostapd /etc/hostapd/hostapd-%I.conf

[Install]
Alias=multi-user.target.wants/hostapd@%i.service
EOF

mkdir -p /etc/hostapd/
cat <<EOF >/etc/hostapd/hostapd-ap0.conf
interface=ap0
hw_mode=g

ssid=${AP_SSID}
channel=6
ignore_broadcast_ssid=0

auth_algs=1
wpa=2
wpa_passphrase=${AP_PASS}
wpa_key_mgmt=WPA-PSK

wmm_enabled=0
EOF

mkdir -p /etc/systemd/system/wpa_supplicant@wlan0.service.d
cat <<EOF >/etc/systemd/system/wpa_supplicant@wlan0.service.d/override.conf
[Unit]
Wants=hostapd@ap0.service
After=hostapd@ap0.service

[Service]
ExecStartPre=/bin/sleep 3
EOF

if [ ! -L /var/lib/misc ]
then
  if ! findmnt --mountpoint /mutable
  then
    mount /mutable
  fi
  mkdir -p /mutable/varlib
  mv /var/lib/misc /mutable/varlib
  ln -s /mutable/varlib/misc /var/lib/misc
fi

# update the host name to have the AP IP address, otherwise
# clients connected to the IP will get 127.0.0.1 when looking
# up the teslausb host name
sed -i -e "/^127.0.0.1\s*localhost/b; s/^127.0.0.1\(\s*.*\)/$IP\1/" /etc/hosts

systemctl daemon-reload
systemctl enable hostapd@ap0

