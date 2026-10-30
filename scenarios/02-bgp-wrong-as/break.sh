#!/usr/bin/env bash
# Break: while editing r1's BGP config, the ISP's AS number is typed
# as 65200 instead of 65100.

docker exec clab-netlab-r1 vtysh \
    -c "configure terminal" \
    -c "router bgp 65001" \
    -c "neighbor 203.0.113.1 remote-as 65200"

echo "r1 now expects the ISP to be AS 65200"
