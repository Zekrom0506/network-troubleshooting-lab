#!/usr/bin/env bash
# =============================================================================
#  lab.sh - one script to run the whole Network Troubleshooting Lab
#
#  Usage:
#    ./lab.sh up              build the images and start the whole network
#    ./lab.sh down            stop and remove the network
#    ./lab.sh build           rebuild the Docker images (after editing images/)
#    ./lab.sh check           run health checks (PASS / FAIL for each one)
#    ./lab.sh status          show the routing state of every router
#    ./lab.sh scenarios       list the 5 failure scenarios
#    ./lab.sh break <1-5>     inject a failure
#    ./lab.sh fix <1-5>       repair that failure
#    ./lab.sh shell <node>    open a shell on a node   (e.g. ./lab.sh shell r1)
#    ./lab.sh vtysh <router>  open the FRR router CLI  (e.g. ./lab.sh vtysh r4)
# =============================================================================

# Always run from the folder this script lives in
cd "$(dirname "$0")" || exit 1

LAB_NAME="netlab"
TOPOLOGY="${TOPOLOGY:-topology.clab.yml}"
CLAB_IMAGE="ghcr.io/srl-labs/clab:0.68.0"

# Colours for nice output
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# -----------------------------------------------------------------------------
# Helper: run a command inside one of the lab containers
#   node_exec r1 ip route
# -----------------------------------------------------------------------------
node_exec() {
    local node="$1"
    shift
    docker exec "clab-${LAB_NAME}-${node}" "$@"
}

# -----------------------------------------------------------------------------
# Helper: run containerlab.
# On Linux we use the installed "containerlab" command if there is one.
# On macOS (or Linux without containerlab) we run containerlab inside a
# Docker container - this is the method recommended by the containerlab docs.
# -----------------------------------------------------------------------------
run_containerlab() {
    if [ -n "$CLAB_CMD" ]; then
        $CLAB_CMD "$@"
    elif command -v containerlab >/dev/null 2>&1; then
        sudo containerlab "$@"
    else
        docker run --rm --privileged \
            --network host \
            --pid host \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v /run/netns:/run/netns \
            -v "$PWD":"$PWD" \
            -w "$PWD" \
            "$CLAB_IMAGE" containerlab "$@"
    fi
}

# -----------------------------------------------------------------------------
# up / down
# -----------------------------------------------------------------------------
build_images() {
    echo "==> Building lab images"
    docker build -t netlab-router:1.0 images/router || exit 1
    docker build -t netlab-host:1.0 images/host || exit 1
}

lab_up() {
    # Build the images only if they do not exist yet (first run)
    if ! docker image inspect netlab-router:1.0 >/dev/null 2>&1 || \
       ! docker image inspect netlab-host:1.0 >/dev/null 2>&1; then
        build_images
    fi

    echo "==> Starting the network"
    run_containerlab deploy -t "$TOPOLOGY" --reconfigure || exit 1

    echo "==> Waiting for OSPF, BGP and DHCP to settle"
    wait_until_healthy
    lab_check
}

lab_down() {
    run_containerlab destroy -t "$TOPOLOGY" --cleanup
}

# Wait up to 90 seconds until every health check passes
wait_until_healthy() {
    local seconds=0
    while [ $seconds -lt 90 ]; do
        if lab_check >/dev/null 2>&1; then
            echo "    network healthy after ${seconds}s"
            return 0
        fi
        sleep 3
        seconds=$((seconds + 3))
    done
    echo -e "    ${YELLOW}network still not fully healthy after 90s - see the checks below${RESET}"
}

# -----------------------------------------------------------------------------
# Health checks
# -----------------------------------------------------------------------------
PASSED=0
FAILED=0

# report "description" <command...>
# Runs the command; exit code 0 = PASS, anything else = FAIL
report() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo -e "  ${GREEN}PASS${RESET}  $description"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}FAIL${RESET}  $description"
        FAILED=$((FAILED + 1))
    fi
}

# Count the OSPF neighbors in "Full" state on a router
ospf_full_count() {
    node_exec "$1" vtysh -c "show ip ospf neighbor" 2>/dev/null | grep -c "Full"
}

check_ospf_neighbors() {
    local router="$1"
    local expected="$2"
    [ "$(ospf_full_count "$router")" -eq "$expected" ]
}

check_bgp_established() {
    node_exec r1 vtysh -c "show bgp neighbor 203.0.113.1" | grep -q "BGP state = Established"
}

check_default_route_on_r4() {
    node_exec r4 ip route show default | grep -q "proto ospf"
}

check_dhcp_address() {
    local pc="$1"
    local subnet="$2"
    node_exec "$pc" ip -4 addr show eth1 | grep -q "inet $subnet"
}

check_ping() {
    local from="$1"
    local to="$2"
    node_exec "$from" ping -c 2 -W 1 "$to"
}

check_ping_blocked() {
    ! check_ping "$1" "$2"
}

lab_check() {
    PASSED=0
    FAILED=0
    local pc1_ip
    pc1_ip=$(node_exec pc1 ip -4 -o addr show eth1 2>/dev/null | awk '{print $4}' | cut -d/ -f1)

    echo
    echo "Routing"
    report "r1 has 2 OSPF neighbors in Full state"   check_ospf_neighbors r1 2
    report "r2 has 3 OSPF neighbors in Full state"   check_ospf_neighbors r2 3
    report "r3 has 3 OSPF neighbors in Full state"   check_ospf_neighbors r3 3
    report "r4 has 2 OSPF neighbors in Full state"   check_ospf_neighbors r4 2
    report "r1 <-> ISP eBGP session is Established"   check_bgp_established
    report "r4 has a default route learned via OSPF"  check_default_route_on_r4

    echo "LAN services"
    report "pc1 got a DHCP address in VLAN 10"        check_dhcp_address pc1 192.168.10.
    report "pc2 got a DHCP address in VLAN 20"        check_dhcp_address pc2 192.168.20.

    echo "Reachability"
    report "pc1 (Staff) can reach the Internet 8.8.8.8" check_ping pc1 8.8.8.8
    report "pc2 (Guest) can reach the Internet 1.1.1.1" check_ping pc2 1.1.1.1
    report "r1 can reach the Guest gateway 192.168.20.1" check_ping r1 192.168.20.1

    echo "Security policy"
    if [ -n "$pc1_ip" ]; then
        report "pc2 (Guest) is BLOCKED from pc1 (Staff)" check_ping_blocked pc2 "$pc1_ip"
    else
        report "pc2 (Guest) is BLOCKED from pc1 (Staff)" false
    fi

    echo
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}All $PASSED checks passed - the network is healthy.${RESET}"
        return 0
    else
        echo -e "${RED}$FAILED check(s) failed${RESET}, $PASSED passed."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Status - quick look at every router
# -----------------------------------------------------------------------------
lab_status() {
    for router in isp r1 r2 r3 r4; do
        echo "==================== $router ===================="
        node_exec "$router" vtysh -c "show ip route" | grep -E "^[A-Z>*]" | grep -v "Codes"
    done
    echo "==================== OSPF neighbors on r4 ===================="
    node_exec r4 vtysh -c "show ip ospf neighbor"
    echo "==================== BGP on r1 ===================="
    node_exec r1 vtysh -c "show bgp summary"
}

# -----------------------------------------------------------------------------
# Scenarios
# -----------------------------------------------------------------------------
scenario_folder() {
    # Finds the folder that starts with the scenario number, e.g. scenarios/01-ospf-mtu-mismatch
    local number
    number=$(printf "%02d" "$1")
    ls -d scenarios/"${number}"-* 2>/dev/null | head -n 1
}

list_scenarios() {
    echo "Failure scenarios (./lab.sh break <n>  /  ./lab.sh fix <n>):"
    for folder in scenarios/*/; do
        local title
        title=$(head -n 1 "${folder}README.md" | sed 's/^# //')
        echo "  $title"
    done
}

run_scenario() {
    local action="$1"     # break or fix
    local number="$2"
    local folder
    folder=$(scenario_folder "$number")

    if [ -z "$folder" ]; then
        echo "Unknown scenario '$number'."
        list_scenarios
        exit 1
    fi

    echo "==> $action: $folder"
    bash "$folder/$action.sh"

    if [ "$action" = "break" ]; then
        echo
        echo "Failure injected. Read the ticket in $folder/README.md and start troubleshooting."
        echo "Tip: './lab.sh check' shows what is broken from the user's point of view."
    else
        echo
        echo "==> Waiting for the network to recover"
        wait_until_healthy
        lab_check
    fi
}

# -----------------------------------------------------------------------------
# Main: pick the action from the first argument
# -----------------------------------------------------------------------------
case "$1" in
    up)        lab_up ;;
    down)      lab_down ;;
    build)     build_images ;;
    check)     lab_check ;;
    status)    lab_status ;;
    scenarios) list_scenarios ;;
    break)     run_scenario break "$2" ;;
    fix)       run_scenario fix "$2" ;;
    shell)     docker exec -it "clab-${LAB_NAME}-$2" sh ;;
    vtysh)     docker exec -it "clab-${LAB_NAME}-$2" vtysh ;;
    *)
        sed -n '3,16p' "$0"
        exit 1
        ;;
esac
