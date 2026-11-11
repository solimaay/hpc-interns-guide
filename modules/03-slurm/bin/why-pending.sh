#!/usr/bin/env bash
# why-pending - explain in plain words why a Slurm job is waiting.
#
#   why-pending          explain every pending job of yours
#   why-pending 1234     explain job 1234
#
# Read-only. For each job it shows the reason code, what it means, and who has to act.
set -u

# reason code -> what it means and who acts
explain() {
  case "$1" in
    None)        echo "No reason yet. Normal for a job submitted a moment ago. Run squeue again in a minute." ;;
    Priority)    echo "Jobs ahead of this one have a higher priority. Nothing is wrong: wait. (sprio -j <id> shows why)" ;;
    Resources)   echo "First in line, but the CPUs or memory it asked for are not free yet. Wait, or ask for less." ;;
    Dependency)  echo "Waiting for another job (--dependency) to finish. Check it with: squeue -j <other id>" ;;
    DependencyNeverSatisfied)
                 echo "The job it depends on failed, so this job will never start. The owner must scancel and resubmit." ;;
    JobHeldUser) echo "The owner put the job on hold. The owner releases it: scontrol release <id>" ;;
    JobHeldAdmin) echo "An administrator put the job on hold. Ask the administrators." ;;
    BeginTime)   echo "The job was submitted with a start time in the future (--begin). It is waiting on purpose." ;;
    ReqNodeNotAvail*|NodeDown)
                 echo "A node the job needs is down, drained or reserved. An administrator must act: sinfo -R shows why." ;;
    PartitionDown) echo "The partition is down, so nothing in it can start. An administrator must act." ;;
    PartitionTimeLimit)
                 echo "The job asks for more time than the partition allows, so it will never start. Resubmit with a shorter --time." ;;
    QOS*|Assoc*) echo "A usage limit was reached (for example jobs per user). The job starts when earlier jobs finish." ;;
    BadConstraints) echo "The job asks for something the cluster does not have, so it will never start. Resubmit with a valid request." ;;
    *)           echo "Not in this tool's list. Look it up: man squeue (section JOB REASON CODES)" ;;
  esac
}

command -v squeue >/dev/null || { echo "why-pending: Slurm is not installed on this node yet."; exit 1; }

if [ -n "${1:-}" ]; then jobs="$(squeue -h -j "$1" -o '%i|%T|%r|%P')"
else jobs="$(squeue -h -u "$(id -un)" -t PENDING -o '%i|%T|%r|%P')"; fi

[ -n "$jobs" ] || { echo "No matching jobs in the queue."; exit 0; }

while IFS='|' read -r id state reason partition; do
  echo "----------------------------------------"
  echo "Job $id in partition $partition: $state"
  if [ "$state" != PENDING ]; then continue; fi
  echo "Reason : $reason"
  echo "Meaning: $(explain "$reason")"
done <<< "$jobs"
