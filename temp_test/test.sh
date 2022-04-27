#!/bin/sh -ex

vlan_interfaces_lines=$(lava-vland-self)

echo $(vlan_interfaces_lines)
echo $(vlan_interfaces_lines) | while read -r a; do echo $a; done


interfaces=()

for line in ${vlan_interfaces_lines}
do
    interfaces+=$(echo line | cut -d',' -f1)
    echo $interfaces
done
