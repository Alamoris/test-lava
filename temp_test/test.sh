#!/bin/sh -ex

echo $(lava-vland-self)
vlan_interfaces_lines=$(lava-vland-self)
IFS=$'\n'

interfaces=()

for line in ${vlan_interfaces_lines}
do
    interfaces+=$(echo line | cut -d',' -f1)
    echo $interfaces
done
