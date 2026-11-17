#!/bin/bash
#SBATCH --job-name=lab_hybrid
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:02:00
#SBATCH --output=lab_hybrid_%j.out

# Hybrid: 2 MPI ranks, each with 2 OpenMP threads.
# On a real cluster: --nodes=2 --ntasks-per-node=2 --cpus-per-task=2,
#   export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK  and run  mpirun ./hello_hybrid
[ -r /etc/profile.d/modules.sh ] && . /etc/profile.d/modules.sh
module load mpi/openmpi-x86_64 2>/dev/null || export PATH=/usr/lib64/openmpi/bin:$PATH
export OMP_NUM_THREADS=2
mpirun --oversubscribe -np 2 -x OMP_NUM_THREADS ./hello_hybrid
