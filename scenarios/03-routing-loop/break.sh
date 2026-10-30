#!/usr/bin/env bash
# Break: two engineers add "temporary" static routes for the Guest LAN
# (192.168.20.0/24) during a maintenance window and forget to remove them.
#   r2 sends the Guest LAN to r3
#   r3 sends the Guest LAN back to r2
# Static routes (distance 1) beat OSPF (distance 110), so packets bounce
# between r2 and r3 until their TTL runs out.

docker exec clab-netlab-r2 vtysh \
    -c "configure terminal" \
    -c "ip route 192.168.20.0/24 10.0.23.2"

docker exec clab-netlab-r3 vtysh \
    -c "configure terminal" \
    -c "ip route 192.168.20.0/24 10.0.23.1"

echo "static routes added on r2 and r3"
