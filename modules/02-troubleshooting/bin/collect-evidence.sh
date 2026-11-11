#!/usr/bin/env bash
# collect-evidence - gather the standard facts for a support ticket into one text file.
#
#   collect-evidence alice          facts about user alice on this node
#   collect-evidence alice 1234     ... plus Slurm details for job 1234
#
# The file is written to the current folder. Read-only: it changes nothing and collects
# system and account information, not file contents or passwords. Review it before sharing.
set -u

user="${1:-$(id -un)}"
job="${2:-}"
out="evidence-$(hostname -s)-$user-$(date +%Y%m%d-%H%M).txt"
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo -n"

# run <command...>: write the command and its output to the file
run() { { echo "\$ $*"; timeout 20 "$@" 2>&1; echo; } >> "$out"; }
section() { printf '\n=== %s ===\n' "$1" >> "$out"; }

: > "$out"
echo "Collected $(date '+%F %T') by $(id -un) on $(hostname -f)" >> "$out"

section "Account: $user"
run id "$user"
run getent passwd "$user"
run $SUDO chage -l "$user"
run $SUDO passwd -S "$user"

section "Storage"
run df -hT -x tmpfs -x devtmpfs
run df -i -x tmpfs -x devtmpfs
run findmnt -t nfs,nfs4

section "Node health"
run uptime
run free -h
run systemctl --failed --no-pager
run timedatectl

section "Recent warnings in the system log"
run journalctl -p warning --since "1 hour ago" --no-pager -n 30

if command -v squeue >/dev/null 2>&1; then
  section "Slurm"
  run sinfo -N
  run squeue -u "$user"
  if [ -n "$job" ]; then
    run scontrol show job "$job"
    run sacct -j "$job" --format=JobID,State,ExitCode,Elapsed,NodeList
  fi
fi

chmod 600 "$out"
echo "Evidence written to: $out"
echo "Review it, then attach or paste it into the ticket."
