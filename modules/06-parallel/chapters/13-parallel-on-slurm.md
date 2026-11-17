# Chapter 13 - OpenMP and Open MPI as Slurm jobs

About 45 minutes. You work on `login` as the user `alice`. Needs Chapters 7 (a working Slurm), 11 and 12.

Users do not run `mpirun` by hand on a cluster. They write a job script, `sbatch` it, and read the output file. Your job is to look at that script and its output and say **what kind of job it is** (OpenMP, MPI or hybrid), **where it ran** and **whether it got what it asked for**. In this chapter you submit one job of each kind and read a small picture of where each worker ran. You do not write any code: the programs are ready.

## What you will learn

- Tell OpenMP, MPI and hybrid jobs apart from the job script and from the output.
- Read the Slurm request (`--nodes`, `--ntasks`, `--cpus-per-task`) and say how many cores it reserves: nodes x tasks per node x CPUs per task.
- Check what Slurm really gave the job with `sacct`.
- See what happens when the thread or rank count does not match the request.

## The three jobs

| Job | Script | What it is | Shape |
|---|---|---|---|
| A | `job_omp.sh` | OpenMP | one process with 4 threads |
| B | `job_mpi.sh` | MPI | 4 separate ranks |
| C | `job_hybrid.sh` | Hybrid | 2 ranks, each with 2 threads |

Each program prints one line per worker (node, rank, thread, CPU). `show_map.sh` sorts those lines into a picture.

> **Lab size.** The lab has one compute node with one CPU, so every job asks Slurm for 1 CPU and starts more workers than that (threads, or `mpirun --oversubscribe`). The scripts carry a comment with the values you would use on a real cluster, for example `--nodes=2 --ntasks-per-node=2`. On real hardware the workers would sit on different CPUs and nodes; here they all show `cpu0` on `compute1`. The shape (process, rank, thread) is what you learn to read.

## Before you start

- Slurm works: `sinfo` shows `compute1` as `idle`, and `slurm-verify` is healthy.
- Both nodes are prepared for Chapters 11 and 12 (`parallel-verify` says `PARALLEL READY`).
- Snapshot: `vagrant snapshot save before-slurm-parallel`.
- On `login`, become alice and copy the lab into her home, which is on `/shared`, so `compute1` sees it:

  ```bash
  sudo -iu alice
  cp -r /vagrant/modules/06-parallel/lab ~/lab13 && cd ~/lab13
  ./build.sh
  ```

  You should see `Built: hello_omp  hello_mpi  hello_hybrid`.

## Part 1 - OpenMP job

First predict: read `job_omp.sh`. How many tasks? How many threads?

```bash
cat job_omp.sh
sbatch job_omp.sh
squeue                    # wait until the job leaves the list
./show_map.sh lab_omp_*.out
```

Expected:

```
  NODE compute1
    1 process  [t0 @cpu0] [t1 @cpu0] [t2 @cpu0] [t3 @cpu0]

  Workers: 4   Nodes: 1
  This looks like: OpenMP (threads in one process)
```

One node, one process, four threads. The thread count came from `OMP_NUM_THREADS` in the script, not from Slurm. Slurm reserved 1 CPU, so the four threads share it (on a real cluster you would see four different CPUs).

## Part 2 - MPI job

Predict: how many ranks? Is anything asked of Slurm about ranks?

```bash
sbatch job_mpi.sh
./show_map.sh lab_mpi_*.out
```

Expected:

```
  NODE compute1
    rank 0     [@cpu0]
    rank 1     [@cpu0]
    rank 2     [@cpu0]
    rank 3     [@cpu0]

  Workers: 4   Nodes: 1   Ranks: 4
  This looks like: MPI (separate ranks)
```

Four separate processes with no threads. The number of ranks came from `mpirun -np 4`. Slurm only allocated the node; on a real cluster it would also size the job through `--ntasks`, and `mpirun` would use that number by itself.

## Part 3 - Hybrid job

Predict: how many ranks, how many threads per rank, how many workers in total?

```bash
sbatch job_hybrid.sh
./show_map.sh lab_hybrid_*.out
```

Expected:

```
  NODE compute1
    rank 0     [t0 @cpu0] [t1 @cpu0]
    rank 1     [t0 @cpu0] [t1 @cpu0]

  Workers: 4   Nodes: 1   Ranks: 2   Threads per rank: 2
  This looks like: hybrid (MPI ranks, each with OpenMP threads)
```

MPI between the ranks, OpenMP inside each one.

If you ran the job scripts more than once, the `*` in `show_map.sh lab_omp_*.out` matches several files; name one file (for example `lab_omp_7.out`) instead.

## Part 4 - What did Slurm record?

```bash
sacct -j <jobid> --format=JobID,JobName,NNodes,NTasks,AllocCPUS,State
```

`AllocCPUS` is 1 for every job, although the pictures show 4, 4 and 4 workers. That gap is the point: Slurm reserved what the script asked for, and the program started more workers than that. On a real cluster this is the first thing to check when a user says their job is slow. Compare `AllocCPUS` with the number of threads or ranks the program started.

## Part 5 - Change one thing

Edit a script, resubmit and compare the picture with your guess.

| Try this | What you should notice |
|---|---|
| In `job_omp.sh` set `OMP_NUM_THREADS=2` | Two threads. The thread count is decided by this variable, not by Slurm. |
| In `job_omp.sh` remove the `export` line | One thread per CPU the node reports (the node has 1, so one thread). Run it on a bigger node and the program would start more threads than the job was given. |
| In `job_mpi.sh` change `-np 4` to `-np 2` | Two ranks. |
| In `job_mpi.sh` remove `--oversubscribe` | The job fails with "not enough slots": Slurm gave 1 slot and 4 ranks do not fit. Read the `.out` file; this message is what users send you. |
| In `job_hybrid.sh` remove `-x OMP_NUM_THREADS` | Each rank may use a different thread count, because the variable is not passed on to the ranks. |

## Write down what you found

| | Job A | Job B | Job C |
|---|---|---|---|
| Nodes | | | |
| Ranks (processes) | | | |
| Threads per rank | | | |
| CPUs Slurm reserved | | | |
| Model (OpenMP / MPI / hybrid) | | | |

## Clean up

```bash
cd ~ && rm -rf ~/lab13
exit
```

## Check yourself

<details><summary>1. A job script has <code>--cpus-per-task=8</code> and runs <code>./app</code>, with no <code>mpirun</code>. What do you expect?</summary>

OpenMP (or another threaded program): one process using up to 8 threads on one node. Confirm with `top -H` on the node, and check that `OMP_NUM_THREADS` matches the 8.
</details>

<details><summary>2. A job asks for <code>--nodes=2 --ntasks-per-node=4</code> and runs <code>mpirun ./app</code>. How many ranks and how many cores?</summary>

8 ranks (2 x 4) on 2 nodes, and 8 cores if each task has 1 CPU (`--cpus-per-task` is 1 by default).
</details>

<details><summary>3. Same job with <code>--cpus-per-task=4</code> added, and the program uses OpenMP inside. What is it, and how many cores?</summary>

Hybrid: 8 ranks with up to 4 threads each, 2 x 4 x 4 = 32 cores. The threads per rank should equal `--cpus-per-task`.
</details>

<details><summary>4. A user asks for 4 CPUs and the program starts 64 threads. Where do you see it?</summary>

`sacct` shows `AllocCPUS` 4, while `top -H` on the node shows 64 threads sharing those 4 CPUs. The fix is in the script: `OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK`.
</details>

<details><summary>5. A job fails with "not enough slots". What happened?</summary>

`mpirun` was asked for more ranks than the job has slots (CPUs). Either the script asks Slurm for too little or `-np` is too large.
</details>

## If you are stuck

- Job stays `PD`: run `why-pending <jobid>`. The jobs here ask for 1 CPU, so a pending job usually means Slurm itself is not healthy (`slurm-verify`).
- `show_map.sh` says "No MAP lines": the job has not finished or it failed; read the `.out` file for the first error.
- `mpirun` cannot start under Slurm (an error mentioning `srun` or `plm`): add `export OMPI_MCA_plm=rsh` before the `mpirun` line in the script and resubmit.
- `sbatch: error: Unable to open file`: you are not in `~/lab13`.
- To start over: `vagrant snapshot restore before-slurm-parallel`.

## Next

Chapter 8's `why-pending` pairs well with this one: submit a job that asks for 4 CPUs and see why it stays pending on a one-CPU node.
