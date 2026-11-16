#!/bin/bash
#SBATCH --job-name=lab_mpi
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:02:00
#SBATCH --output=lab_mpi_%j.out

# MPI: several separate ranks. We ask Slurm for 1 CPU (all the lab node has) and let mpirun
# start 4 ranks anyway (--oversubscribe).
# On a real cluster: --nodes=2 --ntasks-per-node=2, and run  mpirun ./hello_mpi  (no -np, no --oversubscribe)
[ -r /etc/profile.d/modules.sh ] && . /etc/profile.d/modules.sh
module load mpi/openmpi-x86_64 2>/dev/null || export PATH=/usr/lib64/openmpi/bin:$PATH
mpirun --oversubscribe -np 4 ./hello_mpi
