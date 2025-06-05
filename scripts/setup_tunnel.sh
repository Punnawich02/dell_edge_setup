#!/bin/bash

BASEDIR="$(dirname $0)/.."

. ${BASEDIR}/setup.conf
while true; do
  read -r -p 'Enter BUS number : ' BUS_NUMBER
  if [ BUS_NUMBER != '' ]; then
    break
  fi
done

# install autossh
if ! (command -v autossh &>/dev/null); then
  echo "> install autossh"
  sudo apt-get install -y autossh
else
  echo "> autossh exist"
fi

echo Use bus number ${BUS_NUMBER}

SSH_TUNNEL_PORT=$((SSH_TUNNEL_BASE_PORT + BUS_NUMBER))
echo Create tunnel as port ${SSH_TUNNEL_PORT}

# replace configuration
# ref https://www.everythingcli.org/ssh-tunnelling-for-fun-and-profit-autossh/
# ref https://blog.itum.me/ssh-tunnel/
echo create ssh config connection
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
echo "> add knownhost"
ssh-keyscan ${SSH_TUNNEL_SERVER} > ~/.ssh/known_hosts

#copy service
echo create service
sudo systemctl stop autossh-ssh-tunnel.service
sudo cp ${BASEDIR}/config/autossh-ssh-tunnel.service /etc/systemd/system/
sudo chmod 664 /etc/systemd/system/autossh-ssh-tunnel.service
sudo systemctl enable autossh-ssh-tunnel.service
sudo systemctl start autossh-ssh-tunnel.service
