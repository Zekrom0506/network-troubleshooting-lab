#!/usr/bin/env bash
# Fix: put the MTU back to 9500 so it matches r2, then bounce the interface
# so OSPF re-forms the adjacency straight away.

docker exec clab-netlab-r4 ip link set dev eth1 mtu 9500

docker exec clab-netlab-r4 vtysh \
    -c "configure terminal" \
    -c "interface eth1" \
    -c "shutdown" \
    -c "no shutdown"

echo "r4 eth1 MTU restored to 9500"
