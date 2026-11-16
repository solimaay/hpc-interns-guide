#!/usr/bin/env bash
# provision.sh (module 06-parallel) - get a lab node ready for the OpenMP and Open MPI chapters.
#
# Run it on every node:
#   vagrant provision login    --provision-with parallel
#   vagrant provision compute1 --provision-with parallel
#
# What it does:
#   - install a C compiler, Open MPI (runtime and development files) and environment-modules
#   - install parallel-verify
#
# Open MPI must be installed at the same path on every node, because mpirun starts the same
# program on each one. Safe to run more than once.
set -euo pipefail

log() { echo "[parallel] $*"; }

. /etc/hpc-lab-release

log "preparing $LAB_NODE ($LAB_ROLE)"

dnf -y install gcc make openmpi openmpi-devel environment-modules >/dev/null

install -m 0755 /vagrant/modules/06-parallel/bin/parallel-verify.sh /usr/local/bin/parallel-verify

log "done. Check with: parallel-verify"
