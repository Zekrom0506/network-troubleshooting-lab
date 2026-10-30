# Network Troubleshooting Lab

**FRRouting · Containerlab · Docker · Linux**

A 5-router network that runs on a laptop. It has OSPF inside the network, eBGP to a simulated
ISP, VLAN-separated LAN segments with DHCP, and iptables access-control rules. Everything
starts with **one command**.

On top of the working network there are **5 common failures** you can inject and fix. Each one is
written up like a real support ticket: symptom, commands used, root cause, and fix.

```
./lab.sh up        # start the whole network (about 30 seconds)
./lab.sh check     # 12 health checks, PASS / FAIL
./lab.sh break 3   # inject failure number 3
./lab.sh fix 3     # repair it and re-check
./lab.sh down      # remove everything
```

---

## Topology

```
                    +---------+
                    |   isp   |  AS 65100   "Internet": 8.8.8.8, 1.1.1.1
                    +----+----+
                         |  eBGP   203.0.113.0/30
                    +----+----+
                    |   r1    |  AS 65001   edge router
                    +--+---+--+
          10.0.12.0/30 |   | 10.0.13.0/30
              +--------+   +--------+
         +----+----+           +----+----+
         |   r2    |-----------|   r3    |  core routers
         +----+----+ 10.0.23/30+----+----+
          10.0.24.0/30 |           | 10.0.34.0/30
              +--------+   +-------+
                    +--+---+--+
                    |   r4    |  LAN gateway: VLANs, DHCP, firewall
                    +----+----+
                         |  802.1Q trunk (VLAN 10 + 20)
                    +----+----+
                    |   sw1   |  Linux VLAN-aware bridge
                    +--+---+--+
              VLAN 10  |   |  VLAN 20
                 +-----+   +-----+
              +--+--+         +--+--+
              | pc1 |         | pc2 |
              +-----+         +-----+
            Staff LAN        Guest LAN
         192.168.10.0/24   192.168.20.0/24
```

| Node | Role | Software |
|---|---|---|
| isp | Simulated ISP, AS 65100, sends a default route | FRRouting (bgpd) |
| r1 | Edge router, AS 65001, eBGP to ISP, OSPF inside | FRRouting (bgpd, ospfd) |
| r2, r3 | Core routers, OSPF area 0 | FRRouting (ospfd) |
| r4 | LAN gateway: VLAN sub-interfaces, DHCP server, firewall | FRRouting, dnsmasq, iptables |
| sw1 | Access switch (1 trunk port, 2 access ports) | Linux bridge with VLAN filtering |
| pc1, pc2 | End users, get their address by DHCP | Alpine Linux, udhcpc |

### IP plan

| Network | Use |
|---|---|
| 203.0.113.0/30 | isp (.1) - r1 (.2) |
| 10.0.12.0/30, 10.0.13.0/30, 10.0.23.0/30, 10.0.24.0/30, 10.0.34.0/30 | Point-to-point links (lower router = .1) |
| 10.255.0.1 - 10.255.0.4 | Router loopbacks / router IDs for r1 - r4 |
| 192.168.10.0/24 | VLAN 10 Staff, gateway .1, DHCP pool .100 - .150 |
| 192.168.20.0/24 | VLAN 20 Guest, gateway .1, DHCP pool .100 - .150 |
| 8.8.8.8, 1.1.1.1 | "Internet" test addresses on the ISP loopback |

### How the pieces fit together

- **OSPF** (area 0) runs on every link between r1, r2, r3 and r4, so the network has two paths
  from the LAN to the edge (via r2 and via r3).
- **eBGP**: r1 (AS 65001) peers with the ISP (AS 65100). Prefix-lists and route-maps make sure
  r1 only announces the two LAN subnets and only accepts the default route and the test prefixes.
- r1 injects the **default route** into OSPF with `default-information originate`. If BGP goes
  down, the default route disappears from the whole network.
- **VLANs**: r4 has two sub-interfaces on its trunk port (`eth3.10`, `eth3.20`). sw1 tags and
  untags the frames, so pc1 and pc2 are in separate broadcast domains.
- **DHCP**: dnsmasq on r4 serves one pool per VLAN and hands out the gateway address.
- **Firewall** (iptables on r4, see [`configs/r4/firewall.sh`](configs/r4/firewall.sh)):
  Staff may go anywhere, Guest may reach the Internet but **not** the Staff LAN, and nothing
  from outside may open new connections into the LANs.

---

## Requirements

- **Docker** - Docker Desktop or OrbStack on macOS, Docker Engine on Linux
- **Containerlab** - optional. If it is not installed, `lab.sh` runs containerlab inside a
  Docker container automatically (the method the containerlab docs recommend for macOS).
- About 1 GB of free RAM. Works on Intel/AMD and Apple Silicon (all images are multi-arch).

## Quick start

```bash
git clone https://github.com/<your-username>/network-troubleshooting-lab.git
cd network-troubleshooting-lab
./lab.sh up
```

The first run builds two small images (FRR + tools, Alpine + tools). After that, `up` takes about
30 seconds and ends with the health checks:

```
Routing
  PASS  r1 has 2 OSPF neighbors in Full state
  PASS  r2 has 3 OSPF neighbors in Full state
  PASS  r3 has 3 OSPF neighbors in Full state
  PASS  r4 has 2 OSPF neighbors in Full state
  PASS  r1 <-> ISP eBGP session is Established
  PASS  r4 has a default route learned via OSPF
LAN services
  PASS  pc1 got a DHCP address in VLAN 10
  PASS  pc2 got a DHCP address in VLAN 20
Reachability
  PASS  pc1 (Staff) can reach the Internet 8.8.8.8
  PASS  pc2 (Guest) can reach the Internet 1.1.1.1
  PASS  r1 can reach the Guest gateway 192.168.20.1
Security policy
  PASS  pc2 (Guest) is BLOCKED from pc1 (Staff)

All 12 checks passed - the network is healthy.
```

### All commands

| Command | What it does |
|---|---|
| `./lab.sh up` | Build images (first time only) and start the network |
| `./lab.sh down` | Stop and remove the network |
| `./lab.sh build` | Rebuild the images after editing `images/` |
| `./lab.sh check` | Run the 12 health checks |
| `./lab.sh status` | Routing tables, OSPF neighbors and BGP summary |
| `./lab.sh scenarios` | List the failure scenarios |
| `./lab.sh break <n>` / `fix <n>` | Inject / repair scenario n |
| `./lab.sh vtysh r1` | Open the FRR router CLI on a router |
| `./lab.sh shell pc1` | Open a shell on any node |

Useful commands once you are inside:

```bash
./lab.sh vtysh r4
  show ip ospf neighbor
  show ip route
  show bgp summary            # on r1 or isp

docker exec clab-netlab-pc1 traceroute -n 8.8.8.8
docker exec clab-netlab-r4 iptables -L FORWARD -n -v --line-numbers
docker exec clab-netlab-r4 tail /var/log/dnsmasq.log
docker exec clab-netlab-r4 tail /var/log/frr/frr.log
```

---

## Failure scenarios

Each scenario folder has a `break.sh`, a `fix.sh`, and a `README.md` written as a support ticket
(symptom → commands used → root cause → fix → verification → prevention). The command outputs in the
tickets are real outputs from this lab.

| # | Scenario | User-visible symptom | Root cause |
|---|---|---|---|
| 1 | [OSPF MTU mismatch](scenarios/01-ospf-mtu-mismatch/README.md) | One uplink of r4 lost, no redundancy | MTU 1400 vs 9500 on r4-r2 link, OSPF stuck in ExStart/Exchange |
| 2 | [Wrong BGP AS number](scenarios/02-bgp-wrong-as/README.md) | Nobody can reach the Internet | ISP neighbor configured as AS 65200 instead of 65100 (Bad Peer AS) |
| 3 | [Routing loop](scenarios/03-routing-loop/README.md) | Guest Wi-Fi has no Internet | Leftover static routes on r2 and r3 point at each other |
| 4 | [Blocking firewall rule](scenarios/04-firewall-block/README.md) | Staff have no Internet | DROP rule for the wrong subnet inserted at the top of FORWARD |
| 5 | [DHCP failure](scenarios/05-dhcp-failure/README.md) | Guest devices get no IP address | Guest DHCP pool mistyped as 192.168.21.x |

Try it without reading the answer first: run `./lab.sh break <n>`, read only the **Symptom**
section of the ticket, and troubleshoot from there.

---

## Repository layout

```
.
├── lab.sh                     # the one script you need
├── topology.clab.yml          # containerlab topology (nodes + links)
├── images/
│   ├── router/Dockerfile      # FRR + dnsmasq + iptables + tcpdump
│   └── host/Dockerfile        # Alpine + iproute2 + tcpdump (switch and PCs)
├── configs/
│   ├── daemons                # which FRR daemons to start
│   ├── vtysh.conf
│   ├── isp/ r1/ r2/ r3/       # frr.conf for each router
│   ├── r4/                    # frr.conf, dnsmasq.conf, firewall.sh, setup.sh
│   ├── sw1/setup.sh           # VLAN-aware bridge
│   └── pc1/ pc2/setup.sh      # DHCP client
├── scripts/router-setup.sh    # common start-up steps for all routers
└── scenarios/
    ├── 01-ospf-mtu-mismatch/  # break.sh, fix.sh, README.md (ticket)
    ├── 02-bgp-wrong-as/
    ├── 03-routing-loop/
    ├── 04-firewall-block/
    └── 05-dhcp-failure/
```

## Notes

- Changes made with `break` only touch the running state of the containers, never the files in this
  repo. `./lab.sh down && ./lab.sh up` always gives you a clean network.
- Containerlab gives every link an MTU of 9500 by default; scenario 1 lowers one side to 1400.
- In a real network the LANs would use NAT towards the ISP. NAT is left out here on purpose so that
  routing problems are easy to see with ping and traceroute.
