#!/usr/bin/env bash
# lab-verify - health check for a lab node. Run it on every node: lab-verify
# Each line is PASS, WARN or FAIL, with a hint when something is wrong.
# Exit code: 0 = no failures, 1 = at least one FAIL.
set -u

. /etc/hpc-lab-release 2>/dev/null || { echo "Not a lab node: /etc/hpc-lab-release is missing."; exit 1; }

fails=0
pass() { printf '[PASS] %-12s %s\n' "$1" "$2"; }
fail() { printf '[FAIL] %-12s %s\n       -> %s\n' "$1" "$2" "$3"; fails=$((fails+1)); }
warn() { printf '[WARN] %-12s %s\n       -> %s\n' "$1" "$2" "$3"; }

echo "Node: $LAB_NODE ($LAB_ROLE, $LAB_IP)"
echo

# hostname and name resolution
[ "$(hostname -s)" = "$LAB_NODE" ] && pass Hostname "$LAB_NODE" \
  || fail Hostname "is $(hostname -s), expected $LAB_NODE" "sudo hostnamectl set-hostname $LAB_NODE"
for pair in ${LAB_NODES//,/ }; do
  name="${pair%%=*}"; ip="${pair#*=}"
  got="$(getent hosts "$name" | awk '{print $1; exit}')"
  if [ "$got" != "$ip" ]; then
    fail "Node $name" "resolves to '${got:-nothing}', expected $ip" "check /etc/hosts"
  elif ping -c1 -W2 "$ip" >/dev/null 2>&1; then
    pass "Node $name" "$ip answers ping"
  else
    fail "Node $name" "$ip does not answer ping" "is that VM running? (vagrant status)"
  fi
done

# clock
if [ "$(timedatectl show -p NTPSynchronized --value)" = yes ]; then pass Clock synchronized
else warn Clock "not synchronized" "sudo systemctl restart chronyd"; fi

# shared storage
if [ "$LAB_ROLE" = login ]; then
  systemctl is-active --quiet nfs-server && pass "NFS server" running \
    || fail "NFS server" "not running" "sudo systemctl enable --now nfs-server"
else
  findmnt -t nfs,nfs4 "$LAB_SHARED" >/dev/null && pass "NFS mount" "$LAB_SHARED mounted" \
    || fail "NFS mount" "$LAB_SHARED is not mounted" "sudo mount $LAB_SHARED (the login node must be up)"
fi
touch "$LAB_SHARED/scratch/.verify-$LAB_NODE" 2>/dev/null && pass "Shared write" "$LAB_SHARED/scratch is writable" \
  || fail "Shared write" "cannot write to $LAB_SHARED/scratch" "check the NFS mount and its permissions"

# users
for entry in alice:2001 bob:2002 carol:2003; do
  user="${entry%%:*}"; uid="${entry##*:}"
  [ "$(id -u "$user" 2>/dev/null)" = "$uid" ] && pass "User $user" "uid $uid" \
    || fail "User $user" "missing or wrong uid (expected $uid)" "vagrant provision $LAB_NODE"
done

echo
if [ "$fails" -gt 0 ]; then echo "Result: NOT HEALTHY ($fails failed)"; exit 1; fi
echo "Result: HEALTHY"
