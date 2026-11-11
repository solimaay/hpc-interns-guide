# 04 - Health monitoring

Chapter 9. You read the health of a node on one screen: Slurm state, load, memory, disks, mounts, services and clock.

Prerequisite: chapters 1 to 5, and chapter 7 if you want the Slurm lines ([03-slurm](../03-slurm/README.md)). Without Slurm the tool still works and says it has no Slurm view.

This module has no provisioner. Its tool is installed on every node by `vagrant up`.

## Tool

| Tool | What it does |
|---|---|
| `node-health` | Prints one tagged line per item and ends with a verdict. Read-only. |

```bash
node-health
```

Run it on the node you want to check.

Each line is tagged `[ OK ]`, `[WARN]`, `[FAIL]` or `[INFO]`. The last line is `HEALTHY`, `ATTENTION` (warnings only) or `PROBLEM` (at least one failure). The exit code is 0 unless something failed.

## What it checks

| View | Items |
|---|---|
| Slurm | node state (if Slurm is installed and knows the node) |
| Operating system | load per CPU, available memory, full disks, network mounts that stop answering, services that should be running, clock sync |

Thresholds: load above 1 per CPU warns and above 2 fails; available memory under 10% warns and under 5% fails; disks warn at 90% and fail at 98%.

## Good to know

- **The login node is not a compute node.** On `login`, `node-health` says it is not known to Slurm. That is expected.
- **A hung NFS mount** (for example `login` stopped exporting `/shared`) is reported as a failure after 5 seconds, without blocking the tool.
- **Load average lags.** After a burst of work, the one-minute load stays high for a while.

## Try it

1. Run `node-health` on each node of a healthy cluster. Read every line.
2. Break something and run it again, then fix it and watch the verdict return: stop a service (`sudo systemctl stop chronyd`), drain a node (`sudo scontrol update NodeName=compute1 State=DRAIN Reason=test`; run `node-health` on `compute1`), or start a few busy loops.
3. Combine it with chapter 6: plant a problem with `sudo inject-fault random`, then let `node-health` point you at the area before you dig in.
