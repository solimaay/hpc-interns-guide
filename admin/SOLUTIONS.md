# Troubleshooting answer key

> **Spoilers.** This file names the cause and the fix of every planted problem in module [02-troubleshooting](../modules/02-troubleshooting/README.md). Learners should not read it before they have tried the exercise: `sudo inject-fault --reveal` is the gentler hint.
>
> The scenarios are readable in `inject-fault.sh` on every node, so treat the exercises as practice, not as an assessment. For an exam, keep a private variant of the script with different scenarios.

For how the fault system works, how to hand out problems and how to recover, see the [admin guide](README.md).

## What is planted

"After chapter" says when a learner has the skills for that problem; chapter 6 is the practice chapter that uses all of them.

| Scenario | Runs on | Symptom the user reports | Skill practiced | After chapter |
|---|---|---|---|---|
| `disk-full` | any | Application cannot save: "No space left on device" | `df`, `du`, finding large files | 1, 6 |
| `service-failed` | any | Clock drifting, time service will not stay up | `journalctl`, config files | 2, 6 |
| `locked-user` | any | bob cannot log in | `passwd -S`, `chage -l`, `usermod` | 3, 6 |

## Answer key

Each entry lists what is planted, how to diagnose, the fix, and points for the debrief. The exact ticket text and the fixed-check are in `inject-fault.sh` (the `ticket_*` and `check_*` functions).

---

### `disk-full`

**Planted:** a 64 MB filesystem (loop-mounted, no reserved space) at `/data/app`, owned by carol. It holds `config.yml`, a legitimate 12 MB `logs/app-2026.log`, and a large `logs/core.dump.tmp` that fills the rest.

**Diagnose**

1. `df -h /data/app` shows the filesystem at 100%.
2. `du -sh /data/app/*` and `ls -lh /data/app/logs` show where the space went.
3. The large `core.dump.tmp` is the culprit.

**Fix:** remove (or truncate) `/data/app/logs/core.dump.tmp`.

**Debrief**

- Freeing the 12 MB log would also pass the check. Ask which file was safe to delete and why: a temporary dump versus an application log.
- `df` tells you which filesystem is full, `du` tells you where the data is.
- Ask what they would tell the user, and whether the dump needs investigating.

---

### `service-failed`

**Planted:** in `/etc/chrony.conf`, `driftfile` is misspelled as `driftfle` (or a bad line is added if no `driftfile` exists), and `chronyd` is restarted so that it fails.

**Diagnose**

1. `chronyc tracking` reports it cannot talk to the daemon.
2. `systemctl status chronyd` shows a failed unit.
3. `journalctl -u chronyd` names the unrecognized directive and its line.
4. Inspect `/etc/chrony.conf` and find the typo.

**Fix:** correct the directive, then `sudo systemctl restart chronyd`.

**Debrief**

- Reading the log first beats guessing.
- Ask why a wrong clock matters later (chapter 7: munge rejects credentials when clocks differ).
- Suggest `chronyc makestep` after the service is back to correct a large offset.

---

### `locked-user`

**Planted:** `usermod -L -e 1 bob`: bob's password is locked and his account is expired. It affects only the node where it was planted.

**Diagnose**

1. `passwd -S bob` shows the status as locked (`LK`).
2. `chage -l bob` shows the account expired (the expiry date is in 1970).
3. `su - bob` reports that the account has expired.

**Fix:** `sudo usermod -U bob` and `sudo usermod -e "" bob` (or `sudo chage -E -1 bob`)

**Debrief**

- Two separate mechanisms are in play. Fixing only one still leaves bob locked out.
- Accounts are local on each node (no LDAP in the lab), so the fix is needed on every affected node. Link this to why centralized identity matters.
