#!/bin/bash

declare -a GATEWAYS
declare -a NETWORKS
METRIC=10
# DEBUG=true

logger() {
    echo $(date +%FT%T): $* | tee -a ${LOG_FILE:-/dev/zero}
}

su_do() {
    logger Executing: $*
    if ${DEBUG:-false}; then
        return
    fi
    if [[ $USER == root ]]; then
        $*
    else
        sudo $*
    fi
}

main() {
    while true; do
        T_START=$(date +%s)
        for GW in ${GATEWAYS[@]}; do
            if ping $GW -c ${TRIES:-1} -q -w ${TIMEOUT:-5} 2>&1 > /dev/zero; then
                for NET in ${NETWORKS[@]}; do
                    if [[ $(ip ro ls via $GW) =~ ${NET} ]]; then
                        ${DEBUG:-false} && logger $GW is OK, route to $NET is OK
                    else
                        logger $GW is reachable, adding back route to $NET
                        su_do ip ro add ${NET} via $GW metric ${METRIC}
                        METRIC=$((1+$METRIC))
                    fi
                done
            else
                logger $GW is unreachable!
                for NET in NETWORKS; do
                    if [[ $(ip ro ls via $GW) =~ default ]]; then
                        logger $GW is unreachable, removing route to $NET!
                        su_do ip ro del ${NET} via $GW
                    else
                        ${DEBUG:-false} && logger $GW is FAILED, route to $NET is ABSENT
                    fi
                done
            fi
        done
        T_END=$(date +%s)
        sleep $((${INTERVAL:-15}-T_END+T_START))
    done
}

while [[ $# -gt 0 ]]; do
    arg="$1"
    shift
    case $arg in
        -d|--debug)
            DEBUG=true
            logger debug enabled
            ;;
        -t|--timeout)
            TIMEOUT=$1
            logger using ping timeout of $1
            shift
            ;;
        -i|--interval)
            INTERVAL=$1
            logger using ping interval of $1
            shift
            ;;
        -r|--retries)
            TRIES=$1
            logger using $1 ping retries
            shift
            ;;
        -n|--network)
            NETWORKS+=($1)
            logger adding managed network $1
            shift
            ;;
        -l|--log)
            LOG_FILE=$1
            shift
            ;;
        -h|--help)
            cat << END
Usage: $0 <args>
    -d, --debug             More logs, do not EXEC ip route commands
    -t, --timeout <num>     PING timeout [5]
    -i, --interal <num>     Interval between PING attempts [15]
    -r, --retries <num>     Number of PING packets to send [1]
    -n, --network x.x.x.x/x IP prefix to manage [default]
    -l, --log <file>        Write logs to file [/dev/zero]
    -g, --gateway x.x.x.x   Monitor gateway x.x.x.x with route
                            metric of <num> (required)
    -h, --help              This message
END
            exit
            ;;
        -g|--gateway)
            logger Adding $1 as gateway
            GATEWAYS+=($1)
            shift
            ;;
    esac
done

if [[ -z ${NETWORKS[@]} ]]; then
    NETWORKS=("default")
    logger using default managed network
fi
if [[ -z ${GATEWAYS[@]} ]]; then
    logger "ERROR: specify gateways to monitor!" && exit 1
fi
if [[ -n ${LOG_FILE} ]]; then
    [[ -d $(dirname ${LOG_FILE}) ]] || unset LOG_FILE
fi

main
