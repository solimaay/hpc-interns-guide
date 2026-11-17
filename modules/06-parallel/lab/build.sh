#!/bin/bash
# build.sh - build the three Chapter 13 programs. Run it in this folder, once.
set -e
[ -r /etc/profile.d/modules.sh ] && . /etc/profile.d/modules.sh
module load mpi/openmpi-x86_64 2>/dev/null || echo "note: module load failed; using /usr/lib64/openmpi/bin"
export PATH=/usr/lib64/openmpi/bin:$PATH

gcc   -fopenmp hello_omp.c    -o hello_omp
mpicc          hello_mpi.c    -o hello_mpi
mpicc -fopenmp hello_hybrid.c -o hello_hybrid

echo "Built: hello_omp  hello_mpi  hello_hybrid"
