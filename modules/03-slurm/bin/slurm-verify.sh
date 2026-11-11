#!/usr/bin/env bash
# slurm-verify - check the Slurm build on this node.
#
#   slurm-verify      run it on the login node and on each compute node
#
# On the login node it also runs a small test job on every compute node.
# Exit code: 0 = no failures, 1 = at least one FAIL.
set -u

. /etc/hpc-lab-release 2>/dev/null || { echo "Not a lab node."; exit 1; }
CONF=/etc/slurm/slurm.conf

fails=0
pass() { printf '[PASS] %-16s %s\n' "$1" "$2"; }
fail() { printf '[FAIL] %-16s %s\n       -> %s\n' "$1" "$2" "$3"; fails=$((fails+1)); }

echo "Node: $LAB_NODE ($LAB_ROLE)"
echo

# accounts: the IDs must match on every node
for entry in slurm:2200 munge:2201; do
  user="${entry%%:*}"; uid="${entry##*:}"
  [ "$(id -u "$user" 2>/dev/null)" = "$uid" ] && pass "Account $user" "uid $uid" \
    || fail "Account $user" "missing or wrong uid (expected $uid)" "run the Slurm provisioner again"
done

# munge: can this node create and read a credential?
if munge -n 2>/dev/null | unmunge 2>/dev/null | grep -q 'STATUS:.*Success'; then pass munge "credential works"
else fail munge "munge -n | unmunge failed" "sudo systemctl enable --now munge; journalctl -u munge -n 20"; fi

# clock
[ "$(timedatectl show -p NTPSynchronized --value)" = yes ] && pass Clock synchronized \
  || fail Clock "not synchronized" "munge rejects credentials when clocks differ: sudo systemctl restart chronyd"

# slurm.conf
if [ ! -r "$CONF" ]; then
  fail slurm.conf "$CONF is missing" "copy /shared/slurm-lab/slurm.conf.template there and edit it"
elif grep -v '^#' "$CONF" | grep -q CHANGE_ME; then
  fail slurm.conf "still contains CHANGE_ME" "run 'slurmd -C' on a compute node and use its RealMemory"
else pass slurm.conf "found, CHANGE_ME replaced"; fi

# the daemon for this node
if [ "$LAB_ROLE" = login ]; then daemon=slurmctld; else daemon=slurmd; fi
systemctl is-active --quiet "$daemon" && pass "$daemon" running \
  || fail "$daemon" "not running" "journalctl -u $daemon -n 30; tail /var/log/slurm/$daemon.log"

# does this node reach the controller?
timeout 15 scontrol ping 2>/dev/null | grep -qi 'is UP' && pass Controller "scontrol ping works" \
  || fail Controller "cannot reach slurmctld" "is it running on login? same slurm.conf and munge key here?"

# login node only: every compute node is up, and a job runs on all of them
if [ "$LAB_ROLE" = login ] && command -v sinfo >/dev/null; then
  computes=""
  for pair in ${LAB_NODES//,/ }; do case "${pair%%=*}" in compute*) computes="$computes ${pair%%=*}" ;; esac; done
  for node in $computes; do
    state="$(sinfo -h -N -n "$node" -o '%t' 2>/dev/null | head -1)"
    case "$state" in
      idle|mix|alloc) pass "Node $node" "state $state" ;;
      *) fail "Node $node" "state '${state:-not listed}'" "scontrol show node $node | grep -i reason" ;;
    esac
  done
  n="$(echo $computes | wc -w)"
  got="$(timeout 120 srun -N "$n" -n "$n" hostname 2>/dev/null | sort | tr '\n' ' ')"   # stdout only: srun prints "queued and waiting" on stderr
  want="$(echo $computes | tr ' ' '\n' | sort | tr '\n' ' ')"
  [ "$got" = "$want" ] && pass "Test job" "srun ran on: $got" \
    || fail "Test job" "srun -N $n hostname gave: $got" "check the node states above and the slurmd logs"
fi

echo
if [ "$fails" -gt 0 ]; then echo "Result: NOT READY ($fails failed)"; exit 1; fi
echo "Result: SLURM LOOKS HEALTHY"
