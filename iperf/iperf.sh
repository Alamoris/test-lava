#!/bin/bash -ex

# shellcheck disable=SC1091
. ../utils/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/iperf.txt"
# If SERVER is blank, we are the server, otherwise
# If we are the client, we set SERVER to the ipaddr of the server
SERVER=""
# Time in seconds to transmit for
TIME="10"
# Number of parallel client streams to run
THREADS="1"
# Specify iperf3 version for CentOS.
VERSION="3.1.4"
# By default, the client sends to the server,
# Setting REVERSE="-R" means the server sends to the client
REVERSE=""
# CPU affinity is blank by default, meaning no affinity.
# CPU numbers are zero based, eg AFFINITY="-A 0" for the first CPU
AFFINITY=""
ETH="eth0"

usage() {
    echo "Usage: $0 [-c server] [-e server ethernet device] [-t time] [-p number] [-v version] [-A cpu affinity] [-R] [-s true|false]" 1>&2
    exit 1
}

while getopts "A:c:e:t:p:v:s:Rh" o; do
  case "$o" in
    A) AFFINITY="-A ${OPTARG}" ;;
    c) SERVER="${OPTARG}" ;;
    e) ETH="${OPTARG}" ;;
    t) TIME="${OPTARG}" ;;
    p) THREADS="${OPTARG}" ;;
    R) REVERSE="-R" ;;
    v) VERSION="${OPTARG}" ;;
    s) SKIP_INSTALL="${OPTARG}" ;;
    h|*) usage ;;
  esac
done

create_out_dir "${OUTPUT}"
cd "${OUTPUT}"

if [ "${SKIP_INSTALL}" = "true" ] || [ "${SKIP_INSTALL}" = "True" ]; then
    info_msg "iperf installation skipped"
else
    dist_name
    # shellcheck disable=SC2154
    case "${dist}" in
        debian|ubuntu|fedora)
            install_deps "iperf3"
            ;;
        centos)
            install_deps "wget gcc make"
            wget https://github.com/esnet/iperf/archive/"${VERSION}".tar.gz
            tar xf "${VERSION}".tar.gz
            cd iperf-"${VERSION}"
            ./configure
            make
            make install
            ;;
    esac
fi

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


# Run local iperf3 server as a daemon when testing localhost.
if [ "${SERVER}" = "" ]; then
    server_ip=50

    IFS=','
    for interface in $interfaces
    do
        static_interface="    ${interface}:
        dhcp4: no
        addresses: [192.168.80.${server_ip}/24]"
        echo $static_interface >> /etc/netplan/01-netcfg.yaml
        adress_id=$((server_ip+1))
    done
    netplan apply
    ifconfig

    cmd="lava-echo-ipv4"
    if which "${cmd}"; then
        ipaddr=$(${cmd} "${ETH}" | tr -d '\0')
        if [ -z "${ipaddr}" ]; then
            lava-test-raise "${ETH} not found"
        fi
    else
        echo "WARNING: command ${cmd} not found. We are not running in the LAVA environment."
    fi
    cmd="lava-send"
    if which "${cmd}"; then
        ${cmd} server-ready ipaddr="${ipaddr}"
    fi

    # We are running in server mode.
    # Start the server and report pass/fail
    cmd="iperf3 -s -B 192.168.80.50 -D"
    ${cmd}
    if pgrep -f "${cmd}" > /dev/null; then
        result="pass"
    else
        result="fail"
    fi
    echo "iperf3_server_started ${result}" | tee -a "${RESULT_FILE}"

    cmd="lava-wait"
    if which "${cmd}"; then
        ${cmd} client-done
    fi
else
    client_ip=80

    IFS=','
    for interface in $interfaces
    do
        static_interface="    ${interface}:
        dhcp4: no
        addresses: [192.168.80.${client_ip}/24]"
        echo $static_interface >> /etc/netplan/01-netcfg.yaml
        client_ip=$((client_ip+1))
    done

    netplan apply

    ifconfig

    cmd="lava-wait"
    if which "${cmd}"; then
        ${cmd} server-ready
        SERVER=$(grep "ipaddr" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
    else
        echo "WARNING: command ${cmd} not found. We are not running in the LAVA environment."
    fi

    if [ -z "${SERVER}" ]; then
        echo "ERROR: no server specified"
        exit 1
    fi
    # We are running in client mode
    # Run iperf test with unbuffered output mode.
    # stdbuf -o0 iperf3 -c "${SERVER}" -t "${TIME}" -P "${THREADS}" "${REVERSE}" "${AFFINITY}" 2>&1 \
    #     | tee "${LOGFILE}"

    stdbuf -o0 iperf3 -c "${SERVER}" -t "${TIME}" -P "${THREADS}" "${REVERSE}" "${AFFINITY}" 2>&1 \
        | tee "${LOGFILE}"

    # Parse logfile.
    if [ "${THREADS}" -eq 1 ]; then
        grep -E "(sender|receiver)" "${LOGFILE}" \
            | awk '{printf("iperf_%s pass %s %s\n", $NF,$7,$8)}' \
            | tee -a "${RESULT_FILE}"
    elif [ "${THREADS}" -gt 1 ]; then
        grep -E "[SUM].*(sender|receiver)" "${LOGFILE}" \
            | awk '{printf("iperf_%s pass %s %s\n", $NF,$6,$7)}' \
            | tee -a "${RESULT_FILE}"
    fi

    cmd="lava-send"
    if which "${cmd}"; then
        ${cmd} client-done
    fi
fi
