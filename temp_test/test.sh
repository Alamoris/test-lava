#!/bin/bash -ex

vlan_interfaces_lines=$(lava-vland-self)

interfaces=""

IFS=$'\n'
for line in $vlan_interfaces_lines
do
    interfaces+=$(echo $line | cut -d',' -f1)$','
done
IFS=''

static_network_header="network:
  version: 2
  renderer: networkd
  ethernets:"

echo $static_network_header > /etc/netplan/01-netcfg.yaml


adress_id=50
IFS=','


for interface in $interfaces
do
    static_interface="    ${interface}:
      dhcp4: no
      addresses: [192.168.1.${adress_id}/24]"
    echo $static_interface >> /etc/netplan/01-netcfg.yaml
    adress_id=$((adress_id+1))
done

netplan apply
ifconfig
