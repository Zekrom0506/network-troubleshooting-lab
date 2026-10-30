#!/bin/sh
# End host. Gets its IP address and default gateway from DHCP (served by r4).

# Remove Docker's management default route so traffic goes through the lab network
ip route del default 2>/dev/null

ip link set eth1 up

# udhcpc is the DHCP client that comes with Alpine (busybox).
#   -i eth1 : interface to configure
#   -b      : if no answer yet, keep trying in the background
udhcpc -i eth1 -b -p /var/run/udhcpc.eth1.pid

echo "$(hostname) setup done"
