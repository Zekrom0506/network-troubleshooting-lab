# 3 - Routing loop

| Ticket | NET-1003 |
|---|---|
| Priority | P2 - guest network has no Internet |
| Reported by | Front desk: "Guest Wi-Fi connects but nothing loads" |
| Affected | Guest LAN 192.168.20.0/24 (return traffic) |

**Inject:** `./lab.sh break 3`  **Repair:** `./lab.sh fix 3`

## Symptom
Guests have an IP address but cannot reach anything. Staff are fine.

```
$ ./lab.sh check
  FAIL  pc2 (Guest) can reach the Internet 1.1.1.1
  FAIL  r1 can reach the Guest gateway 192.168.20.1
```

## Troubleshooting

**1. Confirm the user problem.**

```
$ docker exec clab-netlab-pc2 ping -c2 -W1 1.1.1.1
2 packets transmitted, 0 received, 100% packet loss
$ docker exec clab-netlab-pc1 ping -c1 -W1 8.8.8.8
rtt min/avg/max/mdev = 0.118/0.118/0.118/0.000 ms      <- staff works
```

> Outgoing traffic from guests leaves fine, so the problem is probably the **way back**
> to 192.168.20.0/24. Test from the edge router towards the guest gateway.

**2. Traceroute from r1 towards the guest gateway.** The same two routers repeat forever.

```
$ docker exec clab-netlab-r1 traceroute -n -m 8 -w 1 -q 1 192.168.20.1
 1  10.0.12.2      <- r2
 2  10.0.13.2      <- r3
 3  10.0.12.2      <- r2
 4  10.0.13.2      <- r3
 5  10.0.12.2
 6  10.0.13.2
 7  10.0.12.2
 8  10.0.13.2
```

That is a **routing loop between r2 and r3**. (r3 answers with its r1-facing address 10.0.13.2.)

**3. See which route r2 is using for the guest subnet.**

```
$ docker exec clab-netlab-r2 vtysh -c "show ip route 192.168.20.0/24"
Routing entry for 192.168.20.0/24
  Known via "static", distance 1, metric 0, best
  * 10.0.23.2, via eth2, weight 1          <- sends it to r3

Routing entry for 192.168.20.0/24
  Known via "ospf", distance 110, metric 20  <- correct route, but not used
```

r3 has the mirror image: a static route for 192.168.20.0/24 pointing back to r2 (10.0.23.1).

```
$ docker exec clab-netlab-r3 vtysh -c "show running-config" | grep "ip route"
ip route 192.168.20.0/24 10.0.23.1
```

## Root cause
Two static routes for 192.168.20.0/24 were left over from a maintenance window: r2 points to r3,
and r3 points to r2. A static route has administrative distance **1**, which beats the correct
OSPF route (distance **110**), so both routers ignore OSPF and pass the packets back and forth until
the TTL runs out.

## Fix

```
docker exec clab-netlab-r2 vtysh -c "conf t" -c "no ip route 192.168.20.0/24 10.0.23.2"
docker exec clab-netlab-r3 vtysh -c "conf t" -c "no ip route 192.168.20.0/24 10.0.23.1"
```

## Verification

```
$ docker exec clab-netlab-r2 vtysh -c "show ip route 192.168.20.0/24"
  Known via "ospf", distance 110, metric 20, best

$ ./lab.sh check
All 12 checks passed - the network is healthy.
```

## Prevention
- Every temporary static route needs a change ticket with a removal step.
- Do not add static routes for prefixes that are already in OSPF.
- Regularly search the configs for `ip route` lines that are not documented.
