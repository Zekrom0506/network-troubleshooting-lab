#!/usr/bin/env bash
# Break: while changing the guest DHCP pool, the subnet is mistyped as
# 192.168.21.x - a network that does not exist on any r4 interface.
# dnsmasq is restarted with the bad config, then pc2 renews its address.

# 1. Edit the live DHCP config on r4 and restart dnsmasq
docker exec clab-netlab-r4 sed -i \
    's/dhcp-range=set:guest,192.168.20.100,192.168.20.150/dhcp-range=set:guest,192.168.21.100,192.168.21.150/' \
    /etc/dnsmasq.conf
docker exec clab-netlab-r4 pkill dnsmasq
sleep 1
docker exec clab-netlab-r4 dnsmasq --conf-file=/etc/dnsmasq.conf

# 2. pc2 loses its lease (like a laptop that was switched off and on again)
docker exec clab-netlab-pc2 pkill udhcpc
docker exec clab-netlab-pc2 ip addr flush dev eth1
docker exec clab-netlab-pc2 udhcpc -i eth1 -b -p /var/run/udhcpc.eth1.pid

echo "guest DHCP pool changed and pc2 asked for a new address"
