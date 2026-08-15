#!/bin/bash
# v9 launch. Do not invent a temp Mac user or sudo here.
exec /bin/bash "$(cd "$(dirname "$0")" && pwd)/launch_fresh_zoom.sh" "$@"
