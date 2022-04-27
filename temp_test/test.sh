#!/bin/bash -ex

vlan_interfaces_lines=$(lava-vland-self)

echo $vlan_interfaces_lines

interfaces=()

IFS=$'\n'

for line in $vlan_interfaces_lines
do
    interfaces+=$(echo $line | cut -d',' -f1)
    echo $interfaces
done


