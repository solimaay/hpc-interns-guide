# 06 - Parallel programs: OpenMP and Open MPI

Chapters 11 to 13. Three short, hands-on guides with small C programs: OpenMP (threads on one node) and Open MPI (programs spread across both nodes), then how to read OpenMP and MPI jobs on Slurm. The aim is to understand them well enough to support users, not to write production code.

Prerequisite: chapters 1 to 5 ([01-sysadmin-foundations](../01-sysadmin-foundations/README.md)). Chapter 7 ([03-slurm](../03-slurm/README.md)) is only needed for Chapter 13 and the optional Slurm remarks.

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
3. [Chapter 13 - OpenMP and Open MPI as Slurm jobs](chapters/13-parallel-on-slurm.md) (needs Slurm; uses the ready-made programs in [lab/](lab/))

## Slides and guide

- [slides/openmp-mpi-slides.pptx](slides/openmp-mpi-slides.pptx): 19 slides (about 40 minutes) on OpenMP and Open MPI, to present before Chapters 11 to 13. Speaker notes are on every slide.
- [openmp-openmpi-companion-guide.md](openmp-openmpi-companion-guide.md): the same material as a stand-alone reading guide.

The OpenMP program output comes from running the lab's own programs on a 16-core machine. The Open MPI and hybrid output is the expected output from Chapters 12 and 13.

## Notes

- Each node has 1 CPU, so OpenMP shows no speed-up and MPI needs `--oversubscribe` for more ranks than nodes. The chapters explain what you would see on real hardware.
- Chapter 12 runs as `alice` (home on `/shared`) so the compiled program is at the same path on both nodes.

## Reset

Restore the snapshot you took before the chapter, or remove the work folders `~/omp` and `~alice/mpi`.
