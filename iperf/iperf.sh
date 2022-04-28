#!/bin/sh -ex

# shellcheck disable=SC1091
. ../utils/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/iperf"
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

for line in $vlan_interfaces_lines
do
    interfaces="${interfaces} $(echo $line | cut -d',' -f1)"
done

static_network_header="network:
  version: 2
  renderer: networkd
  ethernets:"

echo "$static_network_header" > /etc/netplan/01-netcfg.yaml
global_adress=100

# Run local iperf3 server as a daemon when testing localhost.
if [ "${SERVER}" = "" ]; then
    for interface in $interfaces
    do
        static_interface="    ${interface}:
        dhcp4: no
        addresses: [192.168.${global_adress}.0/24]"
        echo "$static_interface" >> /etc/netplan/01-netcfg.yaml
        global_adress=$((global_adress+1))
    done
    netplan apply
    ifconfig

    ip_addreses=""
    for interface in $interfaces
    do
        cmd="lava-echo-ipv4"
        if which "${cmd}"; then
            ipaddr=$(${cmd} "${interface}" | tr -d '\0')
            ip_addreses="${ip_addreses} ${ipaddr}"
            if [ -z "${ipaddr}" ]; then
                echo "WARNING: could not find ${interface} adress, check phisial connection"
            fi
        else
            echo "WARNING: command ${cmd} not found. We are not running in the LAVA environment."
        fi
    done

    cmd="lava-send"
    if which "${cmd}"; then
        ${cmd} num_server_interfaces s_length="$(echo -n ${ip_addreses} | wc -w)"
    fi

    # TODO
    # cmd="lava-wait"
    # if which "${cmd}"; then
    #     ${cmd} num_client_interfaces
    #     num_ci=$(grep "fffff" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
    # fi

    r_s_counter=1
    for active_interface in ${ip_addreses}
    do
        cmd="lava-send"
        if which "${cmd}"; then
            ${cmd} server-ready-${r_s_counter} ipaddr="${active_interface}"
            r_s_counter=$((r_s_counter+1))

            cmd="iperf3 -s -B ${active_interface} -D"
            ${cmd}
            if pgrep -f "${cmd}" > /dev/null; then
                result="pass"
            else
                result="fail"
            fi
            echo "iperf3_server_${r_s_counter}_started ${result}" | tee -a "${RESULT_FILE}"
        fi
    done

    cmd="lava-wait"
    if which "${cmd}"; then
        ${cmd} client-done
    fi
else
    for interface in $interfaces
    do
        static_interface="    ${interface}:
        dhcp4: no
        addresses: [192.168.${global_adress}.1/24]"
        echo "$static_interface" >> /etc/netplan/01-netcfg.yaml
        global_adress=$((global_adress+1))
    done
    netplan apply
    ifconfig

    ip_addreses=""
    for interface in $interfaces
    do
        cmd="lava-echo-ipv4"
        if which "${cmd}"; then
            ipaddr=$(${cmd} "${interface}" | tr -d '\0')
            ip_addreses="${ip_addreses} ${ipaddr}"
            if [ -z "${ipaddr}" ]; then
                echo "WARNING: could not find ${interface} adress, check phisial connection"
            fi
        else
            echo "WARNING: command ${cmd} not found. We are not running in the LAVA environment."
        fi
    done

    cmd="lava-wait"
    if which "${cmd}"; then
        ${cmd} num_server_interfaces
        num_servers=$(grep "s_length" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
    else
        echo "WARNING: command ${cmd} not found. We are not running in the LAVA environment."
    fi

    if [ "${num_servers}" -eq 0 ]; then
        echo "ERROR: The number is active interfaces is 0"
        exit 1
    fi


    counter=1
    while [ ${counter} -le ${num_servers} ]
    do
        cmd="lava-wait"
        ${cmd} server-ready-${counter}
        SERVER=$(grep "ipaddr" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')

        # TODO log interfaces
        stdbuf -o0 iperf3 -c "${SERVER}" -B $(echo -n $ip_addreses | cut -d' ' -f${counter}) -t "${TIME}" -P "${THREADS}" "${REVERSE}" "${AFFINITY}" 2>&1 \
            | tee "${LOGFILE}-ens1f$((counter - 1)).txt"

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

        counter=$((counter + 1))
    done

    # We are running in client mode
    # Run iperf test with unbuffered output mode.
    # stdbuf -o0 iperf3 -c "${SERVER}" -t "${TIME}" -P "${THREADS}" "${REVERSE}" "${AFFINITY}" 2>&1 \
    #     | tee "${LOGFILE}"



#    stdbuf -o0 iperf3 -c "${SERVER}" -t "${TIME}" -P "${THREADS}" "${REVERSE}" "${AFFINITY}" 2>&1 \
#        | tee "${LOGFILE}"


    cmd="lava-send"
    if which "${cmd}"; then
        ${cmd} client-done
    fi
fi
