# Router image used by all 5 routers.
# It is the official FRRouting image plus a few extra tools we need:
#   - dnsmasq  : small DHCP server (runs on r4 for the LAN VLANs)
#   - iptables : Linux firewall (access-control rules on r4)
#   - tcpdump  : packet capture, very handy while troubleshooting
FROM quay.io/frrouting/frr:10.2.1

RUN apk add --no-cache dnsmasq iptables tcpdump

# Folder for the FRR log file (see "log file" in each frr.conf)
RUN mkdir -p /var/log/frr && chown frr:frr /var/log/frr
