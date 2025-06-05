#!/bin/bash

# allow gpsd (execute in node-red instead)
#sudo gpsd /dev/ttyHS1 -F /var/run/gpsd.sock

# set ip forwarding
sudo echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# restore iptables
sudo iptables -t nat -A POSTROUTING -o wwan0 -j MASQUERADE
sudo iptables -A FORWARD -i wwan0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eth1 -o wwan0 -j ACCEPT
