#!/bin/bash -ex

vlan_interfaces_lines=$(lava-vland-self)

interfaces=""

IFS=$'\n'

for line in $vlan_interfaces_lines
do
    interfaces+=$(echo $line | cut -d',' -f1)$','
done

IFS=','
for interface in $interfaces
do
    echo interface
done