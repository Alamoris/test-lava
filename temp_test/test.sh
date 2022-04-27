#!/bin/bash -ex

vlan_interfaces_lines=$(lava-vland-self)

interfaces=""

IFS=$'\n'
for line in $vlan_interfaces_lines
do
    interfaces+=$(echo $line | cut -d',' -f1)$','
done
IFS=''

static_network_header="
network:\n
  version: 2\n
  renderer: networkd\n
  ethernets:"

echo $static_network_header > /etc/netplan/01-netcfg.yaml


#ip addr flush dev ${interface}
#ip addr add 192.168.0.${adress_id}/255.255.255.0 dev ${interface}
#ip route replace default via 192.168.0.1


adress_id=50
IFS=','


for interface in $interfaces
do
    static_interface="
    ${interface}:
      dhcp4: no
      addresses: [192.168.1.${adress_id}/24]
      gateway4: 192.168.1.1"
    echo $static_interface >> /etc/netplan/01-netcfg.yaml
    adress_id=$((adress_id+1))
done

netplan apply
ifconfig

#static_interface="
#${interface}:
#    dhcp4: no
#    addresses: [192.168.1.${adress_id}/24]
#    gateway4: 192.168.1.1
#"
#echo $static_interface >> /etc/netplan/01-netcfg.yaml
