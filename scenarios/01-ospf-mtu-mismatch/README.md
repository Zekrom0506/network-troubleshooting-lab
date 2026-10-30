# 1 - OSPF MTU mismatch

| Ticket | NET-1001 |
|---|---|
| Priority | P3 - redundancy lost, no user outage |
| Reported by | Monitoring: "OSPF neighbor r2 on r4 not Full" |
| Affected | r4 <-> r2 link (10.0.24.0/30) |

**Inject:** `./lab.sh break 1`  **Repair:** `./lab.sh fix 1`

## Symptom
Monitoring reports that r4 has only one working uplink. Users can still reach the Internet,
because all traffic now goes through r3. If r3 fails, the whole LAN goes offline.

```
$ ./lab.sh check
  FAIL  r2 has 3 OSPF neighbors in Full state
  FAIL  r4 has 2 OSPF neighbors in Full state
  PASS  pc1 (Staff) can reach the Internet 8.8.8.8
  PASS  pc2 (Guest) can reach the Internet 1.1.1.1
```

## Troubleshooting

**1. Look at the OSPF neighbors on r4.** The neighbor to r2 is stuck in `ExStart` instead of `Full`.

```
$ docker exec clab-netlab-r4 vtysh -c "show ip ospf neighbor"
Neighbor ID     Pri State           Up Time   Dead Time Address    Interface
10.255.0.3        1 Full/-          1m11s     33.692s   10.0.34.1  eth2:10.0.34.2
10.255.0.2        1 ExStart/-       41.321s   38.678s   10.0.24.1  eth1:10.0.24.2
```

On r2 the same neighbor is stuck in `Exchange`:

```
$ docker exec clab-netlab-r2 vtysh -c "show ip ospf neighbor"
10.255.0.4        1 Exchange/-      41.437s   38.562s   10.0.24.2  eth3:10.0.24.1
```

> Hello packets work (the routers see each other), but the database exchange (DBD packets)
> never finishes. Being stuck in ExStart/Exchange is the classic sign of an **MTU mismatch**.

**2. Compare the MTU on both ends of the link.**

```
$ docker exec clab-netlab-r4 ip link show eth1
98: eth1@if99: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 ...
$ docker exec clab-netlab-r2 ip link show eth3
99: eth3@if98: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9500 ...

$ docker exec clab-netlab-r4 vtysh -c "show ip ospf interface eth1"
  ifindex 98, MTU 1400 bytes, BW 10000 Mbit
  MTU mismatch detection: enabled
```

**3. Confirm in the FRR log.**

```
$ docker exec clab-netlab-r4 grep -i mtu /var/log/frr/frr.log
OSPF: Packet[DD]: Neighbor 10.255.0.2 MTU 9500 is larger than [eth1:10.0.24.2]'s MTU 1400
```

**4. Check where traffic goes now.** r4 reaches r2's loopback only through r3:

```
$ docker exec clab-netlab-r4 vtysh -c "show ip route 10.255.0.2"
Routing entry for 10.255.0.2/32
  Known via "ospf", distance 110, metric 20, best
  * 10.0.34.1, via eth2, weight 1
```

## Root cause
The MTU on r4 `eth1` was changed to 1400 bytes while r2's side of the same link stayed at 9500.
OSPF puts the interface MTU into every DBD packet. r4 rejects r2's DBD packets because
9500 is bigger than its own MTU, so the adjacency can never reach `Full`.

## Fix
Make the MTU the same on both ends of the link:

```
docker exec clab-netlab-r4 ip link set dev eth1 mtu 9500
docker exec clab-netlab-r4 vtysh -c "conf t" -c "interface eth1" -c "shutdown" -c "no shutdown"
```

(`ip ospf mtu-ignore` would also bring the adjacency up, but it only hides the problem -
large packets would still be dropped on that link.)

## Verification

```
$ docker exec clab-netlab-r4 vtysh -c "show ip ospf neighbor"
10.255.0.3        1 Full/-          1m20s     30.564s   10.0.34.1  eth2:10.0.34.2
10.255.0.2        1 Full/-          1.464s    38.534s   10.0.24.1  eth1:10.0.24.2

$ ./lab.sh check
All 12 checks passed - the network is healthy.
```

## Prevention
- Keep MTU in a standard per link type and check both ends during every change.
- Alert on OSPF neighbors that stay in ExStart/Exchange for more than a minute.
