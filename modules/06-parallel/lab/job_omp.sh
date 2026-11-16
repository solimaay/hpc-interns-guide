#!/bin/bash
#SBATCH --job-name=lab_omp
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:02:00
#SBATCH --output=lab_omp_%j.out

# OpenMP: ONE task, several threads, one node.
# The lab nodes have a single CPU, so we ask for 1 and start 4 threads to see the shape.
# On a real cluster: --cpus-per-task=4 and  export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_NUM_THREADS=4
./hello_omp
