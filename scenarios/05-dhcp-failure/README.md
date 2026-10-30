# 5 - DHCP failure

| Ticket | NET-1005 |
|---|---|
| Priority | P2 - new guest devices cannot connect |
| Reported by | Guest: "My laptop says no IP address" |
| Affected | Guest LAN, VLAN 20 |

**Inject:** `./lab.sh break 5`  **Repair:** `./lab.sh fix 5`

## Symptom
A guest device that reconnects gets no IP address. Staff devices still get addresses.

```
$ ./lab.sh check
  FAIL  pc2 got a DHCP address in VLAN 20
  FAIL  pc2 (Guest) can reach the Internet 1.1.1.1
```

## Troubleshooting

**1. Check the client.** pc2 has no IPv4 address and no default route on eth1.

```
$ docker exec clab-netlab-pc2 ip -br addr show eth1
eth1@if132       UP

$ docker exec clab-netlab-pc2 udhcpc -i eth1 -f -n -t 3 -T 2
udhcpc: started, v1.36.1
udhcpc: broadcasting discover
udhcpc: broadcasting discover
udhcpc: broadcasting discover
udhcpc: no lease, failing
```

> The link is up and the client sends DHCP DISCOVER, but nobody answers. Either the request
> does not reach the server (VLAN/switch problem) or the server ignores it.

**2. Check the DHCP server log on r4.**

```
$ docker exec clab-netlab-r4 tail -n 3 /var/log/dnsmasq.log
dnsmasq-dhcp[377]: no address range available for DHCP request via eth3.20
dnsmasq-dhcp[377]: no address range available for DHCP request via eth3.20
dnsmasq-dhcp[377]: no address range available for DHCP request via eth3.20
```

Good news: the request *does* reach r4 on the right VLAN interface (eth3.20), so the switch and
VLANs are fine. The server just has no pool that matches that interface.

**3. Compare the pool with the interface address.**

```
$ docker exec clab-netlab-r4 grep dhcp-range /etc/dnsmasq.conf
dhcp-range=set:staff,192.168.10.100,192.168.10.150,255.255.255.0,1h
dhcp-range=set:guest,192.168.21.100,192.168.21.150,255.255.255.0,1h

$ docker exec clab-netlab-r4 ip -br addr show eth3.20
eth3.20@if131    UP             192.168.20.1/24
```

The guest pool is **192.168.21.x**, but the guest interface is **192.168.20.1/24**.

## Root cause
While the guest DHCP pool was being edited, the subnet was mistyped as 192.168.21.0/24.
dnsmasq only hands out addresses from a range that belongs to the subnet of the interface the
request arrived on, so every guest request on eth3.20 is rejected. Existing guests kept working
until their lease ran out; new or reconnecting devices fail immediately.

## Fix
Restore the correct range (192.168.20.100 - 192.168.20.150), restart dnsmasq, and renew the client:

```
docker exec clab-netlab-r4 cp /lab/dnsmasq.conf /etc/dnsmasq.conf
docker exec clab-netlab-r4 pkill dnsmasq
docker exec clab-netlab-r4 dnsmasq --conf-file=/etc/dnsmasq.conf
docker exec clab-netlab-pc2 udhcpc -i eth1 -b
```

## Verification

```
udhcpc: broadcasting select for 192.168.20.124, server 192.168.20.1
udhcpc: lease of 192.168.20.124 obtained from 192.168.20.1, lease time 3600

$ ./lab.sh check
All 12 checks passed - the network is healthy.
```

## Prevention
- Check new DHCP ranges against the IP plan before restarting the server.
- Monitor the DHCP log for "no address range available".
