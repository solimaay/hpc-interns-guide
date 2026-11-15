#!/usr/bin/env bash
# provision.sh (module 05-containers) - get a lab node ready for the containers chapter.
#
# Run it on every node, login node first (it stages the practice image on shared storage):
#   vagrant provision login    --provision-with containers
#   vagrant provision compute1 --provision-with containers
#
# What it does:
#   - install Podman (Rocky AppStream) and Apptainer (EPEL, for the optional last part)
#   - give the 'vagrant' user a subordinate UID/GID range, which rootless Podman needs
#   - allow containers to read NFS (SELinux boolean virt_use_nfs)
#   - login node: pull the practice image once and save it to /shared/containers-lab/alpine.tar,
#     the offline fallback for learners who cannot reach a registry
#   - install container-verify (for labs built before this module existed)
#
# Safe to run more than once.
set -euo pipefail

IMAGE=docker.io/library/alpine:3.20

log() { echo "[containers] $*"; }

. /etc/hpc-lab-release
STAGE="$LAB_SHARED/containers-lab"

log "preparing $LAB_NODE ($LAB_ROLE)"

# ---- packages -----------------------------------------------------------------
dnf -y install podman shadow-utils >/dev/null
dnf -y install epel-release >/dev/null
dnf -y install apptainer >/dev/null || log "WARNING: Apptainer not installed; only the optional part needs it"

# ---- rootless Podman: subordinate IDs for the learner account ----------------
for u in vagrant; do
  grep -q "^$u:" /etc/subuid 2>/dev/null || usermod --add-subuids 100000-165535 "$u"
  grep -q "^$u:" /etc/subgid 2>/dev/null || usermod --add-subgids 100000-165535 "$u"
done

# ---- SELinux: let containers use NFS (needed to mount /shared into a container) ----
setsebool -P virt_use_nfs 1

# ---- login node: stage the practice image for offline use --------------------
if [ "$LAB_ROLE" = login ]; then
  mkdir -p "$STAGE"
  if [ -s "$STAGE/alpine.tar" ]; then
    log "practice image already staged (skipping the pull)"
  else
    log "pulling $IMAGE"
    podman pull -q "$IMAGE" >/dev/null
    podman save -o "$STAGE/alpine.tar" "$IMAGE"
  fi
  chmod 755 "$STAGE"; chmod 644 "$STAGE/alpine.tar"
fi

# ---- the check tool -----------------------------------------------------------
install -m 0755 /vagrant/modules/05-containers/bin/container-verify.sh /usr/local/bin/container-verify

log "done. Check with: container-verify"
