# Chapter 11 - OpenMP: threads on one node

About 1 hour. You work on `login` as the user `vagrant`.

Users will ask you why their program does not use all the cores, or why it gives a different answer each run. Both questions start here. OpenMP is the simplest way to run one program on many cores of one machine: the program starts several threads that share the same memory. You write ordinary C with a few `#pragma` lines, and the compiler does the rest.

## What you will learn

- Compile and run an OpenMP program, and control the thread count with `OMP_NUM_THREADS`.
- See a race condition and fix it with a reduction.
- Explain why the lab nodes show no speed-up, and what you would look for on a real node.
- Read what the Slurm options `--cpus-per-task` and `OMP_NUM_THREADS` have to do with each other.

## Before you start

- Chapters 1 to 5 are done.
- Prepare the nodes from your host in the lab folder:

  ```bash
  vagrant provision login    --provision-with parallel
  vagrant provision compute1 --provision-with parallel
  ```

- On each node, `parallel-verify` should end with `Result: PARALLEL READY`.
- Take a snapshot: `vagrant snapshot save before-parallel`.
- Work in a scratch folder on the node: `mkdir -p ~/omp && cd ~/omp`.

## Part 1 - Hello from many threads

```bash
cat > hello.c <<'EOT'
#include <stdio.h>
#include <omp.h>

int main(void) {
    #pragma omp parallel
    {
        printf("hello from thread %d of %d\n", omp_get_thread_num(), omp_get_num_threads());
    }
    return 0;
}
EOT
gcc -fopenmp hello.c -o hello
./hello
```

`-fopenmp` turns the pragmas on. Without it, the compiler ignores them and you get one ordinary thread. Try it: `gcc hello.c -o hello_serial` fails to link `omp_get_thread_num`, because the OpenMP library is missing. (The pragma itself is ignored silently, which is why forgetting the flag is a common mistake.)

The node has 1 CPU, so OpenMP starts 1 thread. You choose the number with an environment variable:

```bash
nproc
OMP_NUM_THREADS=4 ./hello
OMP_NUM_THREADS=4 ./hello
```

You get four lines in an order that changes between runs. Threads run at the same time and nobody controls who prints first. Remember this: it is the same reason the next part goes wrong.

## Part 2 - A race condition

Add the numbers 1 to 1,000,000. The right answer is 500000500000.

```bash
cat > race.c <<'EOT'
#include <stdio.h>

int main(void) {
    long sum = 0;
    #pragma omp parallel for
    for (long i = 1; i <= 1000000; i++)
        sum += i;                       /* every thread updates the same variable */
    printf("sum = %ld (expected 500000500000)\n", sum);
    return 0;
}
EOT
gcc -fopenmp race.c -o race
for n in 1 2 4 8; do echo "threads=$n"; OMP_NUM_THREADS=$n ./race; done
```

With 1 thread the answer is right. With more threads it is usually wrong, and different each run. Two threads read `sum`, add to their copy, and write back, so one update is lost. That is a **race condition**: the result depends on timing. It is the worst kind of bug because the program does not crash. It just gives bad numbers.

The fix is a **reduction**. Each thread keeps its own private sum and OpenMP adds them at the end:

```bash
sed 's/#pragma omp parallel for/#pragma omp parallel for reduction(+:sum)/' race.c > fixed.c
gcc -fopenmp fixed.c -o fixed
for n in 1 2 4 8; do echo "threads=$n"; OMP_NUM_THREADS=$n ./fixed; done
```

Now every run is correct.

> **For admins.** You do not fix users' code, but you recognise the symptom: "the answer changes when I change the thread count". Ask the user to run with `OMP_NUM_THREADS=1` first. If that gives a different answer, the code has a race.

## Part 3 - Does it go faster?

Estimate pi by adding up many small rectangles, which splits well between threads:

```bash
cat > pi.c <<'EOT'
#include <stdio.h>
#include <omp.h>

int main(void) {
    const long steps = 400000000;
    const double h = 1.0 / steps;
    double sum = 0.0;
    double t0 = omp_get_wtime();
    #pragma omp parallel for reduction(+:sum)
    for (long i = 0; i < steps; i++) {
        double x = (i + 0.5) * h;
        sum += 4.0 / (1.0 + x * x);
    }
    printf("pi = %.10f  threads = %d  time = %.2f s\n", sum * h, omp_get_max_threads(), omp_get_wtime() - t0);
    return 0;
}
EOT
gcc -O2 -fopenmp pi.c -o pi
for n in 1 2 4; do OMP_NUM_THREADS=$n ./pi; done
```

The value of pi is the same each time, but the time is not shorter with more threads. The VM has one CPU, so four threads take turns on it, and switching between them costs a little. On a node with many cores, two threads would take about half the time.

While a run is going, open a second terminal on `login` and look at it:

```bash
top -H -p $(pgrep -n pi)
```

`-H` lists threads. With 4 threads you see four lines sharing one CPU. On a real compute node you would see each thread at 100% on its own core. This is how you check whether a user's job really uses the cores they asked for.

## Part 4 - OpenMP and Slurm

OpenMP is not aware of Slurm. If a user asks for 4 CPUs and the program starts 64 threads (because the node has 64 cores), the threads fight over 4 CPUs. The rule on a cluster is: **tell OpenMP how many CPUs Slurm gave you**.

```bash
#!/bin/bash
#SBATCH --cpus-per-task=4
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
./pi
```

Read the script; you do not need to run it. Chapter 7 shows how to submit jobs. On the lab nodes (1 CPU each) a request for 4 CPUs would stay pending, and `why-pending` would tell you why.

## Clean up

```bash
cd ~ && rm -rf ~/omp
```

## Check yourself

<details><summary>1. A user says their OpenMP program ignores the cores. What do you check first?</summary>

Was it compiled with `-fopenmp`? Is `OMP_NUM_THREADS` set to something small (or `1`)? Under Slurm, is `--cpus-per-task` more than 1? `top -H` shows how many threads really run.
</details>

<details><summary>2. A program prints different results on each run with 4 threads and the right result with 1. What is it?</summary>

A race condition: threads update shared data without coordination. A `reduction` clause, or protecting the update, fixes it.
</details>

<details><summary>3. Why did four threads not run faster in the lab?</summary>

The VM has one CPU. Threads can only take turns, so there is no extra compute power, plus a little switching overhead.
</details>

<details><summary>4. Can OpenMP spread one program over `login` and `compute1`?</summary>

No. Threads share memory, so they must be on one node. Using several nodes needs MPI, the next chapter.
</details>

<details><summary>5. A job asks for 4 CPUs on a 64-core node and the program starts 64 threads. What happens?</summary>

Slurm confines the job to 4 CPUs (with cgroups), so 64 threads share 4 CPUs and run slowly. The job script should set `OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK`.
</details>

## If you are stuck

- `parallel-verify` names the missing piece.
- `undefined reference to omp_get_thread_num`: you forgot `-fopenmp` when compiling.
- `gcc: command not found`: run the provisioner on this node.
- To start over: `vagrant snapshot restore before-parallel`.

## Next

Chapter 12, [Open MPI across nodes](12-openmpi.md).
