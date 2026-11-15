#!/usr/bin/env bash
# parallel-verify - check that this node is ready for the OpenMP and Open MPI chapters.
#
#   parallel-verify      run it on every node (any user)
#
# Each line is PASS, WARN or FAIL, with a hint when something is wrong.
# Exit code: 0 = no failures, 1 = at least one FAIL.
set -u

. /etc/hpc-lab-release 2>/dev/null || { echo "Not a lab node."; exit 1; }
MPI_HOME=/usr/lib64/openmpi

fails=0
pass() { printf '[PASS] %-12s %s\n' "$1" "$2"; }
fail() { printf '[FAIL] %-12s %s\n       -> %s\n' "$1" "$2" "$3"; fails=$((fails+1)); }
warn() { printf '[WARN] %-12s %s\n       -> %s\n' "$1" "$2" "$3"; }

echo "Node: $LAB_NODE ($LAB_ROLE), user $(id -un)"
echo

hint="run the provisioner: vagrant provision $LAB_NODE --provision-with parallel"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# compiler with OpenMP support
if command -v gcc >/dev/null; then
  printf '#include <omp.h>\nint main(void){return omp_get_max_threads()<1;}\n' > "$tmp/o.c"
  if gcc -fopenmp "$tmp/o.c" -o "$tmp/o" 2>/dev/null && "$tmp/o"; then pass "OpenMP" "$(gcc --version | head -1)"
  else fail "OpenMP" "gcc cannot build or run an OpenMP program" "$hint"; fi
else fail "OpenMP" "gcc is not installed" "$hint"; fi

# Open MPI installed where the chapter expects it
if [ -x "$MPI_HOME/bin/mpirun" ] && [ -x "$MPI_HOME/bin/mpicc" ]; then
  pass "Open MPI" "$("$MPI_HOME/bin/mpirun" --version 2>&1 | head -1)"
else fail "Open MPI" "mpirun or mpicc missing under $MPI_HOME/bin" "$hint"; fi

# an MPI program builds and runs on this node (one rank is enough; no network needed)
if [ -x "$MPI_HOME/bin/mpicc" ]; then
  printf '#include <mpi.h>\nint main(int c,char**v){MPI_Init(&c,&v);MPI_Finalize();return 0;}\n' > "$tmp/m.c"
  if "$MPI_HOME/bin/mpicc" "$tmp/m.c" -o "$tmp/m" 2>/dev/null && \
     "$MPI_HOME/bin/mpirun" --oversubscribe -np 1 "$tmp/m" >/dev/null 2>&1; then pass "MPI run" "built and ran a 1-rank MPI program"
  else fail "MPI run" "could not build or run an MPI program" "$MPI_HOME/bin/mpicc and mpirun --oversubscribe -np 1 on a tiny program; read the error"; fi
fi

# environment modules
if [ -r /etc/profile.d/modules.sh ] && bash -lc 'module avail 2>&1' | grep -q 'mpi/openmpi'; then pass "Modules" "mpi/openmpi-x86_64 is available"
else warn "Modules" "the mpi/openmpi module is not listed" "log in again, or run the provisioner; the chapter can use $MPI_HOME/bin directly"; fi

# the other node must be reachable by name (mpirun starts programs there over SSH)
other=$(echo "${LAB_NODES//,/ }" | tr ' ' '\n' | cut -d= -f1 | grep -vx "$LAB_NODE" | head -1)
if [ -n "$other" ]; then
  if getent hosts "$other" >/dev/null; then pass "Peer name" "$other resolves"
  else fail "Peer name" "$other does not resolve" "run lab-verify and fix /etc/hosts (Chapter 5)"; fi
fi

echo
if [ "$fails" -gt 0 ]; then echo "Result: NOT READY ($fails failed)"; exit 1; fi
echo "Result: PARALLEL READY"
