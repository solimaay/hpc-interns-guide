#!/usr/bin/env bash
# fault-status - are you done with the troubleshooting exercise on this node?
#
#   fault-status            check whether the planted problem is fixed
#   fault-status --ticket   show the ticket (the user's complaint) again
#
# Exit code: 0 = fixed, 1 = not fixed yet, 2 = nothing planted.

[ "${1:-}" = "--ticket" ] && exec sudo inject-fault --ticket

sudo inject-fault --check
rc=$?
if [ "$rc" -eq 0 ]; then
  echo
  echo "Before you move on, write your note for the ticket:"
  echo "  1. what the user reported       3. the root cause"
  echo "  2. what you checked, in order   4. what you changed to fix it"
elif [ "$rc" -eq 1 ]; then
  echo "Need the ticket again? Run: fault-status --ticket"
fi
exit "$rc"
