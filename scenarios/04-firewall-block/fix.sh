#!/usr/bin/env bash
# Fix: delete the wrong rule. We delete it by its exact match (safer than
# deleting "rule number 1", which might be a different rule by now).

docker exec clab-netlab-r4 iptables -D FORWARD \
    -s 192.168.10.0/24 \
    -m comment --comment "TEMP block guest wifi - CHG-1042" \
    -j DROP

echo "wrong firewall rule removed from r4"
