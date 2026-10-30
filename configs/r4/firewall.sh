#!/bin/sh
# Access-control rules on r4 (the gateway for both LANs).
#
# Policy:
#   - Staff (VLAN 10) may go anywhere.
#   - Guest (VLAN 20) may reach the Internet, but NOT the Staff LAN.
#   - Nobody from outside may open new connections into the LANs,
#     except ping from the router loopbacks (for monitoring).

STAFF=192.168.10.0/24
GUEST=192.168.20.0/24
LOOPBACKS=10.255.0.0/24

# Start from a clean table
iptables -F FORWARD

# Anything not allowed below is dropped
iptables -P FORWARD DROP

# Rule 1: allow replies to connections that were already allowed
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Rule 2: Guest must never reach Staff (checked before the general guest rule)
iptables -A FORWARD -s $GUEST -d $STAFF -j DROP

# Rule 3: Staff can go anywhere
iptables -A FORWARD -s $STAFF -j ACCEPT

# Rule 4: Guest can go anywhere else (the Internet)
iptables -A FORWARD -s $GUEST -j ACCEPT

# Rule 5: monitoring pings from the routers' loopbacks into the LANs
iptables -A FORWARD -s $LOOPBACKS -p icmp --icmp-type echo-request -j ACCEPT

echo "firewall loaded on $(hostname)"
