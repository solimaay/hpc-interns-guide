# HPC Intern Lab

A small virtual cluster for learning HPC system administration by doing. You work through chapters, from your first login to building Slurm, and practice troubleshooting on problems planted in the cluster. Nothing touches a real system.

> Instructors: the answer key is in [admin/](admin/README.md). Keep that folder away from learners.

## The cluster

| Node | Role | IP |
|---|---|---|
| `login` | Login node, NFS server for `/shared` | 192.168.56.10 |
| `compute1` | Compute node | 192.168.56.11 |

Rocky Linux 9, about 1.25 GB RAM (1280 MB) and 1 vCPU per node. Your computer needs 8 GB RAM, about 50 GB free disk, CPU virtualization enabled, [VirtualBox](https://www.virtualbox.org/) and [Vagrant](https://www.vagrantup.com/).

## Quick start (chapter 0)

Run these in this folder, on your computer.

```bash
vagrant up              # builds the nodes (first run downloads the box, 15 to 30 minutes, depending on your internet speed)
vagrant ssh login       # your first login
lab-verify              # inside the VM: should end with "Result: HEALTHY"
```

Do the same on `compute1`. Login password for the lab accounts: `hpclab`.

| Command | What it does |
|---|---|
| `vagrant status` | Shows which nodes are running |
| `vagrant halt` / `vagrant up` | Stops / starts the cluster; your work stays |
| `vagrant snapshot save clean` | Saves a restore point (restore: `vagrant snapshot restore clean`) |
| `vagrant destroy -f` | Deletes the cluster completely |

## Changing the cluster

The nodes (names and IP addresses) are listed in `nodes.txt`. The lab password and the shared folder are set at the top of `core/provision-base.sh`. Node memory and CPUs are in the `Vagrantfile`. Nothing is passed in from outside.

## Chapters

Self-paced; each chapter assumes the earlier ones.

| Chapter | Topic | Est. time |
|---|---|---|
| 0 | Set up the lab, first login, health check, snapshot (above) | 1-2 h |
| 1 | [Storage and the shared filesystem](modules/01-sysadmin-foundations/chapters/01-storage.md) | 1 h |
| 2 | [Time sync and services](modules/01-sysadmin-foundations/chapters/02-time-and-services.md) | 1 h |
| 3 | [Users, groups and SSH keys](modules/01-sysadmin-foundations/chapters/03-users-and-ssh.md) | 1.5 h |
| 4 | [Permissions and processes](modules/01-sysadmin-foundations/chapters/04-permissions-and-processes.md) | 1 h |
| 5 | [Name resolution and hosts](modules/01-sysadmin-foundations/chapters/05-name-resolution.md) | 45 min |
| 6 | [Troubleshooting practice](modules/02-troubleshooting/README.md) | 2-3 h |
| 7-8 | [Build Slurm, verify it, read pending jobs](modules/03-slurm/README.md) | 4-6 h |
| 9 | [Node health checks](modules/04-health-monitoring/README.md) | 45 min |

## Layout

```text
Vagrantfile     describes the nodes
core/           base setup and the lab-verify health check
modules/        one folder per topic: chapters, tools, optional provisioner
admin/          instructor guide and answer key
```

## Security note

This is a disposable lab. It uses a well-known default password, enables SSH password login, and (during the Slurm chapters) leaves a copy of the munge key on shared storage until it is cleaned up. Never reuse these settings on a real system, and do not expose the lab VMs to a network you do not control.

## License

Copyright (c) 2026 Ahmed Yousri Sobhi. Supplied to the course under the terms in [LICENSE](LICENSE).
