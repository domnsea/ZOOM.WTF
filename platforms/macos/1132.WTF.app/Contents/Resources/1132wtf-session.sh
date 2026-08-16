#!/bin/bash
# Blank-profile launch. Password prompt is in launch_fresh_zoom.sh.
exec /bin/bash "$(cd "$(dirname "$0")" && pwd)/launch_fresh_zoom.sh" "$@"
