#!/bin/sh
# Extra setup for r4, the LAN gateway.
# 1. Create the two VLAN sub-interfaces on the trunk port eth3
# 2. Start the DHCP server (dnsmasq)
# 3. Load the firewall rules

# --- 1. VLAN sub-interfaces --------------------------------------------
# eth3.10 sends and receives frames tagged with VLAN 10 (Staff)
# eth3.20 sends and receives frames tagged with VLAN 20 (Guest)
ip link add link eth3 name eth3.10 type vlan id 10
ip link add link eth3 name eth3.20 type vlan id 20
ip link set eth3 up
ip link set eth3.10 up
ip link set eth3.20 up

# FRR (zebra) puts the IP addresses from frr.conf on these interfaces as
# soon as they appear. Wait until both have their address.
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if ip -4 addr show eth3.10 | grep -q 192.168.10.1 && \
       ip -4 addr show eth3.20 | grep -q 192.168.20.1; then
        break
    fi
    sleep 1
done

# --- 2. DHCP server ------------------------------------------------------
# /lab/dnsmasq.conf is the "golden" copy from the repo. We copy it to
# /etc/dnsmasq.conf, which is the live config the server actually uses.
cp /lab/dnsmasq.conf /etc/dnsmasq.conf
dnsmasq --conf-file=/etc/dnsmasq.conf

# --- 3. Firewall -----------------------------------------------------------
sh /lab/firewall.sh

echo "r4 LAN setup done"
