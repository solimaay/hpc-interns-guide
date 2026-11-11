#!/usr/bin/env bash
# inject-fault - plant a practice problem on a lab node (run it with sudo).
#
#   sudo inject-fault random      plant a random problem (its name stays hidden)
#   sudo inject-fault <name>      plant a named one: disk-full, service-failed, locked-user
#   sudo inject-fault --ticket    show the user's complaint again
#   sudo inject-fault --check     is the problem fixed? (exit 0 yes, 1 no, 2 none planted)
#   sudo inject-fault --reveal    show what was planted and how to fix it
#   sudo inject-fault --revert    undo the problem
#
# Only on lab VMs. One problem at a time. The disk problem disappears at reboot.
set -u

STATE=/var/lib/hpc-lab/fault
SCENARIOS="disk-full service-failed locked-user"

die() { echo "inject-fault: $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "run it with sudo"
[ -r /etc/hpc-lab-release ] || die "this is not a lab node"
fn() { echo "${1//-/_}"; }   # disk-full -> disk_full (function names)
active() { cat "$STATE/active" 2>/dev/null; }

# ---- the three problems: ticket, solution, inject, check, revert ------------

ticket_disk_full()   { echo "The analysis application on this node cannot save its results: it reports 'No space left on device'. Nobody deleted anything. Please investigate (the application writes under /data/app)."; }
solution_disk_full() { echo "A large leftover file fills /data/app. Find it with 'df -h /data/app' and 'du -sh /data/app/*' (then into logs/), remove or truncate it, and confirm free space."; }
inject_disk_full() {
  mkdir -p /data/app
  dd if=/dev/zero of="$STATE/diskfull.img" bs=1M count=64 status=none || return 1
  mkfs.ext4 -q -F -m 0 "$STATE/diskfull.img" || return 1
  mount -o loop "$STATE/diskfull.img" /data/app || return 1
  mkdir -p /data/app/logs
  echo "mode: batch" > /data/app/config.yml
  fallocate -l 12M /data/app/logs/app-2026.log
  dd if=/dev/zero of=/data/app/logs/core.dump.tmp bs=1M status=none 2>/dev/null   # fills the rest
  chown -R carol:hpc-users /data/app
}
check_disk_full()  { mountpoint -q /data/app && [ "$(df -Pk /data/app | awk 'NR==2{print $4}')" -gt 10240 ]; }
revert_disk_full() { umount /data/app 2>/dev/null; rmdir /data/app 2>/dev/null; }

ticket_service_failed()   { echo "This node's clock is drifting and time synchronization looks broken: 'chronyc' cannot talk to the daemon, and the service will not stay up."; }
solution_service_failed() { echo "chronyd fails on a configuration error. Read 'systemctl status chronyd' and 'journalctl -u chronyd' to find the bad line in /etc/chrony.conf, fix it, and restart the service."; }
inject_service_failed() {
  cp -a /etc/chrony.conf "$STATE/chrony.conf.orig" || return 1
  sed -i 's/^driftfile/driftfle/' /etc/chrony.conf   # a typo chronyd refuses to start with
  systemctl restart chronyd >/dev/null 2>&1
  return 0
}
check_service_failed()  { systemctl is-active --quiet chronyd; }
revert_service_failed() { cp -a "$STATE/chrony.conf.orig" /etc/chrony.conf && systemctl restart chronyd; }

ticket_locked_user()   { echo "bob cannot log in on this node, although he is sure his password is correct."; }
solution_locked_user() { echo "bob's account is locked and expired on this node. Check 'passwd -S bob' and 'chage -l bob', then unlock it ('usermod -U bob') and clear the expiry ('usermod -e \"\" bob')."; }
inject_locked_user() { usermod -L -e 1 bob; }
check_locked_user() {
  [ "$(passwd -S bob | awk '{print $2}')" = PS ] && chage -l bob | grep 'Account expires' | grep -qi never
}
revert_locked_user() { usermod -U -e "" bob; }

# ---- commands -----------------------------------------------------------------

case "${1:-}" in
  --ticket)
    [ -f "$STATE/ticket" ] || { echo "No problem is planted on this node."; exit 2; }
    sed 's/^/  | /' "$STATE/ticket" ;;

  --check)
    s="$(active)"; [ -n "$s" ] || { echo "No problem is planted on this node."; exit 2; }
    if "check_$(fn "$s")"; then echo "FIXED: the problem is resolved."; exit 0; fi
    echo "NOT FIXED YET: the problem is still there."; exit 1 ;;

  --reveal)
    s="$(active)"; [ -n "$s" ] || { echo "No problem is planted on this node."; exit 2; }
    echo "Planted problem: $s"
    echo "How to fix it:   $(cat "$STATE/solution")" ;;

  --revert)
    s="$(active)"; [ -n "$s" ] || { echo "No problem is planted on this node."; exit 0; }
    "revert_$(fn "$s")" >/dev/null 2>&1
    rm -rf "$STATE"
    echo "The node is back to normal." ;;

  random|disk-full|service-failed|locked-user)
    [ -z "$(active)" ] || die "a problem is already planted. Fix it, or run: sudo inject-fault --revert"
    s="$1"
    if [ "$s" = random ]; then pool=($SCENARIOS); s="${pool[RANDOM % ${#pool[@]}]}"; fi
    mkdir -p "$STATE"; chmod 700 "$STATE"
    echo "$s" > "$STATE/active"
    if ! "inject_$(fn "$s")"; then
      "revert_$(fn "$s")" >/dev/null 2>&1; rm -rf "$STATE"
      die "could not plant the problem; the node was restored"
    fi
    "ticket_$(fn "$s")"   > "$STATE/ticket"
    "solution_$(fn "$s")" > "$STATE/solution"
    echo "A problem has been planted. Here is the ticket you received:"
    echo
    sed 's/^/  | /' "$STATE/ticket"
    echo
    echo "Investigate and fix it. Check your progress with: fault-status" ;;

  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
