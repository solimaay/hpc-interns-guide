#!/usr/bin/env bash
# provision.sh (module 03-slurm) - get a lab node ready for the "build Slurm" chapter.
#
# Run it on every node, login node first (the compute node fetches the munge key from it):
#   vagrant provision login    --provision-with slurm
#   vagrant provision compute1 --provision-with slurm
#
# It does NOT install or start Slurm; the learner does that. It does:
#   - enable the EPEL and CRB repositories
#   - login node: build the Slurm packages (RPMs) from the official source, once (~10 minutes),
#     into /shared/slurm-lab/rpms
#   - create the 'slurm' and 'munge' accounts with the same IDs on every node
#   - install munge with the SAME key on every node (not started)
#   - login node: write slurm.conf.template and README.txt (the checklist) to /shared/slurm-lab/
#
# Safe to run more than once.
set -euo pipefail

VERSION=26.05.5
SHA256=4680cafc82b0689865c885eb703441e7ebf764896c40fd03a50f2fcb60664f68   # from download.schedmd.com/slurm/SHA256

log() { echo "[slurm] $*"; }

. /etc/hpc-lab-release
STAGE="$LAB_SHARED/slurm-lab"
RPMS="$STAGE/rpms"
KEY=/etc/munge/munge.key

log "preparing $LAB_NODE ($LAB_ROLE)"

# ---- repositories -------------------------------------------------------------
dnf -y install dnf-plugins-core epel-release >/dev/null
dnf config-manager --set-enabled crb >/dev/null

# ---- Slurm RPMs: built once on the login node ----------------------------------
if [ "$LAB_ROLE" = login ]; then
  mkdir -p "$RPMS"
  if ls "$RPMS"/slurm-"$VERSION"-*.rpm >/dev/null 2>&1; then
    log "Slurm $VERSION packages already built (skipping the build)"
  else
    log "building Slurm $VERSION from source (about 10 minutes)"
    dnf -y install rpm-build gcc make autoconf automake python3 readline-devel munge-devel \
      pam-devel mariadb-devel http-parser-devel json-c-devel perl-ExtUtils-MakeMaker perl-devel \
      dbus-devel libbpf-devel kernel-headers systemd-devel pkgconf-pkg-config bzip2 curl >/dev/null
    BUILD="$(mktemp -d /var/tmp/slurm-build.XXXXXX)"
    tarball="slurm-$VERSION.tar.bz2"
    curl -fsSL --retry 3 -o "$BUILD/$tarball" "https://download.schedmd.com/slurm/$tarball"
    echo "$SHA256  $BUILD/$tarball" | sha256sum -c - >/dev/null   # stops here if the download is not the expected file
    rpmbuild -ta --without debug --define "_topdir $BUILD/rpmbuild" "$BUILD/$tarball" >"$BUILD/build.log" 2>&1 \
      || { tail -n 20 "$BUILD/build.log"; echo "Build failed. Full log: $BUILD/build.log"; exit 1; }
    cp "$BUILD"/rpmbuild/RPMS/*/*.rpm "$RPMS"/
    rm -rf "$BUILD"
    log "built the packages into $RPMS"
  fi
  chmod 755 "$STAGE" "$RPMS"; chmod 644 "$RPMS"/*.rpm
fi

# ---- accounts with identical IDs on every node --------------------------------
getent group slurm >/dev/null || groupadd -g 2200 slurm
id slurm >/dev/null 2>&1 || useradd -u 2200 -g slurm -M -s /sbin/nologin -d /var/lib/slurm slurm
getent group munge >/dev/null || groupadd -g 2201 munge
id munge >/dev/null 2>&1 || useradd -u 2201 -g munge -M -s /sbin/nologin -d /var/lib/munge munge

# ---- munge: installed, same key everywhere, not started -----------------------
dnf -y install munge munge-libs >/dev/null
if [ "$LAB_ROLE" = login ]; then
  [ -s "$KEY" ] || create-munge-key -f >/dev/null
  chown munge:munge "$KEY"; chmod 400 "$KEY"
  # Lab-only shortcut so the compute node can fetch the same key. A real cluster never leaves
  # the key readable on shared storage. The checklist tells learners to delete it afterwards.
  install -m 0644 "$KEY" "$STAGE/munge.key"
else
  [ -s "$STAGE/munge.key" ] || { echo "No munge key in $STAGE. Run this on the login node first."; exit 1; }
  install -m 0400 -o munge -g munge "$STAGE/munge.key" "$KEY"
fi
log "munge key in place (fingerprint $(sha256sum "$KEY" | cut -c1-12); it must match on every node)"

# ---- login node: template and checklist ---------------------------------------
if [ "$LAB_ROLE" = "login" ]; then
  cpus="$(nproc)"
  computes=(); lines=""
  IFS=',' read -ra pairs <<< "$LAB_NODES"
  for p in "${pairs[@]}"; do
    n="${p%%=*}"; ip="${p#*=}"
    case "$n" in compute*) computes+=("$n"); lines+="NodeName=$n NodeAddr=$ip CPUs=$cpus RealMemory=CHANGE_ME State=UNKNOWN"$'\n' ;; esac
  done
  nodelist="$(IFS=,; echo "${computes[*]}")"

  cat > "$STAGE/slurm.conf.template" <<EOF
# slurm.conf TEMPLATE for the lab. Copy to /etc/slurm/slurm.conf on EVERY node after you have
# replaced CHANGE_ME. Find RealMemory by running 'slurmd -C' on a compute node (it must not exceed
# what slurmd reports). The file must be identical on all nodes.
ClusterName=hpclab
SlurmctldHost=login
SlurmUser=slurm
SlurmctldPort=6817
SlurmdPort=6818
AuthType=auth/munge
MpiDefault=none
ProctrackType=proctrack/linuxproc
TaskPlugin=task/none
SwitchType=switch/none
ReturnToService=1
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory
StateSaveLocation=/var/spool/slurmctld
SlurmdSpoolDir=/var/spool/slurmd
SlurmctldPidFile=/var/run/slurm/slurmctld.pid
SlurmdPidFile=/var/run/slurm/slurmd.pid
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
AccountingStorageType=accounting_storage/none
JobAcctGatherType=jobacct_gather/none
# The lab has no mail system; without this slurmctld logs 'MailProg is invalid'
MailProg=/bin/true

# --- nodes (one line per compute node) ---
${lines}
# --- partition ---
PartitionName=debug Nodes=${nodelist} Default=YES MaxTime=INFINITE State=UP
EOF

  cat > "$STAGE/README.txt" <<EOF
CHECKLIST: build the Slurm cluster

Already done: the munge key (same on every node), the 'slurm' and 'munge' accounts, the
repositories, and the packages (in /shared/slurm-lab/rpms). slurm.conf.template is next to this file.

 1. Every node: start munge and test it.
        sudo systemctl enable --now munge
        munge -n | unmunge              (STATUS: Success)
 2. Install the packages with dnf, from /shared/slurm-lab/rpms: 'slurm' plus the
    controller package on login, and 'slurm' plus the node package on the compute node.
 3. On a compute node run 'slurmd -C' and read RealMemory.
 4. Every node: create /etc/slurm, copy slurm.conf.template to /etc/slurm/slurm.conf,
    and replace CHANGE_ME with that RealMemory (or a little less). The file must be identical everywhere.
 5. Every node: create the directories named in slurm.conf (spool, log, run) and
    give them to the 'slurm' user.
 6. Start slurmctld on login and slurmd on the compute node (enable them too).
 7. Check with: sinfo   srun -N1 hostname   slurm-verify

If something fails, read /var/log/slurm/ and 'journalctl -u slurmctld' (or slurmd).
The usual suspects: the clock, the munge key, name resolution.

When the chapter is done, delete the staged key:  sudo rm /shared/slurm-lab/munge.key
EOF
  chmod 644 "$STAGE/slurm.conf.template" "$STAGE/README.txt"
  log "wrote $STAGE/slurm.conf.template and $STAGE/README.txt"
fi

log "Slurm prep complete on $LAB_NODE."
[ "$LAB_ROLE" = login ] && log "Next: read $STAGE/README.txt"
exit 0
