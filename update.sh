#!/bin/bash

YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
  echo -e "${GREEN}> $*${NC}"
}

error() {
  echo -e "${RED}> $*${NC}"
}

warning() {
  echo -e "${YELLOW}> $*${NC}"
}

# ======================================================
# allow no password sudo if not exist
log "allow admin sudo without password"
if ! sudo grep -Fxq "admin ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then
  echo "admin ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers >/dev/null
fi

# -------------------------------------------------
log "set timezone to Asia/Bangkok"
sudo timedatectl set-timezone Asia/Bangkok

# -------------------------------------------------
log "set static eth0 ip to 10.10.10.50"
sudo nmcli con mod "Wired connection 1" ipv4.addresses 10.10.10.50/24
sudo nmcli con mod "Wired connection 1" ipv4.method manual

# -------------------------------------------------
# enable wan
sudo nmcli c add con-name sim type gsm ifname cdc-wdm0 apn internet
# turn it on
sudo nmcli r wwan on

# -------------------------------------------------
while ! ping -q -c 1 -W 1 8.8.8.8 >/dev/null; do
  warning "Waiting for internet connection"
  sleep 5
done

log "INTERNET CONNECTION IS UP"

# -------------------------------------------------
log "apt update"
sudo apt-get update

log "apt upgrade"
sudo apt-get upgrade -y

log "dist upgrade"
sudo apt-get dist-upgrade -y

log "autoremove"
sudo apt-get autoremove -y

# -------------------------------------------------
# log "install screen"
# sudo apt install screen

# -------------------------------------------------
log "install update-manager-core"
sudo apt install update-manager-core

# -------------------------------------------------
log "Upgrade to 20.04 LTS"
sudo do-release-upgrade

# -------------------------------------------------
warning "Required to reboot before upgrade to Ubuntu 20.04 LTS"
while true; do
  read -r -p 'Reboot now? [y/n] (y) : ' SHOULDREBOOT
  SHOULDREBOOT=${SHOULDREBOOT:-y}
  if [ "${SHOULDREBOOT}" == "y" ]; then
    echo "reboot now"
    sleep 2
    # warning "After reboot, please run \"screen\" to use screen mode"
    warning "After reboot run \"sudo do-release-upgrade\" to upgrade to 20.04 LTS"
    sudo reboot
    break
  elif [ "${SHOULDREBOOT}" == "n" ]; then
    break
  else
    echo "Please enter y or n"
  fi
done