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
PORT="8000"

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

global_adress=130

# Run local iperf3 server as a daemon when testing localhost.
if [ "${SERVER}" = "" ]; then
    /etc/init.d/network-manager restart
    for interface in $interfaces
    do
        ifconfig ${interface} 192.168.${global_adress}.10 netmask 255.255.255.0
        global_adress=$((global_adress+1))
    done
    ifconfig
    sleep 2

    ip_addreses=""
    server_ips=0
    for interface in $interfaces
    do
        cmd="lava-echo-ipv4"
        if which "${cmd}"; then
            ipaddr=$(${cmd} "${interface}" | tr -d '\0')

            # Check if interface really active
            if ethtool ${interface} | grep -q "Link detected: yes"; then
                if [ ! -z ${ip_addreses} ]; then
                    ip_addreses="${ip_addreses},"
                fi
                ip_addreses="${ip_addreses}${ipaddr}"
                server_ips=$((server_ips+1))
            fi

            if [ -z "${ipaddr}" ]; then
                echo "WARNING: could not find ${interface} adress, check phisial connection"
            fi
        else
            echo "WARNING: command ${cmd} not found. We are not running in the LAVA environment."
        fi
    done

    cmd="lava-send"
    if which "${cmd}"; then
        ${cmd} num_server_interfaces s_length="${server_ips}"
    fi

    # TODO
    # cmd="lava-wait"
    # if which "${cmd}"; then
    #     ${cmd} num_client_interfaces
    #     num_ci=$(grep "fffff" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
    # fi

    IFS=','
    cmd=""
    r_s_counter=1
    for active_interface in ${ip_addreses}
    do
        r_s_counter=$((r_s_counter+1))

        #cmd="${cmd} iperf3 -s -B ${active_interface} -p ${PORT} -D >/dev/null &"
        iperf3 -s -B ${active_interface} -p ${PORT} -D

        # echo "iperf3_server_${r_s_counter}_started ${result}" | tee -a "${RESULT_FILE}"
    done
    unset IFS

    # TODO maybe need to check by pid
    # ${cmd}

    cmd="lava-send"
    if which "${cmd}"; then
        ${cmd} servers-ready ipaddrs="$(echo ${ip_addreses} | xargs)"
    fi

    cmd="lava-wait"
    if which "${cmd}"; then
        ${cmd} client-done
    fi
else
    for interface in $interfaces
    do
        ifconfig ${interface} 192.168.${global_adress}.11 netmask 255.255.255.0
        global_adress=$((global_adress+1))
    done
    ifconfig
    sleep 2

    ip_addreses=""
    for interface in $interfaces
    do
        cmd="lava-echo-ipv4"
        if which "${cmd}"; then
            ipaddr=$(${cmd} "${interface}" | tr -d '\0')

            # Check if interface really active
            if ethtool ${interface} | grep -q "Link detected: yes"; then
                if [ ! -z ${ip_addreses} ]; then
                    ip_addreses="${ip_addreses},"
                fi
                ip_addreses="${ip_addreses}${ipaddr}"
            fi

            if [ -z "${ipaddr}" ]; then
                echo "WARNING: could not find ${interface} adress, check phisial connection"
            fi
        else
            echo "WARNING: command ${cmd} not found. We are not running in the LAVA environment."
        fi
    done

    cmd="lava-wait"
    if which "${cmd}"; then
        ${cmd} servers-ready
        server_adreses=$(grep "ipaddrs" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
    else
        echo "WARNING: command ${cmd} not found. We are not running in the LAVA environment."
    fi

    if [ "${server_adreses}" -eq 0 ]; then
        echo "ERROR: The number f servers is 0"
        exit 1
    fi

    IFS=','
    cmd=""
    counter=1
    for server_adress in $server_adreses
    do
#        if [ ! -z ${cmd} ]; then
#            cmd="${cmd} /&"
#        fi
#        cmd="${cmd} stdbuf -o0 iperf3 -c "${server_adress}" -B $(echo -n $ip_addreses | cut -d' ' -f${counter}) -p 8000 -t "${TIME}" -P "${THREADS}" "${REVERSE}" "${AFFINITY}" 2>&1 \
#            | tee "${LOGFILE}-ens1f$((counter - 1)).txt""
        stdbuf -o0 iperf3 -c "${server_adress}" -B $(echo -n $ip_addreses | cut -d' ' -f${counter}) -p 8000 -t "${TIME}" -P "${THREADS}" "${REVERSE}" "${AFFINITY}" 2>&1 \
            | tee "${LOGFILE}-ens1f$((counter - 1)).txt"
        counter=$((counter + 1))
    done
    unset IFS

    ${cmd}

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
