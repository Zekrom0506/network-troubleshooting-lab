#!/usr/bin/env bash
# Break: an engineer wanted to temporarily block the GUEST network
# (192.168.20.0/24) but typed the STAFF subnet (192.168.10.0/24) instead,
# and put the rule at the very top of the FORWARD chain.

docker exec clab-netlab-r4 iptables -I FORWARD 1 \
    -s 192.168.10.0/24 \
    -m comment --comment "TEMP block guest wifi - CHG-1042" \
    -j DROP

echo "firewall rule inserted on r4"
