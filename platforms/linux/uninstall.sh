#!/usr/bin/env bash
#
# Remove 1132.WTF from Linux.
#
#   ./uninstall.sh              remove from ~/.local
#   ./uninstall.sh --system     remove from /usr/local (needs root)
#   ./uninstall.sh --prefix DIR remove from DIR
#
# Zoom is never touched. Identity backups are kept unless you ask for them to
# go as well.

set -u
set -o pipefail

APP_NAME="1132.WTF"
APP_ID="1132wtf"

PREFIX="$HOME/.local"
MODE="user"

while [ $# -gt 0 ]; do
  case "$1" in
    --system)
      PREFIX="/usr/local"
      MODE="system"
      shift
      ;;
    --prefix)
      [ $# -ge 2 ] || { printf '%s\n' "--prefix needs a directory" >&2; exit 2; }
      PREFIX="$2"
      MODE="custom"
      shift 2
      ;;
    -h | --help)
      printf '%s\n' "Usage: $0 [--system | --prefix DIR]"
      exit 0
      ;;
    *)
      printf '%s\n' "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [ "$MODE" = "system" ] && [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' "--system removes from /usr/local, so run it with sudo." >&2
  exit 1
fi

STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APP_ID"
AUTOSTART_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/$APP_ID.desktop"

printf '=== Removing %s ===\n\n' "$APP_NAME"

rm -f "$AUTOSTART_FILE" && printf '  autostart entry removed\n'
rm -f "$PREFIX/bin/$APP_ID" "$PREFIX/bin/$APP_ID-gui"
printf '  commands removed from %s/bin\n' "$PREFIX"
rm -f "$PREFIX/share/applications/$APP_ID.desktop"
printf '  desktop entry removed\n'
find "$PREFIX/share/icons/hicolor" -name "$APP_ID.png" -delete 2>/dev/null || true
find "$PREFIX/share/icons/hicolor" -name "$APP_ID.svg" -delete 2>/dev/null || true
printf '  icons removed\n'
rm -rf "$PREFIX/share/doc/$APP_ID"

printf '\n'
printf '%s\n' "Throwaway users (wtf1132a, wtf1132b, wtf1132c) are not removed here."
printf '%s\n' "Remove any that remain with: sudo userdel -r <name>"
printf '\n'

if [ -d "$STATE_DIR" ]; then
  printf '%s\n' "Backups and logs are in: $STATE_DIR"
  read -r -p "Delete them too? [y/N] " answer || answer=""
  case "$answer" in
    y | Y | yes | YES)
      rm -rf "$STATE_DIR"
      printf '  deleted\n'
      ;;
    *) printf '  kept\n' ;;
  esac
fi

printf '\nDone.\n'
