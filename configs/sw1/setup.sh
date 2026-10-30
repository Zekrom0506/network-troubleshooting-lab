#!/bin/sh
# sw1 is a simple access switch built from a Linux bridge with VLAN filtering.
#   eth1 = trunk port to r4 (carries VLAN 10 and VLAN 20, tagged)
#   eth2 = access port for pc1 in VLAN 10 (untagged)
#   eth3 = access port for pc2 in VLAN 20 (untagged)

# Create the bridge ("the switch") and turn on VLAN awareness
ip link add br0 type bridge vlan_filtering 1
ip link set br0 up

# Plug the three ports into the switch
for port in eth1 eth2 eth3; do
    ip link set $port master br0
    ip link set $port up
    # Remove the default VLAN 1 so only our VLANs are used
    bridge vlan del dev $port vid 1
done

# Trunk port: VLAN 10 and 20, tagged
bridge vlan add dev eth1 vid 10
bridge vlan add dev eth1 vid 20

# Access ports: untagged member of one VLAN each
bridge vlan add dev eth2 vid 10 pvid untagged
bridge vlan add dev eth3 vid 20 pvid untagged

echo "switch setup done"
