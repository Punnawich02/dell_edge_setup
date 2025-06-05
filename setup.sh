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

if ! [ $(whoami) == "admin" ]; then
  error "Please run setup script as 'admin'"
  exit
fi

# this directory
BASEDIR=$(dirname $0)
CURRENT_DIR=$(pwd)

# load configuration
. ${BASEDIR}/setup.conf

# ======================================================
echo "test root access"
sudo ls >/dev/null
if ! [ $? -eq 0 ]; then
  log "Could access root"
#  exit;
fi

# ======================================================
echo "ask for bus number"
NUMBER_REGEX='^[0-9]+$'
while true; do
  read -r -p 'Enter BUS number : ' BUS_NUMBER
  if [ "$BUS_NUMBER" != '' ]; then
    if [[ "$BUS_NUMBER" =~ $NUMBER_REGEX ]]; then
      break
    else
      log "Not a number"
    fi
  fi
done

# ======================================================
# allow no password sudo if not exist
log "allow admin sudo without password"
if ! sudo grep -Fxq "admin ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then
  echo "admin ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers >/dev/null
fi

# ======================================================
# add ssh authorized key
log "add ssh key for login"
mkdir -p ~/.ssh
cat ${BASEDIR}/config/ssh_publickey >>~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

# disallow password login
log "disallow password login"
if ! sudo grep -Fxq "PasswordAuthentication no" /etc/ssh/sshd_config; then
  echo "PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config >/dev/null
fi

# =======================================================
# ========== SHOULD BE ABLE TO CONNECT TO INTERNET ======
# =======================================================

# loop check internet connection

while ! ping -q -c 1 -W 1 8.8.8.8 >/dev/null; do
  warning "Waiting for internet connection"
  sleep 5
done

log "INTERNET CONNECTION IS UP"

# =======================================================
log "update apt package"
sudo sudo apt-get update

# ======================================================
log "set LAN0 static ip 192.168.2.1/24"
sudo nmcli con mod "Wired connection 2" ipv4.addresses 192.168.2.1/24
sudo nmcli con mod "Wired connection 2" ipv4.method manual

log "install dhcp server"
sudo apt-get install -y isc-dhcp-server
sudo sudo cp -f ${BASEDIR}/config/isc-dhcp-server.conf /etc/dhcp/dhcpd.conf

# ======================================================
# install and config gpsd

if ! (command -v gpsd &>/dev/null); then
  log "install gpsd"
  sudo apt-get install -y gpsd
  sudo systemctl disable gpsd.socket
else
  warning "gpsd is already install"
fi

# ======================================================

if ! (command -v node-red &>/dev/null); then
  # install node-red
  log "install node-red"
  if (command -v lsb_release &>/dev/null); then

    ## INSTALL USING SCRIPT
    log "install node red via node-red ubuntu install script"
    wget https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered
    chmod +x update-nodejs-and-nodered
    ./update-nodejs-and-nodered --confirm-install --skip-pi
    rm update-nodejs-and-nodered
    sudo systemctl enable nodered
    sudo systemctl start nodered
    log "set node-red home to ~/.node-red"
    NODE_RED_HOME="${HOME}/.node-red"
  else
    snap install node-red
    snap enable node-red
    snap start node-red
    NODE_RED_HOME="/root/snap/node-red/current"
  fi
else
  warning "node-red is installed"
fi

if ! (command -v node-red &>/dev/null); then
  error "node-red install failed. please check error then try again"
  exit
fi

# ======================================================
# install node-red package
log "install node-red dependencies"
cp -f ${BASEDIR}/config/node-red-package.json ${NODE_RED_HOME}/package.json
cd ${NODE_RED_HOME} && npm install
cd ${CURRENT_DIR}

# ======================================================
# copy node-red setting
log "copy node-red setting"
cp -f ${BASEDIR}/config/node-red-setting.js ${NODE_RED_HOME}/settings.js

# ======================================================
# copy node-red flow
log "copy node-red flow"
cp -f ${BASEDIR}/config/node-red-flows.json ${NODE_RED_HOME}/flows.json

# ======================================================
# copy node-red base setting
log "create node-red config from setup.conf"
mkdir -p ${NODE_RED_HOME}/context/settings/global/
echo "{\"base_setting\": { \"base_url\": \"${TRANSIT_API_BASE_URL}/\", \"token\": \"${TRANSIT_API_TOKEN}\"}}" >${NODE_RED_HOME}/context/settings/global/global.json

# ======================================================
log "restart node-red"
#pm2 restart node-red
sudo systemctl restart nodered

# ======================================================
# add startup script
log "add startup script to start gpsd data and restore iptables configuration"
sudo cp ${BASEDIR}/config/transit-bus.service /etc/systemd/system/
sudo cp ${BASEDIR}/config/transit_bus_startup.sh /usr/local/bin/
sudo chmod 664 /etc/systemd/system/transit-bus.service
sudo chmod 744 /usr/local/bin/transit_bus_startup.sh
sudo systemctl daemon-reload
sudo systemctl enable transit-bus

# ======================================================
log "setup ssh tunnel with bus + ${SSH_TUNNEL_BASE_PORT} as reverse port"

log Use bus number ${BUS_NUMBER}

SSH_TUNNEL_PORT=$((SSH_TUNNEL_BASE_PORT + BUS_NUMBER))
log Create tunnel as port ${SSH_TUNNEL_PORT}

# replace configuration
# ref https://www.everythingcli.org/ssh-tunnelling-for-fun-and-profit-autossh/
# ref https://blog.itum.me/ssh-tunnel/
log install autossh
sudo apt-get install autossh

log create ssh config connection
mkdir -p ~/.ssh
sudo chmod 700 ~/.ssh
cp ${BASEDIR}/config/autossh-ssh-priv-key ~/.ssh/
chmod 600 ~/.ssh/autossh-ssh-priv-key
# replace port and host value
cp ${BASEDIR}/config/autossh-ssh-config ~/.ssh/config
sed -i "s/:HOST/${SSH_TUNNEL_SERVER}/g" ~/.ssh/config
sed -i "s/:USER/${SSH_TUNNEL_USER}/g" ~/.ssh/config
sed -i "s/:PORT/${SSH_TUNNEL_PORT}/g" ~/.ssh/config

# add known host
log "> add tunnel server known_hosts"
ssh-keyscan ${SSH_TUNNEL_SERVER} >~/.ssh/known_hosts

#copy service
log create service
sudo systemctl stop autossh-ssh-tunnel.service
sudo cp ${BASEDIR}/config/autossh-ssh-tunnel.service /etc/systemd/system/
sudo chmod 664 /etc/systemd/system/autossh-ssh-tunnel.service
sudo systemctl daemon-reload
sudo systemctl enable autossh-ssh-tunnel.service
sudo systemctl start autossh-ssh-tunnel.service

# ======================================================
# ask for reboot

while true; do
  read -r -p 'Reboot now [y/n] (y) : ' SHOULDREBOOT
  SHOULDREBOOT=${SHOULDREBOOT:-y}
  if [ "${SHOULDREBOOT}" == "y" ]; then
    echo "reboot now"
    sleep 2
    sudo reboot
    break
  elif [ "${SHOULDREBOOT}" == "n" ]; then
    break
  else
    echo "Please enter y or n"
  fi
done
