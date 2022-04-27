#!/bin/sh -ex

vlan_interfaces_lines=$(lava-vland-self)

interfaces=""

# IFS=$'\n'
for line in ${vlan_interfaces_lines//'\n'/}
do
    interfaces="${interfaces} $(echo $line | cut -d',' -f1)"
done

echo $interfaces