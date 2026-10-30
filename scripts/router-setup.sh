#!/bin/sh
# Runs inside every router right after it starts.
#
# Docker gives each container a default route through its management
# interface (eth0). We remove it, so that the routers only use the routes
# they learn from OSPF and BGP - exactly like a real network.
ip route del default 2>/dev/null

# Allow the router to forward packets between its interfaces.
sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "router setup done on $(hostname)"
