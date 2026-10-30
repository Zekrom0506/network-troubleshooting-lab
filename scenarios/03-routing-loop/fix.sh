#!/usr/bin/env bash
# Fix: remove the two static routes so OSPF is used again.

docker exec clab-netlab-r2 vtysh \
    -c "configure terminal" \
    -c "no ip route 192.168.20.0/24 10.0.23.2"

docker exec clab-netlab-r3 vtysh \
    -c "configure terminal" \
    -c "no ip route 192.168.20.0/24 10.0.23.1"

echo "static routes removed from r2 and r3"
