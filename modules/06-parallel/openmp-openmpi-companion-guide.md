# OpenMP and Open MPI on the Cluster: Companion Guide

A plain-language guide to how programs run in parallel on a cluster: OpenMP (threads on one node), Open MPI (processes across nodes), and hybrid jobs that use both. It shows how a Slurm job asks for them and how to check on the node that they run the way the user thinks. It is complete on its own.

The aim is to **understand users and recognise what they are running**. You do not need to write parallel code. Where code appears, it is so you can recognise it when a user shows it to you.

> **Conventions.** `<angle brackets>` are values you replace. Module names, partitions and defaults differ from site to site, so treat every job script as a template. The OpenMP output was produced by running the lab programs (`hello.c`, `race.c`, `pi.c` from Chapter 11) on a 16-core machine; your numbers will differ, and the order of lines from a threaded program changes from run to run. The Open MPI, hybrid and `show_map.sh` outputs are the expected results from Chapters 12 and 13.

---

## Contents

1. [A ticket lands in your queue](#1-a-ticket-lands-in-your-queue)
2. [OpenMP: many threads, one process](#2-openmp-many-threads-one-process)
3. [Hello from many threads](#3-hello-from-many-threads)
4. [When threads collide: a race condition](#4-when-threads-collide-a-race-condition)
5. [The fix, and a test you can ask for](#5-the-fix-and-a-test-you-can-ask-for)
6. [Does it go faster?](#6-does-it-go-faster)
7. [Are the threads really running?](#7-are-the-threads-really-running)
8. [MPI: separate processes, messages](#8-mpi-separate-processes-messages)
9. [Hello from many ranks](#9-hello-from-many-ranks)
10. [Open MPI across nodes: what breaks](#10-open-mpi-across-nodes-what-breaks)
11. [Hybrid: MPI plus OpenMP](#11-hybrid-mpi-plus-openmp)
12. [Three layouts in a Slurm script](#12-three-layouts-in-a-slurm-script)
13. [An OpenMP job script, line by line](#13-an-openmp-job-script-line-by-line)
14. [Reading a job: three pictures](#14-reading-a-job-three-pictures)
15. [Tell the three apart](#15-tell-the-three-apart)
16. [What users say, and what you ask](#16-what-users-say-and-what-you-ask)
17. [Practice: what do you say?](#17-practice-what-do-you-say)
18. [Rules of thumb](#18-rules-of-thumb)
19. [Where to go next](#19-where-to-go-next)

---

## 1. A ticket lands in your queue

A user writes:

> "I asked for 64 cores, but my job is slower than it was with 16. What is wrong?"

You do not need to write parallel code to help. You need to recognise what kind of program it is, and ask for the right facts. After reading this guide you can:

1. Tell OpenMP from MPI: threads in one process, or ranks that pass messages.
2. Read a job script and say how many threads, ranks and cores it asks for.
3. Check on the node whether the work runs where the user thinks.

---

## 2. OpenMP: many threads, one process

A program starts as one **main thread**. When it reaches a **parallel region**, it **forks** a team of threads. They all work, then **join** back into one thread.

```
                 parallel region
              +--> thread 0 --+
              +--> thread 1 --+
main thread --+--> thread 2 --+--> main thread
   (fork)     +--> thread 3 --+     (join)

  Shared memory: all threads read and write the same variables
```

Three facts to remember:

| Fact | What it means for support |
|---|---|
| **One process, many threads** | In the C code it starts with `#pragma omp parallel` (in Fortran, `!$omp`). |
| **Shared memory** | Handing data between threads is fast, but two threads can collide on the same variable (section 4). |
| **One node only** | All threads live in one process, so they run on one machine. OpenMP cannot spread a program over several nodes. |

Think of one kitchen where several cooks share a single workbench.

---

## 3. Hello from many threads

```c
#include <stdio.h>
#include <omp.h>

int main(void) {
    #pragma omp parallel
    {
        printf("hello from thread %d of %d\n",
               omp_get_thread_num(), omp_get_num_threads());
    }
    return 0;
}
```

Compile and run:

```bash
gcc -fopenmp hello.c -o hello
OMP_NUM_THREADS=4 ./hello
```

Two runs of the same program:

```
# run 1                          # run 2
hello from thread 0 of 4         hello from thread 2 of 4
hello from thread 1 of 4         hello from thread 1 of 4
hello from thread 2 of 4         hello from thread 3 of 4
hello from thread 3 of 4         hello from thread 0 of 4
```

- **`-fopenmp` switches the pragmas on.** Without it the compiler ignores them and the program runs on one thread. (In this particular program, leaving it out even fails to link, because `omp_get_thread_num` is missing. In other programs it just runs on one thread, with no message.)
- **`OMP_NUM_THREADS` sets the thread count.** If it is not set, OpenMP usually starts one thread per CPU the process can see. On the 16-core test machine that gave 16 threads. The same program limited to one CPU with `taskset -c 0` gave 1.
- **The order changes.** Threads run at the same time and nobody controls who prints first. This is also the reason the next example goes wrong.

---

## 4. When threads collide: a race condition

Add the numbers 1 to 1,000,000. The right answer is `500000500000`.

```c
long sum = 0;
#pragma omp parallel for
for (long i = 1; i <= 1000000; i++)
    sum += i;               // all threads update the same variable
```

| threads | run 1 | run 2 |
|---:|---|---|
| 1 | `500000500000` | `500000500000` |
| 2 | `125000250000` | `225288482527` |
| 4 | `110525487369` | `91510999175` |
| 8 | `112853147514` | `95252000144` |

Every thread updates the same variable `sum`. Two threads read it at the same time, each adds its number, and each writes it back, so one of the two additions is lost. With a million additions, a large part is lost. This is a **race condition**: the result depends on timing.

It is the worst kind of bug because the program **does not crash and prints no error**. It just gives wrong numbers. The ticket says:

> "The answer changes when I change the number of threads, or between runs."

That sentence should make you think *race condition*.

---

## 5. The fix, and a test you can ask for

One extra clause fixes the loop:

```c
#pragma omp parallel for reduction(+:sum)
for (long i = 1; i <= 1000000; i++)
    sum += i;
```

With `reduction`, each thread keeps its own private `sum`, and OpenMP adds them up at the end. Nothing is lost:

```
threads=1  sum = 500000500000
threads=2  sum = 500000500000
threads=4  sum = 500000500000
threads=8  sum = 500000500000
```

**What the desk can do.** You do not fix the code. You ask the user to run the same input both ways and compare:

```bash
OMP_NUM_THREADS=1 ./app > one.txt
OMP_NUM_THREADS=8 ./app > eight.txt
diff one.txt eight.txt
```

- **Clearly different results:** suspect a race. Pass it to the HPC team with both outputs.
- **Only tiny last-digit differences** in decimal numbers can be normal rounding. Adding in a different order changes the last digits. A big difference is not normal.

---

## 6. Does it go faster?

Time to compute pi with `pi.c` (400 million steps), in seconds. Lower is better.

| Threads | Time (s) |
|---:|---:|
| 1 | 0.37 |
| 2 | 0.18 |
| 4 | 0.10 |
| 8 | 0.05 |
| 4 threads limited to **1 CPU** | 0.38 |

With 8 threads the program is about 7 times faster, because every thread has its own core and the work splits cleanly. With 4 threads squeezed onto 1 CPU there is **no gain**: the threads take turns, and switching between them costs a little. This is what the lab virtual machines show, because each has one CPU.

The lesson is not "OpenMP is slow". It is **threads only help when each one gets a core.**

---

## 7. Are the threads really running?

On the compute node, `top -H` lists every thread of a process on its own line:

```bash
top -H -p $(pgrep -n pi)       # -H shows one line per thread
```

**4 threads, 4 free CPUs.** About 100% each is healthy: four threads keep four cores busy.

```
  PID S  %CPU COMMAND
748412 R  99.9 pi
748415 R  99.9 pi
748416 R  99.9 pi
748414 R  90.0 pi
```

**4 threads, 1 CPU.** Added up, about 100% is a problem: the four threads share one CPU, so the job uses one core only.

```
  PID S  %CPU COMMAND
748490 R  30.0 pi
748492 R  20.0 pi
748493 R  20.0 pi
748494 R  20.0 pi
```

These two captures are real: the same program, started once normally and once limited to one CPU with `taskset`. In a Slurm job the cgroup does the limiting instead of `taskset`, with the same visible effect.

Count the threads of a process: `ps -o nlwp= -p <pid>`. A serial program shows `1`.

---

## 8. MPI: separate processes, messages

MPI (Message Passing Interface) starts several separate copies of the same program, called **ranks**. Each rank has its **own memory**, so ranks cannot see each other's variables. They send **messages** instead (`MPI_Send`, `MPI_Recv`). Because they are separate processes, ranks can run on different nodes. Open MPI is the MPI implementation Rocky Linux ships. Others exist, such as MPICH and Intel MPI.

```
   node 0                               node 1
 +---------------------------+        +---------------------------+
 | [rank 0]       [rank 1]   | <----> | [rank 2]       [rank 3]   |
 |  own memory     own memory|messages|  own memory     own memory|
 +---------------------------+        +---------------------------+
```

| | OpenMP | MPI (Open MPI) |
|---|---|---|
| Workers | Threads in one process | Separate processes (ranks) |
| Memory | Shared by all threads | Separate for each rank |
| Runs on | One node only | One node or many nodes |
| In the code | `#pragma omp ...` | `MPI_Init`, `MPI_Send` ... |
| Started with | `OMP_NUM_THREADS=8 ./app` | `mpirun -np 8 ./app` |

**Do not mix up the names.** *OpenMP* is threads inside one node. *Open MPI* is one implementation of MPI. They are different things with almost the same name.

---

## 9. Hello from many ranks

```c
#include <stdio.h>
#include <mpi.h>

int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);
    int rank, size, len;
    char node[MPI_MAX_PROCESSOR_NAME];
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Get_processor_name(node, &len);
    printf("hello from rank %d of %d on %s\n", rank, size, node);
    MPI_Finalize();
    return 0;
}
```

- `MPI_Init` starts MPI. `MPI_Comm_rank` gives this process its number (0 to N-1). `MPI_Comm_size` says how many ranks there are. The rank number is how each copy decides which part of the work is its own.
- `mpicc` is `gcc` with the MPI include and library flags added.
- `mpirun` starts the ranks.

```bash
mpicc hello.c -o hello
mpirun --hostfile hosts -np 2 ./hello
```

Expected output from the lab nodes (one line from each node; the order can vary):

```
hello from rank 0 of 2 on login
hello from rank 1 of 2 on compute1
```

**Not enough slots?** Open MPI counts one slot per CPU. Asking for more ranks than slots stops with an error. That is not a fault: it protects real clusters from overloading a node. Ask for fewer ranks, or for more cores. For a test only, `--oversubscribe` overrides it.

> Unlike the OpenMP output earlier, the Open MPI and hybrid outputs in this guide are the expected results from the lab chapters, not captures from a particular run.

---

## 10. Open MPI across nodes: what breaks

`mpirun` reaches the other nodes by logging in over SSH and starting the ranks there. So every node needs three things: the program at the **same path** (the lab uses shared storage), a way to **log in without a password**, and Open MPI on its **PATH**.

A hostfile lists the nodes and how many ranks each can take:

```
$ cat hosts
login    slots=1
compute1 slots=1
$ mpirun --prefix /usr/lib64/openmpi \
      --hostfile hosts -np 2 ./hello
```

The three usual failures, with the symptom a user pastes into the ticket:

| Symptom | Cause | Fix |
|---|---|---|
| A password prompt, or "unable to reliably start daemons" | `mpirun` logs in over SSH and cannot type a password | Key-based login to every node: `ssh node hostname` must just work |
| "cannot find `orted`" on the other node | SSH starts a shell that has not loaded the module, so Open MPI is not in its `PATH` | `--prefix /usr/lib64/openmpi`, or set `PATH` for non-login shells |
| It hangs, or "connection refused" | The ranks picked the wrong network interface (the lab VMs have two) | Set `OMPI_MCA_btl_tcp_if_include` (and `OMPI_MCA_oob_tcp_if_include`) to the cluster network |

First check for any "mpirun hangs" ticket: `ssh` to each node and run `hostname`. If that asks for a password, stop there.

---

## 11. Hybrid: MPI plus OpenMP

Real jobs often combine both: **MPI between nodes**, **OpenMP threads inside each rank**. Fewer ranks means less duplicated data per node and fewer messages to send.

```
node 0 (login)                 node 1 (compute1)
+----------------------+       +----------------------+
| rank 0 (MPI)         | <---> | rank 1 (MPI)         |
|   [t0]   [t1]        |       |   [t0]   [t1]        |
|   2 OpenMP threads   |       |   2 OpenMP threads   |
+----------------------+       +----------------------+
```

```bash
mpicc -fopenmp hybrid.c -o hybrid
mpirun -np 2 -x OMP_NUM_THREADS=2 ./hybrid
```

Expected output (order varies):

```
rank 0, thread 0 of 2, on login
rank 0, thread 1 of 2, on login
rank 1, thread 0 of 2, on compute1
rank 1, thread 1 of 2, on compute1
```

- **`ranks × threads` = the CPUs you were given.** Otherwise the node is overloaded. Here: 2 ranks × 2 threads = 4 CPUs.
- `-x` copies an environment variable to every rank. Without it a rank on another node may not see `OMP_NUM_THREADS`.
- **How to recognise it:** several tasks, more than one `cpus-per-task`, and `OMP_NUM_THREADS` set.

---

## 12. Three layouts in a Slurm script

| | Pure MPI | Pure OpenMP | Hybrid |
|---|---|---|---|
| `--nodes` | 2 | 1 | 2 |
| `--ntasks` / `--ntasks-per-node` | `--ntasks-per-node=2` | `--ntasks=1` | `--ntasks-per-node=1` |
| `--cpus-per-task` | 1 | 4 | 4 |
| Environment | | `export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK` | `export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK` |
| Run line | `mpirun ./hello_mpi` | `./hello_omp` | `mpirun ./hybrid` |
| Cores reserved | 2 × 2 × 1 = **4** | 1 × 1 × 4 = **4** | 2 × 1 × 4 = **8** |
| Shape | 4 ranks, one core each | one task, 4 threads | 2 ranks × 4 threads |

**Cores reserved = nodes × tasks per node × cpus-per-task.** Tasks are MPI ranks. `cpus-per-task` is the OpenMP threads of each rank.

Some sites start MPI with `srun ./app` instead of `mpirun ./app`. Follow the site's instructions.

The lab scripts differ on purpose: the lab node has 1 CPU, so they ask Slurm for 1 and start more workers (`--oversubscribe` for MPI). Their comments show the real-cluster values from this table.

---

## 13. An OpenMP job script, line by line

```bash
#!/bin/bash
#SBATCH --job-name=omp_pi
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:05:00
#SBATCH --output=omp_%j.out

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
./pi
```

| # | Line | What it does |
|---|---|---|
| 1 | `--nodes=1 --ntasks=1` | One node, one process. OpenMP cannot span nodes. |
| 2 | `--cpus-per-task=4` | The cores Slurm reserves: room for 4 threads. |
| 3 | `export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK` | Tells OpenMP to use exactly that many threads. Slurm provides the variable. |
| 4 | `./pi` | A plain run line. No `mpirun` needed. |

**Cores reserved = nodes × tasks × cpus-per-task = 1 × 1 × 4 = 4.**

If the script does not set `OMP_NUM_THREADS`, OpenMP picks its own number, which may not be what was reserved.

> **Lab note.** The lab virtual machine has 1 CPU, so `job_omp.sh` asks for 1 and sets `OMP_NUM_THREADS=4` on purpose, to show the shape of the job. Its own comment shows the real-cluster values used here.

---

## 14. Reading a job: three pictures

The lab script `show_map.sh` prints where each worker ran. Expected output from Chapter 13, on the 1-CPU lab VM (so every worker is on `cpu0`; on a real cluster they would sit on different CPUs and nodes):

**A. OpenMP: one process, four threads**

```
  NODE compute1
    1 process  [t0 @cpu0] [t1 @cpu0] [t2 @cpu0] [t3 @cpu0]

  This looks like: OpenMP (threads in one process)
```

**B. MPI: four ranks, no threads**

```
  NODE compute1
    rank 0     [@cpu0]
    rank 1     [@cpu0]
    rank 2     [@cpu0]
    rank 3     [@cpu0]

  This looks like: MPI (separate ranks)
```

**C. Hybrid: two ranks, two threads each**

```
  NODE compute1
    rank 0     [t0 @cpu0] [t1 @cpu0]
    rank 1     [t0 @cpu0] [t1 @cpu0]

  This looks like: hybrid (MPI ranks, each with OpenMP threads)
```

A job has two numbers to compare:

| What Slurm **reserved** | What the program **started** |
|---|---|
| `sacct -j <jobid> --format=JobID,NNodes,AllocCPUS,State` | `top -H -p <pid>` (threads), `ps -ef \| grep <app>` (ranks) |

In the lab, `AllocCPUS` is 1 while the pictures show 4 workers. On a real cluster the common problem is a script that reserves 4 CPUs while the program starts more workers than that. The fix is always the same: set `OMP_NUM_THREADS` from `SLURM_CPUS_PER_TASK`, and make `-np` match the tasks.

---

## 15. Tell the three apart

| | OpenMP | MPI | Hybrid |
|---|---|---|---|
| **Job script** | One task, `--cpus-per-task` above 1, `OMP_NUM_THREADS` | `--ntasks` or `--ntasks-per-node` above 1 | Several tasks and `--cpus-per-task` above 1 |
| **Run line** | `./app` | `mpirun ./app` (or `srun`) | `mpirun ./app` with `OMP_NUM_THREADS` |
| **Compile** | `gcc -fopenmp` (`-qopenmp` Intel) | `mpicc`, `mpicxx`, `mpif90` | `mpicc -fopenmp` |
| **In the code** | `#pragma omp`, `omp.h` | `mpi.h`, `MPI_Init` | Both |
| **On the node** | `top -H`: one process, many threads | `ps`: many processes of the same program | Several processes, each with several threads |

**Hidden OpenMP.** Libraries such as BLAS (used by NumPy) can use OpenMP threads with no pragma in the user's code. `mpi4py` means MPI.

---

## 16. What users say, and what you ask

| The user says | It may point to | You ask for or check |
|---|---|---|
| "My program ignores the cores" | No `-fopenmp`, `OMP_NUM_THREADS=1` or unset, or `--cpus-per-task=1` | Compile line, job script, `top -H` on the node |
| "The answer changes between runs" | A race condition on shared data (OpenMP) | A run with `OMP_NUM_THREADS=1` and one with several. Compare |
| "64 cores, but slower than 16" | More threads or ranks than cores, or work that does not split | Threads vs `--cpus-per-task`, ranks vs `--ntasks`. Timings at 16, 32, 64 |
| "I asked for 2 nodes, only 1 is busy" | OpenMP or serial code stays on one node. MPI needs `mpirun` or `srun` | The run line. Is it MPI? |
| "mpirun: not enough slots" | More ranks than the job has CPUs | `-np` vs `--ntasks`, and the cores reserved |
| "mpirun hangs, no output" | On several nodes: SSH, wrong network, program path | `ssh node hostname`, the interface setting, the same path |

**Always add to the ticket:** the job ID, the job script as submitted, what `sacct` says was allocated, and the last lines of output. A ticket with these four facts can be picked up by the HPC team without going back to the user.

---

## 17. Practice: what do you say?

**A.** "I set `OMP_NUM_THREADS=32`, but my script has `--cpus-per-task=4`. The job is slow."

**B.** "With 1 thread the total is 1000. With 8 threads it is 874, and 912 the next time."

**C.** "`mpirun -np 4 ./app` says there are not enough slots. The node has 1 CPU."

Try each one before reading on: what kind of problem is it, and what do you ask for first?

<details><summary>Answers</summary>

**A. Threads exceed cores.** 32 threads share 4 CPUs. Match the thread count to the cores asked for, or ask for more cores.

**B. Looks like a race.** The result changes with the thread count and between runs. Reproduce with 1 and 8 threads, keep both outputs, and pass it to the HPC team or the code owner. You do not need to find the bug.

**C. Not a fault.** Open MPI counts one slot per CPU. Ask for fewer ranks or more cores. `--oversubscribe` is for tests only.
</details>

---

## 18. Rules of thumb

1. OpenMP = threads in one process, on one node. MPI = ranks passing messages, on one node or many.
2. Cores reserved = nodes × tasks per node × cpus-per-task. Threads = `cpus-per-task`.
3. Compile with `-fopenmp` or `mpicc`. Check with `top -H` or `ps`.
4. OpenMP answer changes with the thread count? Think race. Test with 1 thread.
5. `mpirun` across nodes needs SSH keys, the same program path and the right network.

---

## 19. Where to go next

- **Hands-on:** [Chapter 11](chapters/11-openmp.md) (OpenMP, about 1 hour), [Chapter 12](chapters/12-openmpi.md) (Open MPI, about 1.5 hours) and [Chapter 13](chapters/13-parallel-on-slurm.md) (both as Slurm jobs, about 45 minutes).
- **Going deeper (optional):** the limits of speedup, pinning threads and ranks to cores (affinity), and hyperthreading versus physical cores.
