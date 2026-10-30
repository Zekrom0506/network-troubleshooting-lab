# 2 - Wrong BGP AS number

| Ticket | NET-1002 |
|---|---|
| Priority | P1 - full Internet outage |
| Reported by | Staff and guests: "No Internet for anyone" |
| Affected | r1 eBGP session to the ISP (203.0.113.1) |

**Inject:** `./lab.sh break 2`  **Repair:** `./lab.sh fix 2`

## Symptom
Nobody on either LAN can reach the Internet. Internal routing (OSPF) is fine.

```
$ ./lab.sh check
  FAIL  r1 <-> ISP eBGP session is Established
  FAIL  r4 has a default route learned via OSPF
  FAIL  pc1 (Staff) can reach the Internet 8.8.8.8
  FAIL  pc2 (Guest) can reach the Internet 1.1.1.1
```

## Troubleshooting

**1. Start at the user.** pc1 cannot ping, and the gateway r4 has no default route at all:

```
$ docker exec clab-netlab-pc1 ping -c2 -W1 8.8.8.8
2 packets transmitted, 0 received, +2 errors, 100% packet loss

$ docker exec clab-netlab-r4 ip route show default
(no output)
```

> The default route normally comes from r1 (`default-information originate`), and r1 only
> has a default route while its BGP session to the ISP is up. So check BGP on r1.

**2. Check the BGP session on r1.** It is `Idle`, and the neighbor AS shows **65200**.

```
$ docker exec clab-netlab-r1 vtysh -c "show bgp summary"
Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
203.0.113.1     4      65200        16        15        0    0    0 00:00:26         Idle        0 ISP
```

**3. Look at why the session was reset.**

```
$ docker exec clab-netlab-r1 vtysh -c "show bgp neighbor 203.0.113.1"
BGP neighbor is 203.0.113.1, remote AS 65200, local AS 65001, external link
  BGP state = Idle
  Last reset 00:00:26,  Notification sent (OPEN Message Error/Bad Peer AS)

$ docker exec clab-netlab-r1 grep NOTIFICATION /var/log/frr/frr.log
BGP: %NOTIFICATION: sent to neighbor 203.0.113.1 2/2 (OPEN Message Error/Bad Peer AS)
```

The ISP log shows the other side of the same story:

```
$ docker exec clab-netlab-isp grep NOTIFICATION /var/log/frr/frr.log
BGP: %NOTIFICATION: received from neighbor 203.0.113.2 2/2 (OPEN Message Error/Bad Peer AS)
```

## Root cause
On r1 the ISP neighbor was configured with `remote-as 65200`. The ISP really is AS **65100**
(see the ISP handoff details). When the ISP sends its OPEN message with AS 65100, r1 rejects it
with *Bad Peer AS*, so the session never comes up. No BGP means no default route on r1, so r1
stops advertising a default into OSPF and every LAN loses Internet access.

## Fix

```
docker exec clab-netlab-r1 vtysh -c "conf t" -c "router bgp 65001" \
    -c "neighbor 203.0.113.1 remote-as 65100"
```

## Verification

```
$ docker exec clab-netlab-r1 vtysh -c "show bgp summary"
203.0.113.1     4      65100   ...   00:00:09    3    2 ISP

$ ./lab.sh check
All 12 checks passed - the network is healthy.
```

## Prevention
- Copy the peer AS from the ISP handoff document, never type it from memory.
- Use `neighbor ... description` and check `show bgp summary` before and after every change.
- Alert on any eBGP session that is not Established.
