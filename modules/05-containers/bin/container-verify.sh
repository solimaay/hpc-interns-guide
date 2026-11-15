#!/usr/bin/env bash
# container-verify - check that this node is ready for the containers chapter.
#
#   container-verify      run it as the user 'vagrant' on every node
#
# Each line is PASS, WARN or FAIL, with a hint when something is wrong.
# Exit code: 0 = no failures, 1 = at least one FAIL.
set -u

. /etc/hpc-lab-release 2>/dev/null || { echo "Not a lab node."; exit 1; }
STAGE="$LAB_SHARED/containers-lab"
IMAGE=docker.io/library/alpine:3.20

fails=0
pass() { printf '[PASS] %-14s %s\n' "$1" "$2"; }
fail() { printf '[FAIL] %-14s %s\n       -> %s\n' "$1" "$2" "$3"; fails=$((fails+1)); }
warn() { printf '[WARN] %-14s %s\n       -> %s\n' "$1" "$2" "$3"; }

echo "Node: $LAB_NODE ($LAB_ROLE), user $(id -un)"
echo

if [ "$(id -u)" = 0 ]; then
  echo "Run this as a normal user (vagrant), not root: the chapter uses rootless Podman."; exit 1
fi

# podman installed
if command -v podman >/dev/null; then pass Podman "$(podman --version)"
else fail Podman "not installed" "run the provisioner: vagrant provision $LAB_NODE --provision-with containers"; fi

# subordinate IDs (rootless needs them)
if grep -q "^$(id -un):" /etc/subuid 2>/dev/null && grep -q "^$(id -un):" /etc/subgid 2>/dev/null; then
  pass "Subuid/subgid" "range defined for $(id -un)"
else fail "Subuid/subgid" "no range for $(id -un) in /etc/subuid or /etc/subgid" "run the provisioner again"; fi

# can it run a container? prefer the staged image so a missing internet is not a failure here
if command -v podman >/dev/null; then
  if ! podman image exists "$IMAGE" 2>/dev/null; then
    if [ -s "$STAGE/alpine.tar" ]; then podman load -q -i "$STAGE/alpine.tar" >/dev/null 2>&1
    else podman pull -q "$IMAGE" >/dev/null 2>&1; fi
  fi
  if [ "$(podman run --rm "$IMAGE" echo ok 2>/dev/null)" = ok ]; then pass "Run container" "rootless run works"
  else fail "Run container" "could not run $IMAGE" "podman run --rm $IMAGE echo ok   (read the error; is $STAGE/alpine.tar there?)"; fi
fi

# SELinux boolean for NFS
if [ "$(getsebool virt_use_nfs 2>/dev/null | awk '{print $3}')" = on ]; then pass SELinux "virt_use_nfs is on"
else warn SELinux "virt_use_nfs is off, so containers cannot use /shared" "sudo setsebool -P virt_use_nfs 1"; fi

# staged image
if [ -s "$STAGE/alpine.tar" ]; then pass "Offline image" "$STAGE/alpine.tar"
else warn "Offline image" "$STAGE/alpine.tar is missing" "run the provisioner on the login node"; fi

echo
if [ "$fails" -gt 0 ]; then echo "Result: NOT READY ($fails failed)"; exit 1; fi
echo "Result: CONTAINERS READY"
