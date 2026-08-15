#!/bin/bash
# Double-click this if macOS says the author cannot be verified.
# It strips the download flag and signs 1132.WTF as your own copy.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$HERE/allow-macos.sh"
