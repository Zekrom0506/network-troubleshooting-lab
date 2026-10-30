#!/usr/bin/env bash
# Break: someone lowers the MTU on r4's uplink to r2 (eth1) to 1400 bytes.
# r2's side of the same link is still 9500 (containerlab's default MTU), so the two routers disagree.

docker exec clab-netlab-r4 ip link set dev eth1 mtu 1400

# Bounce the OSPF interface so the adjacency has to be built again
# (in real life this happens on the next reboot or link flap).
docker exec clab-netlab-r4 vtysh \
    -c "configure terminal" \
    -c "interface eth1" \
    -c "shutdown" \
    -c "no shutdown"

echo "r4 eth1 MTU changed to 1400"
