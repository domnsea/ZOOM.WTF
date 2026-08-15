#!/bin/bash
# Open the 1132.WTF log folder.
set -u
LOG_DIR="$HOME/Library/Logs/1132.WTF"
if [ -d "$LOG_DIR" ]; then
  open "$LOG_DIR"
else
  printf '%s\n' "No logs yet. Run 1132.WTF at least once."
  printf '%s\n' "They will appear in: $LOG_DIR"
  read -r -p "Press Return to close. " _
fi
