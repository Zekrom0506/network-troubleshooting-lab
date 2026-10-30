# 4 - Firewall rule blocking traffic

| Ticket | NET-1004 |
|---|---|
| Priority | P1 - all staff lost Internet |
| Reported by | Staff: "Internet stopped right after the 2 PM change" |
| Affected | Staff LAN 192.168.10.0/24 |

**Inject:** `./lab.sh break 4`  **Repair:** `./lab.sh fix 4`

## Symptom
Staff cannot reach the Internet. Guests can. Staff can still ping their own gateway.

```
$ ./lab.sh check
  FAIL  pc1 (Staff) can reach the Internet 8.8.8.8
```

## Troubleshooting

**1. Find where the traffic stops.**

```
$ docker exec clab-netlab-pc1 traceroute -n -m 4 -w 1 -q 1 8.8.8.8
 1  192.168.10.1     <- r4 answers
 2  *
 3  *
 4  *

$ docker exec clab-netlab-pc1 ping -c3 -W1 192.168.10.1
3 packets transmitted, 3 received, 0% packet loss
```

> The gateway answers, but nothing gets past it. Routing on r4 is fine (guests work through the
> same uplinks), so the next suspect is the **firewall on r4**.

**2. List the FORWARD rules with packet counters.**

```
$ docker exec clab-netlab-r4 iptables -L FORWARD -n -v --line-numbers
Chain FORWARD (policy DROP 0 packets, 0 bytes)
num   pkts bytes target  prot  source            destination
1        5   306 DROP    0     192.168.10.0/24   0.0.0.0/0     /* TEMP block guest wifi - CHG-1042 */
2       53  4452 ACCEPT  0     0.0.0.0/0         0.0.0.0/0     ctstate RELATED,ESTABLISHED
3       26  2184 DROP    0     192.168.20.0/24   192.168.10.0/24
4       11   924 ACCEPT  0     192.168.10.0/24   0.0.0.0/0
5       14  1176 ACCEPT  0     192.168.20.0/24   0.0.0.0/0
6        0     0 ACCEPT  1     10.255.0.0/24     0.0.0.0/0     icmptype 8
```

Rule 1 is new, it drops **everything** from 192.168.10.0/24, and its packet counter goes up every
time pc1 pings. Its comment says it was meant to block the **guest** network.
iptables checks rules from top to bottom and stops at the first match, so the normal
"Staff can go anywhere" rule (number 4) is never reached.

## Root cause
During change CHG-1042 a temporary rule meant to block the guest network (192.168.20.0/24)
was inserted at the top of the FORWARD chain with the staff subnet (192.168.10.0/24) by mistake.

## Fix
Delete exactly that rule (deleting by match is safer than deleting "rule 1"):

```
docker exec clab-netlab-r4 iptables -D FORWARD -s 192.168.10.0/24 \
    -m comment --comment "TEMP block guest wifi - CHG-1042" -j DROP
```

## Verification

```
$ docker exec clab-netlab-pc1 ping -c2 -W1 8.8.8.8
2 packets transmitted, 2 received, 0% packet loss

$ ./lab.sh check
All 12 checks passed - the network is healthy.
```

## Prevention
- Peer review every firewall change; check the subnet against the IP plan.
- Always add a comment with the change number (it made this rule easy to find).
- Run `./lab.sh check` (or a similar test) right after each change.
