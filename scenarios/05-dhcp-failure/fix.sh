#!/usr/bin/env bash
# Fix: restore the correct DHCP config from the repo copy (/lab/dnsmasq.conf),
# restart dnsmasq, and let pc2 ask for an address again.

docker exec clab-netlab-r4 cp /lab/dnsmasq.conf /etc/dnsmasq.conf
docker exec clab-netlab-r4 pkill dnsmasq
sleep 1
docker exec clab-netlab-r4 dnsmasq --conf-file=/etc/dnsmasq.conf

docker exec clab-netlab-pc2 pkill udhcpc
docker exec clab-netlab-pc2 udhcpc -i eth1 -b -p /var/run/udhcpc.eth1.pid

echo "DHCP config restored and pc2 renewed"
