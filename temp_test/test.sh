#!/bin/bash -ex

for i in {1..5}; do
    touch $i && sleep $i &
done
