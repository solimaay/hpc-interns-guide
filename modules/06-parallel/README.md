# 06 - Parallel programs: OpenMP and Open MPI

Chapters 11 and 12. Two short, hands-on guides with small C programs: OpenMP (threads on one node) and Open MPI (programs spread across both nodes). The aim is to understand them well enough to support users, not to write production code.

Prerequisite: chapters 1 to 5 ([01-sysadmin-foundations](../01-sysadmin-foundations/README.md)). Chapter 7 ([03-slurm](../03-slurm/README.md)) is only needed for the optional Slurm remarks.

## Tools

| Tool | Where it comes from | What it does |
|---|---|---|
| `provision.sh` | run with `vagrant provision --provision-with parallel` | Installs gcc, Open MPI, its development files and environment-modules, and `parallel-verify`. |
| `parallel-verify` | installed by the provisioner | Checks gcc with OpenMP, Open MPI, a 1-rank MPI test run, the module, and that the other node resolves. |

## Chapters

Start with:

```bash
vagrant provision login    --provision-with parallel
vagrant provision compute1 --provision-with parallel
vagrant ssh login -c parallel-verify
```

1. [Chapter 11 - OpenMP: threads on one node](chapters/11-openmp.md)
2. [Chapter 12 - Open MPI: one program on several nodes](chapters/12-openmpi.md)

## Notes

- Each node has 1 CPU, so OpenMP shows no speed-up and MPI needs `--oversubscribe` for more ranks than nodes. The chapters explain what you would see on real hardware.
- Chapter 12 runs as `alice` (home on `/shared`) so the compiled program is at the same path on both nodes.

## Reset

Restore the snapshot you took before the chapter, or remove the work folders `~/omp` and `~alice/mpi`.
