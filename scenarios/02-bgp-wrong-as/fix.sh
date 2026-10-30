#!/usr/bin/env bash
# Fix: set the correct ISP AS number (65100) on r1.

docker exec clab-netlab-r1 vtysh \
    -c "configure terminal" \
    -c "router bgp 65001" \
    -c "neighbor 203.0.113.1 remote-as 65100"

echo "r1 ISP neighbor set back to AS 65100"
