# OpenMP on the Cluster: Companion Guide

A plain-language guide to OpenMP: what it is, how a Slurm job asks for it, and how to check on the node that it really runs the way the user thinks. It is complete on its own.

The aim is to **understand users and recognise what they are running**. You do not need to write parallel code. Where code appears, it is so you can recognise it when a user shows it to you.

> **Conventions.** `<angle brackets>` are values you replace. Module names, partitions and defaults differ from site to site, so treat every job script as a template. All program output below was produced by running the lab programs (`hello.c`, `race.c`, `pi.c`, `hello_omp.c` from Chapters 11 and 13) on a 16-core machine. Your numbers will differ, and the order of lines from a threaded program changes from run to run.

---

## Contents

1. [A ticket lands in your queue](#1-a-ticket-lands-in-your-queue)
2. [OpenMP: many threads, one process](#2-openmp-many-threads-one-process)
3. [Hello from many threads](#3-hello-from-many-threads)
4. [When threads collide: a race condition](#4-when-threads-collide-a-race-condition)
5. [The fix, and a test you can ask for](#5-the-fix-and-a-test-you-can-ask-for)
6. [Does it go faster?](#6-does-it-go-faster)
7. [Are the threads really running?](#7-are-the-threads-really-running)
8. [An OpenMP job script, line by line](#8-an-openmp-job-script-line-by-line)
9. [Reserved vs started: compare two numbers](#9-reserved-vs-started-compare-two-numbers)
10. [What users say, and what you ask](#10-what-users-say-and-what-you-ask)
11. [Practice: what do you say?](#11-practice-what-do-you-say)
12. [Rules of thumb](#12-rules-of-thumb)
13. [Where to go next](#13-where-to-go-next)

---

## 1. A ticket lands in your queue

A user writes:

> "I asked for 64 cores, but my job is slower than it was with 16. What is wrong?"

You do not need to write parallel code to help. You need to recognise what kind of program it is, and ask for the right facts. After reading this guide you can:

1. Explain what OpenMP is: threads that share memory inside one process on one node.
2. Read an OpenMP job script and say how many threads should run, and why.
3. Check on the node whether the threads really get their own cores.

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

## 8. An OpenMP job script, line by line

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

## 9. Reserved vs started: compare two numbers

The lab script `show_map.sh` turns a job's output into a picture of where each thread ran.

On the lab VM (1 CPU), all four threads share `cpu0`:

```
  NODE compute1
    1 process  [t0 @cpu0] [t1 @cpu0] [t2 @cpu0] [t3 @cpu0]

  Workers: 4   Nodes: 1
  This looks like: OpenMP (threads in one process)
```

On a real node (a run on a 16-core machine), each thread sits on its own CPU:

```
  NODE node01
    1 process  [t0 @cpu6] [t1 @cpu7] [t2 @cpu3] [t3 @cpu1]

  Workers: 4   Nodes: 1
```

Same shape: one process, four threads.

A job has two numbers to compare:

| What Slurm **reserved** | What the program **started** |
|---|---|
| `sacct -j <jobid> --format=JobID,NNodes,AllocCPUS,State` | `top -H -p <pid>` or `ps -o nlwp= -p <pid>` on the node |

In the lab, `AllocCPUS` is 1 while the picture shows 4 workers. On a real cluster the common problem is a script that reserves 4 CPUs while the program starts more threads than that. The fix is always the same: set `OMP_NUM_THREADS` from `SLURM_CPUS_PER_TASK`.

---

## 10. What users say, and what you ask

| The user says | It may point to | You ask for or check |
|---|---|---|
| "My program ignores the cores" | No `-fopenmp`, `OMP_NUM_THREADS=1` or unset, or `--cpus-per-task=1` | The compile line and the job script. `top -H` on the node |
| "The answer changes between runs" | A race condition on shared data | A run with `OMP_NUM_THREADS=1` and one with several. Compare |
| "64 cores, but slower than 16" | More threads than reserved CPUs, or work that does not split | `OMP_NUM_THREADS` vs `--cpus-per-task`. Timings at 16, 32, 64 |
| "I asked for 2 nodes, only 1 is busy" | OpenMP runs on one node only | Is it MPI too? Ask for the run line |
| "No OpenMP in my code, yet many cores" | A threaded library inside (BLAS, NumPy) | Set `OMP_NUM_THREADS` = `--cpus-per-task` |

The last row is worth a note: libraries such as BLAS, used by NumPy, can use OpenMP threads internally, so the same rules apply even if the user never wrote a pragma.

**Always add to the ticket:** the job ID, the job script as submitted, what `sacct` says was allocated, and the last lines of output. A ticket with these four facts can be picked up by the HPC team without going back to the user.

---

## 11. Practice: what do you say?

**A.** "I set `OMP_NUM_THREADS=32`, but my script has `--cpus-per-task=4`. The job is slow."

**B.** "With 1 thread the total is 1000. With 8 threads it is 874, and 912 the next time."

**C.** "My OpenMP job asks for 2 nodes, but only one node is busy."

Try each one before reading on: what kind of problem is it, and what do you ask for first?

<details><summary>Answers</summary>

**A. Threads exceed cores.** 32 threads share 4 CPUs. Match the thread count to the cores asked for, or ask for more cores.

**B. Looks like a race.** The result changes with the thread count and between runs. Reproduce with 1 and 8 threads, keep both outputs, and pass it to the HPC team or the code owner. You do not need to find the bug.

**C. Expected.** OpenMP stays on one node. Check whether the program is MPI as well.
</details>

---

## 12. Rules of thumb

1. OpenMP = threads in one process, on one node.
2. Threads = cores: `OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK`.
3. Compile with `-fopenmp`. Check with `top -H`.
4. Answer changes with the thread count? Think race. Test with 1 thread.
5. Threads only speed things up when each has its own core.

---

## 13. Where to go next

- **Hands-on:** [Chapter 11](chapters/11-openmp.md) (OpenMP on one node, about 1 hour) and Part 1 of [Chapter 13](chapters/13-parallel-on-slurm.md) (an OpenMP job on Slurm).
- **MPI vs OpenMP:** how MPI ranks run across nodes, how hybrid jobs combine ranks with threads, and how to pin threads to cores (affinity). See [Chapter 12](chapters/12-openmpi.md).
