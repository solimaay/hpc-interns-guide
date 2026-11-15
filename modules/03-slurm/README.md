# 03 - Slurm

Chapters 7 and 8. You build a working Slurm cluster yourself by following a checklist, verify it, and learn to explain why a job is pending.

Prerequisite: chapters 1 to 5 ([01-sysadmin-foundations](../01-sysadmin-foundations/README.md)). Slurm needs matching accounts, a synced clock, working name resolution and shared storage, and this chapter is where those pay off.

## Tools

| Tool | Where it comes from | What it does |
|---|---|---|
| `provision.sh` | run with `vagrant provision --provision-with slurm` | Prepares every node and builds the Slurm packages (login node, once). It does **not** install or start Slurm; that is your job. |
| `slurm-verify` | installed by the provisioner | Checks the Slurm build on the node you are on. On the login node it also runs a test job on every compute node. |
| `why-pending` | installed by the provisioner | Explains in plain words why a job is waiting, who has to act, and the first command to run. |

## Chapter 7 - Build a Slurm cluster

### 1. Prepare the nodes

Run this on your host, from the lab folder, login node first (the compute node fetches the munge key from it):

```bash
vagrant provision login    --provision-with slurm
vagrant provision compute1 --provision-with slurm
```

It is safe to repeat. The login node takes about 10 minutes the first time, because it builds Slurm from source (see [Which Slurm version](#which-slurm-version)); a repeat run skips the build. The compute node takes about a minute.

After it runs, every node has:

- the repositories the build and munge need (EPEL and CRB),
- on the login node, the Slurm packages (`.rpm` files) in `/shared/slurm-lab/rpms/`, which every node can read,
- the `slurm` and `munge` accounts with the same IDs everywhere,
- munge installed with the **same key** on every node, not started,
- on the login node, `/shared/slurm-lab/` with a `slurm.conf.template` and a step-by-step `README.txt`.

### 2. Follow the checklist

Read `/shared/slurm-lab/README.txt` on the login node and work through it: start munge and prove it works across nodes, install the right packages on each side from `/shared/slurm-lab/rpms/` (the controller needs different ones from a compute node), read `slurmd -C` for the memory value, finish `slurm.conf`, create the directories, start the daemons, and run `sinfo` and `srun -N1 hostname`.

If something fails, read the logs and look at the three usual suspects: the clock, the munge key and name resolution.

### 3. Check your work

```bash
slurm-verify
```

Run it on the login node and on each compute node. A healthy build ends with `Result: SLURM LOOKS HEALTHY`. Each failure comes with a hint for what to do next.

## Chapter 8 - Why is my job pending?

Submit a few jobs that cannot start straight away (a held job, a job with a dependency, a job that asks for more than is free, a job with a future start time), then explain them:

```bash
why-pending              # every pending job of yours
why-pending 1234         # one job
```

It is read-only. Use it to understand the user's question before you answer, and `collect-evidence` (module [02-troubleshooting](../02-troubleshooting/README.md)) when you need to escalate.

## Which Slurm version

The lab builds Slurm 26.05.5 from the official source tarball at `download.schedmd.com` and checks its SHA-256 before building. EPEL only offers Slurm 22.05, an old release that upstream no longer supports, so the packages from the distribution would teach you to run a version you should not run. The build uses the same steps an admin uses on a real cluster: `rpmbuild -ta`, then install the packages with `dnf`.

To change the version, edit `VERSION` and `SHA256` at the top of [provision.sh](provision.sh) (the checksum is on `https://download.schedmd.com/slurm/SHA256`).

## Cleaning up

The lab leaves a copy of the munge key on shared storage so the compute node can fetch it. A real cluster never does this. When the chapter is done, delete it on the login node:

```bash
sudo rm /shared/slurm-lab/munge.key
```

## Resources

The Slurm daemons are small: about 18 MB for `slurmctld` and 11 MB for `slurmd` (measured with 26.05.5). The default 1280 MB per node is enough, including for the one-time build on the login node. Slurm's `RealMemory` for a node must not exceed what `slurmd -C` reports (about 950 MB on a 1 GB node); the template uses `CHANGE_ME` so you read the real value.

## Reset

Remove Slurm's state by restoring the snapshot you took before this chapter (`vagrant snapshot save before-slurm` first), or by re-running the provisioner, which is safe but does not uninstall packages.

