# Admin guide

For the person who runs this lab for other people (an "admin"): how the planted problems work, how to hand them out, how to recover, how to run the Slurm chapter, and how to maintain the lab. Learners need only the [lab README](../README.md) and the module READMEs.

The cause and fix of every planted problem are in [SOLUTIONS.md](SOLUTIONS.md). That file is a spoiler for learners.

## 1. How the fault system works

`inject-fault` plants one practice problem on a node and gives the learner the user's ticket. `fault-status` (which calls `inject-fault --check`) tells the learner whether it is fixed.

| Item | Detail |
|---|---|
| Installed as | `/usr/local/bin/inject-fault` and `/usr/local/bin/fault-status` on every node (from [modules/02-troubleshooting/bin/](../modules/02-troubleshooting/bin/)) |
| Needs | root (`sudo`), and a node provisioned by `core/provision-base.sh` |
| State directory | `/var/lib/hpc-lab/fault/` (root only): `active` (scenario name), `ticket`, `solution`, `data/` (backups) |
| Limit | One active problem per node |
| Checks | Based on the end state of the system, not on the commands used |

Commands (all with `sudo`):

| Command | Purpose |
|---|---|
| `inject-fault <scenario>` | Plant a named problem (`disk-full`, `service-failed`, `locked-user`) |
| `inject-fault random` | Plant a random problem (name hidden) |
| `inject-fault --ticket` | Show the ticket again (the state directory is root-only) |
| `inject-fault --check` | Fixed? Exit 0 yes, 1 no, 2 none active |
| `inject-fault --reveal` | Show the cause and the fix |
| `inject-fault --revert` | Undo the problem and clear the state |

There is no confirmation prompt, so `vagrant ssh <node> -c "sudo inject-fault <scenario>"` works.

### Running an exercise session

1. Make sure the lab is healthy: `lab-verify` on every node. Take a snapshot first (`vagrant snapshot save clean`).
2. Choose how problems are assigned (section 2).
3. Learners plant, investigate and report using [module 02](../modules/02-troubleshooting/README.md).
4. Debrief with the notes in [SOLUTIONS.md](SOLUTIONS.md). Ask each learner for the four-point note: what the user reported, what was checked in order, the root cause, the fix.
5. Learners run `sudo inject-fault --revert` before the next exercise.

### Reboots

State is stored on disk and survives a reboot, but some effects do not:

| Survives a reboot | Disappears at reboot |
|---|---|
| `service-failed`, `locked-user` | `disk-full` (loop mount) |

After a reboot, a learner should run `sudo inject-fault --revert` to clear the state. Otherwise `fault-status` keeps reporting `NOT FIXED YET` for the problems that disappeared (for example a missing `/data/app` mount).

## 2. Assigning problems

| Approach | How | Use it when |
|---|---|---|
| Self-service | Learners run `sudo inject-fault random` | Practice; each learner gets something different |
| Named | `sudo inject-fault <scenario>` | You are demonstrating one scenario, or testing |

## 3. Checking the scenarios yourself

Run this once on your lab for each of the three scenarios (`disk-full`, `service-failed`, `locked-user`) before using them with learners:

| Step | Expected |
|---|---|
| `sudo inject-fault <scenario>` | Prints the ticket without errors |
| The diagnose commands in [SOLUTIONS.md](SOLUTIONS.md) | Show the problem |
| `fault-status` before the fix | `NOT FIXED YET` |
| Apply the fix from the answer key | `fault-status` says `FIXED` |
| `sudo inject-fault --revert` | `The node is back to normal`, and `lab-verify` passes |

For `service-failed`, confirm the typo really stops `chronyd` on your image. For `disk-full`, confirm the loop mount works.

## 4. Recovery

| Situation | Action |
|---|---|
| Learner finished or gave up | `sudo inject-fault --revert` |
| Node rebooted during an exercise | `sudo inject-fault --revert`, then plant again if needed |
| `--revert` fails or the node is badly broken | `vagrant snapshot restore clean`, or `vagrant destroy -f` and `vagrant up` |
| SSH to a node is dead and `vagrant ssh` fails | Reboot the node from the hypervisor (VirtualBox: `VBoxManage controlvm hpc-<node> reset`); `/dev` and the runtime state are rebuilt at boot |
| A planted problem hit the wrong node | Run `sudo inject-fault --revert` on that node |

Tips:

- Take the snapshot before any exercise session.
- Do not run a scenario on a node that is being used for something else. Problems such as `service-failed` affect the whole node.

## 5. Adding a scenario

In [inject-fault.sh](../modules/02-troubleshooting/bin/inject-fault.sh), add the scenario name to `SCENARIOS` and define five functions, using underscores in place of hyphens in the names:

| Function | Purpose |
|---|---|
| `ticket_<name>` | Prints the user's complaint (symptom only) |
| `solution_<name>` | Prints the cause and the fix (shown by `--reveal`) |
| `inject_<name>` | Plants the problem. Back up anything it changes under `$DATA` |
| `check_<name>` | Returns 0 when the end state is fixed |
| `revert_<name>` | Restores the original state |

Also add the name to the `random|disk-full|...` line in the command list at the bottom of the script. Then add an entry to [SOLUTIONS.md](SOLUTIONS.md) and check the scenario as in section 3. Roll the updated script out with `vagrant provision <node> --provision-with base` (the scripts are read from the shared folder).

## 6. The Slurm chapter

Chapter 7 uses [module 03-slurm](../modules/03-slurm/README.md). You prepare the nodes; the learners build the cluster.

| When | Task | Command |
|---|---|---|
| Before the chapter | Make sure the login node can reach `download.schedmd.com` (the build downloads the source) | `vagrant ssh login -c "curl -sI https://download.schedmd.com/slurm/ \| head -1"` |
| Start of the chapter | Prepare every node, `login` first (about 10 minutes on the login node, 1 minute on the compute node) | `vagrant provision <node> --provision-with slurm` |
| During | Learners follow `/shared/slurm-lab/README.txt` and use `slurm-verify` | |
| End of the chapter | Delete the staged munge key from shared storage (the built packages stay) | `vagrant ssh login -c "sudo rm /shared/slurm-lab/munge.key"` |

Notes:

- **Slurm is built from source.** The provisioner builds Slurm 26.05.5 once on the login node, checks the tarball's SHA-256, and puts the RPMs in `/shared/slurm-lab/rpms/`. EPEL only has 22.05, which upstream no longer supports. A repeat run skips the build; to rebuild, delete the RPMs in that directory.
- **Updating the version.** Change `DEFAULT_VERSION` and `DEFAULT_SHA256` in [provision.sh](../modules/03-slurm/provision.sh) (the checksum comes from `https://download.schedmd.com/slurm/SHA256`), read the release notes, and run the whole chapter again.
- **Build dependencies matter.** Slurm 26 builds fine without `json-c-devel`, but `slurmctld` then refuses to start (`serializer_required: could not find plugin for application/json`). `http-parser-devel` is needed to avoid `http_parser` errors in the logs. If you change the dependency list, start the daemons before you trust the build.
- **The staged key is world-readable** on the NFS share, a lab-only convenience. Always delete it when the chapter is done.
- **The template** uses `proctrack/linuxproc` and `task/none`, so cgroup features are not exercised, and sets `MailProg=/bin/true` because the lab has no mail system. `RealMemory=CHANGE_ME` is deliberate: learners must read `slurmd -C`.
- **The packages do not create `/etc/slurm`.** The checklist tells learners to create it.
- **Memory.** The 1280 MB nodes are enough, including the build. `slurmctld` uses about 18 MB and `slurmd` about 11 MB. Adding `slurmdbd` and MariaDB was not tested.
- **Common failures to watch for:** clocks that differ (munge), a munge key that differs between nodes, `RealMemory` larger than the node has (node drained), directories not owned by `slurm`, and a `slurm.conf` that differs between nodes. `slurm-verify` reports most of these.

## 7. Support tools for your own use

These are installed on every node and are useful when a learner asks for help or when you triage a problem.

| Tool | Use it to |
|---|---|
| `node-health` | See in one screen whether a node is healthy (Slurm state, load, memory, full disks, hung mounts, services, clock) |
| `why-pending [jobid]` | Explain a pending job's reason code in plain words and see who has to act |
| `collect-evidence <user> [jobid]` | Capture the standard facts for a ticket in one file |
| `lab-verify`, `slurm-verify` | Check the lab base and the Slurm build |
| `inject-fault --reveal` | See which problem a learner was given |

## 8. Maintaining the lab

- Scripts keep Unix line endings (`.gitattributes` enforces this on clone) and stay executable.
- After any change to a script, run `vagrant provision` on a test lab and rerun the checks in section 3.
- Keep [SOLUTIONS.md](SOLUTIONS.md) in step with the scenario functions in `inject-fault.sh`: the ticket, `check_*` and `solution_*` text are the source of truth.
- Do not commit answer keys for an exam, internal URLs, or generated files (`lab-report-*.txt`, `evidence-*.txt`, `.vagrant/`, `*.box`; the last three are covered by `.gitignore`).
