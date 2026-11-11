#!/usr/bin/env bash
# node-health - one-screen health summary of the node you are on.
#
#   node-health
#
# Read-only. Each line is tagged [ OK ], [WARN], [FAIL] or [INFO]; the last line is the verdict.
# Exit code: 0 = no failures (warnings allowed), 1 = at least one failure.
set -u

nwarn=0; nfail=0
line() {  # line <tag> <label> <text>
  case "$1" in
    WARN) nwarn=$((nwarn+1)); tag="[WARN]" ;;
    FAIL) nfail=$((nfail+1)); tag="[FAIL]" ;;
    OK)   tag="[ OK ]" ;;
    *)    tag="[INFO]" ;;
  esac
  printf '%s %-12s %s\n' "$tag" "$2" "$3"
}

echo "Node health: $(hostname -s)   ($(date '+%F %T'))"
echo

# ---- Slurm view (only where Slurm is installed and knows this node) ----------
if command -v scontrol >/dev/null 2>&1; then
  state="$(scontrol show node "$(hostname -s)" 2>/dev/null | grep -o 'State=[^ ]*' | head -1 | cut -d= -f2)"
  case "$state" in
    "")                       line INFO "Slurm" "this node is not known to Slurm (normal for the login node)" ;;
    *DOWN*|*INVAL*|*UNK*)     line FAIL "Slurm state" "$state" ;;
    *DRAIN*)                  line WARN "Slurm state" "$state" ;;
    *)                        line OK   "Slurm state" "$state" ;;
  esac
else
  line INFO "Slurm" "not installed yet"
fi

# ---- load: busy CPUs, compared with the number of CPUs ----------------------
cpus="$(nproc)"; load="$(cut -d' ' -f1 /proc/loadavg)"
if   awk -v l="$load" -v c="$cpus" 'BEGIN {exit !(l > 2*c)}'; then line FAIL "Load" "$load on $cpus CPU(s): overloaded"
elif awk -v l="$load" -v c="$cpus" 'BEGIN {exit !(l > c)}';   then line WARN "Load" "$load on $cpus CPU(s)"
else line OK "Load" "$load on $cpus CPU(s)"; fi

# ---- memory: percent still available ----------------------------------------
pct="$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {print int(a*100/t)}' /proc/meminfo)"
if   [ "$pct" -lt 5 ];  then line FAIL "Memory" "only ${pct}% available"
elif [ "$pct" -lt 10 ]; then line WARN "Memory" "only ${pct}% available"
else line OK "Memory" "${pct}% available"; fi

# ---- disks: local filesystems that are nearly full --------------------------
full=0
while read -r use mount; do
  use="${use%\%}"
  if   [ "$use" -ge 98 ]; then line FAIL "Disk $mount" "${use}% full"; full=1
  elif [ "$use" -ge 90 ]; then line WARN "Disk $mount" "${use}% full"; full=1
  fi
done < <(df -P -l -x tmpfs -x devtmpfs | awk 'NR>1 {print $5, $6}')
[ "$full" -eq 0 ] && line OK "Disks" "no local filesystem is above 90% full"

# ---- shared storage must answer (5 s limit, so a hung NFS mount cannot block us) ----
for mount in $(findmnt -rn -t nfs,nfs4 -o TARGET); do
  if timeout 5 df -P "$mount" >/dev/null 2>&1; then line OK "Mount $mount" "responds"
  else line FAIL "Mount $mount" "does not answer within 5 s"; fi
done

# ---- services that exist on this node ---------------------------------------
services="sshd chronyd munge slurmd slurmctld"
[ "$(hostname -s)" = login ] && services="$services nfs-server"   # only the login node serves NFS
for svc in $services; do
  systemctl cat "$svc" >/dev/null 2>&1 || continue
  if systemctl is-active --quiet "$svc"; then line OK "Service" "$svc running"
  elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then line FAIL "Service" "$svc is enabled but not running"
  else line INFO "Service" "$svc is installed but disabled"; fi
done

# ---- clock -------------------------------------------------------------------
synced() { [ "$(timedatectl show -p NTPSynchronized --value)" = yes ]; }
synced || sleep 5   # right after chronyd restarts it needs a few seconds
if synced; then line OK "Clock" "synchronized"
else line WARN "Clock" "not synchronized"; fi

echo
if   [ "$nfail" -gt 0 ]; then echo "Verdict: PROBLEM ($nfail failed, $nwarn warnings)"; exit 1
elif [ "$nwarn" -gt 0 ]; then echo "Verdict: ATTENTION ($nwarn warnings)"
else echo "Verdict: HEALTHY"; fi
