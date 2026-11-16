# Chapter 12 - Open MPI: one program on several nodes

About 1.5 hours. You work on `login` and `compute1` as the user `alice`.

OpenMP threads share memory, so they stay on one node. MPI (Message Passing Interface) starts several separate copies of a program, called **ranks**, which can run on different nodes and send messages to each other. Most large cluster jobs use it. As an admin you rarely write MPI code, but you often have to find out why `mpirun` hangs, why it cannot find the other node, or why ranks land on the wrong nodes. Open MPI is the implementation Rocky Linux ships.

## What you will learn

- Compile and run an MPI program, first on one node and then on both.
- Tell `mpirun` where to start ranks with a hostfile.
- Send messages between ranks on different nodes.
- Fix the two usual cross-node failures: no passwordless SSH, and the wrong network interface.
- Combine MPI and OpenMP (a hybrid job), and see how it maps onto Slurm.

## Before you start

- Chapters 1 to 5 are done, and Chapter 11 if you want the OpenMP background (the hybrid part uses it).
- Both nodes are prepared and `parallel-verify` ends with `Result: PARALLEL READY` on each.
- Take a snapshot: `vagrant snapshot save before-mpi`.
- Become alice on `login` and make a work folder. Alice's home is on `/shared`, so both nodes see the same files, which is what MPI needs (same program path on every node):

  ```bash
  sudo -iu alice
  module load mpi/openmpi-x86_64
  mkdir -p ~/mpi && cd ~/mpi
  which mpicc mpirun
  ```

  `module load` puts Open MPI's tools in your `PATH`. If `module` is not found, run `source /etc/profile.d/modules.sh` first.

## Part 1 - Hello from many ranks, one node

```bash
cat > hello.c <<'EOT'
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
EOT
mpicc hello.c -o hello
mpirun -np 1 ./hello
mpirun -np 4 ./hello
```

`mpicc` is `gcc` with the MPI include and library flags added (`mpicc --showme` prints them). The second `mpirun` stops with an error that there are not enough **slots**. Open MPI counts one slot per CPU, and this node has one. This protects real clusters from overloading a node. In the lab you can override it:

```bash
mpirun --oversubscribe -np 4 ./hello
```

All four ranks run on this node, taking turns on one CPU.

## Part 2 - Passwordless SSH between nodes

`mpirun` starts the ranks on another node by logging in over SSH. It cannot type a password, so it needs key-based login. Alice may already have a key from Chapter 3; make sure:

```bash
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519 -C alice@lab
grep -qF "$(cat ~/.ssh/id_ed25519.pub)" ~/.ssh/authorized_keys 2>/dev/null || cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys ~/.ssh/id_ed25519
ssh -o StrictHostKeyChecking=accept-new compute1 hostname
ssh login hostname
```

Both commands must print a hostname without asking for anything. (The first time you connect to a host SSH asks about its fingerprint; the option accepts it, and you do the same for `login` itself, because `mpirun` will also log in there.) If a password is asked, go back to Chapter 3: the usual causes are permissions on `~/.ssh` and a missing key.

Now see what the failure looks like. Temporarily hide the key and try to start a rank on the other node:

```bash
mv ~/.ssh/authorized_keys ~/.ssh/authorized_keys.off
mpirun --host compute1 -np 1 hostname
mv ~/.ssh/authorized_keys.off ~/.ssh/authorized_keys
```

It stops at a password prompt or prints `ORTE was unable to reliably start one or more daemons`. Press `Ctrl-C` if it waits. Put the file back (the last line) before going on.

## Part 3 - Two nodes: the hostfile

A hostfile lists the nodes and how many ranks each can take:

```bash
cat > hosts <<'EOT'
login    slots=1
compute1 slots=1
EOT
mpirun --hostfile hosts -np 2 ./hello
```

The first run is likely to fail, with a message that it cannot find `orted` or `mpirun` on `compute1`. The reason: SSH starts a plain, non-login shell there, which has not loaded the module, so `PATH` lacks Open MPI. Tell `mpirun` where Open MPI lives instead:

```bash
mpirun --prefix /usr/lib64/openmpi --hostfile hosts -np 2 ./hello
```

If it hangs or prints `connection refused` or `no route`, the ranks picked the wrong network. Each VM has two network interfaces: the NAT one that every VM shares (the same address on both) and the lab network `192.168.56.0/24`. Open MPI may try the NAT one, which cannot reach the other node. Pick the lab network:

```bash
export OMPI_MCA_btl_tcp_if_include=192.168.56.0/24
export OMPI_MCA_oob_tcp_if_include=192.168.56.0/24
mpirun --prefix /usr/lib64/openmpi --hostfile hosts -np 2 ./hello
```

You should see one line from `login` and one from `compute1`. (`btl` is the transport for rank-to-rank messages; `oob` is the channel `mpirun` uses to control the ranks. Setting `OMPI_MCA_*` variables is the same as passing `--mca` options.) To keep these settings for later logins:

```bash
cat >> ~/.bashrc <<'EOT'
export OMPI_MCA_btl_tcp_if_include=192.168.56.0/24
export OMPI_MCA_oob_tcp_if_include=192.168.56.0/24
EOT
```

Next, see where ranks land. With 4 ranks and two slots per node, the default is to fill one node before the next:

```bash
sed -i 's/slots=1/slots=2/' hosts
mpirun --prefix /usr/lib64/openmpi --hostfile hosts --oversubscribe -np 4 ./hello
mpirun --prefix /usr/lib64/openmpi --hostfile hosts --oversubscribe --map-by node -np 4 ./hello
```

The first run puts ranks 0 and 1 on `login`. `--map-by node` deals them out like cards, so ranks 0 and 2 go to `login` and 1 and 3 to `compute1`. Placement matters on real clusters: it decides which ranks share memory and which cross the network.

## Part 4 - Ranks talk to each other

Pass a number around a ring: rank 0 sends to rank 1, which adds 1 and sends it on, and so on until it returns to rank 0.

```bash
cat > ring.c <<'EOT'
#include <stdio.h>
#include <mpi.h>

int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);
    int rank, size, token;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    if (size < 2) { if (rank == 0) fprintf(stderr, "run with at least 2 ranks\n"); MPI_Finalize(); return 1; }
    if (rank == 0) {
        token = 100;
        MPI_Send(&token, 1, MPI_INT, 1, 0, MPI_COMM_WORLD);
        MPI_Recv(&token, 1, MPI_INT, size - 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        printf("rank 0 got the token back: %d (expected %d)\n", token, 100 + size - 1);
    } else {
        MPI_Recv(&token, 1, MPI_INT, rank - 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        token++;
        MPI_Send(&token, 1, MPI_INT, (rank + 1) % size, 0, MPI_COMM_WORLD);
    }
    MPI_Finalize();
    return 0;
}
EOT
mpicc ring.c -o ring
mpirun --prefix /usr/lib64/openmpi --hostfile hosts --oversubscribe --map-by node -np 4 ./ring
```

Messages between ranks 0 and 1 cross the network, and the token comes back as 103. Run it with `-np 1` and read the message.

Now a real calculation. Each rank adds up its share of the pi rectangles from Chapter 11, and `MPI_Reduce` sums the pieces on rank 0:

```bash
cat > pi.c <<'EOT'
#include <stdio.h>
#include <mpi.h>

int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    const long steps = 200000000;
    const double h = 1.0 / steps;
    double local = 0.0, total = 0.0, t0 = MPI_Wtime();
    for (long i = rank; i < steps; i += size) {
        double x = (i + 0.5) * h;
        local += 4.0 / (1.0 + x * x);
    }
    MPI_Reduce(&local, &total, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);
    if (rank == 0) printf("pi = %.10f  ranks = %d  time = %.2f s\n", total * h, size, MPI_Wtime() - t0);
    MPI_Finalize();
    return 0;
}
EOT
mpicc -O2 pi.c -o pi
mpirun --prefix /usr/lib64/openmpi --hostfile hosts --map-by node -np 1 ./pi
mpirun --prefix /usr/lib64/openmpi --hostfile hosts --map-by node -np 2 ./pi
```

Two ranks on two nodes use two CPUs, one per node, so the second run takes about half the time of the first (some variation is normal on VMs). This is the point of MPI: more nodes, more CPUs. Set `slots=1` in `hosts` if the second run says there are not enough slots.

## Part 5 - Hybrid: MPI between nodes, OpenMP inside

Real jobs often use one rank per node and OpenMP threads on the cores of each node. Print who runs where:

```bash
cat > hybrid.c <<'EOT'
#include <stdio.h>
#include <mpi.h>
#include <omp.h>

int main(int argc, char **argv) {
    int provided, rank, len;
    char node[MPI_MAX_PROCESSOR_NAME];
    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Get_processor_name(node, &len);
    #pragma omp parallel
    {
        printf("rank %d, thread %d of %d, on %s\n", rank, omp_get_thread_num(), omp_get_num_threads(), node);
    }
    MPI_Finalize();
    return 0;
}
EOT
mpicc -fopenmp hybrid.c -o hybrid
mpirun --prefix /usr/lib64/openmpi --hostfile hosts --map-by node -np 2 -x OMP_NUM_THREADS=2 ./hybrid
```

`-x` copies an environment variable to the ranks; without it the remote rank would not see `OMP_NUM_THREADS`. You see 2 ranks with 2 threads each. On a real cluster you would set the numbers to match the cores: `ranks x threads` should equal the CPUs you were given, or the node is overloaded.

> **Slurm.** Under Slurm you usually do not write a hostfile. Slurm gives `mpirun` the nodes and CPUs it allocated (`#SBATCH --nodes=2 --ntasks-per-node=1 --cpus-per-task=4`, then `mpirun ./hybrid` with `OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK`). The lab nodes have one CPU each, so a job can use at most one task per node. If you finished Chapter 7, try `sbatch` with `--nodes=2 --ntasks-per-node=1` and `mpirun ./hello` as the command; the output goes to a file in the submit folder.

## Clean up

```bash
cd ~ && rm -rf ~/mpi
sed -i '/OMPI_MCA_/d' ~/.bashrc
exit
```

`exit` returns you to `vagrant`.

## Check yourself

<details><summary>1. What is the difference between OpenMP and MPI?</summary>

OpenMP: threads in one process, sharing memory, one node. MPI: separate processes (ranks) that send messages, on one node or many. Big jobs combine them.
</details>

<details><summary>2. `mpirun -np 4 ./hello` says there are not enough slots. Is something broken?</summary>

No. The node has fewer CPUs than ranks requested. Request fewer ranks, add slots to the hostfile if the node really has the CPUs, or use `--oversubscribe` when you want to test.
</details>

<details><summary>3. `mpirun` on two nodes hangs with no output. Name the first two things you check.</summary>

Passwordless SSH to every node in the hostfile (`ssh node hostname`), and the network interface Open MPI uses (`OMPI_MCA_btl_tcp_if_include` / `oob_tcp_if_include` pointing at the cluster network). Also check that the program exists at the same path on every node.
</details>

<details><summary>4. `mpirun` says it cannot find `orted` on the remote node. Why?</summary>

SSH starts a non-login shell on the remote node, which has not loaded the module, so Open MPI is not in its `PATH`. Use `--prefix`, or set the path in a place that non-login shells read.
</details>

<details><summary>5. Why must alice's folder be on `/shared`?</summary>

MPI runs the same executable on every node. The file must exist at the same path on each of them, and shared storage gives that.
</details>

## If you are stuck

- `parallel-verify` names the missing piece.
- `mpirun: command not found`: run `module load mpi/openmpi-x86_64` (or call `/usr/lib64/openmpi/bin/mpirun`).
- A password prompt from `mpirun`: Part 2; check permissions with `ls -ld ~/.ssh` (700) and `ls -l ~/.ssh` (600 for keys).
- Hangs after `hello from rank 0`: the other rank cannot reach it; set the two `OMPI_MCA_*` variables from Part 3.
- To start over: `vagrant snapshot restore before-mpi`.

## Next

Chapter 9, [node health checks](../../04-health-monitoring/README.md), pairs well with this one: run `node-health` on both nodes while `pi` is busy.
