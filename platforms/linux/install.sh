#!/usr/bin/env bash
#
# Install 1132.WTF on Linux.
#
#   ./install.sh              install for the current user, into ~/.local
#   ./install.sh --system     install for everyone, into /usr/local (needs root)
#   ./install.sh --prefix DIR install into DIR
#
# Follows the freedesktop layout, so the app shows up in the launcher with its
# icon and its right-click actions.

set -u
set -o pipefail

APP_NAME="1132.WTF"
APP_ID="1132wtf"
HERE="$(cd "$(dirname "$0")" && pwd)"

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

BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
ICON_DIR="$PREFIX/share/icons/hicolor"
DOC_DIR="$PREFIX/share/doc/$APP_ID"

if [ "$MODE" = "system" ] && [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' "--system installs into /usr/local, so run it with sudo." >&2
  exit 1
fi

printf '=== Installing %s ===\n' "$APP_NAME"
printf 'prefix: %s\n\n' "$PREFIX"

for required in "$HERE/$APP_ID" "$HERE/$APP_ID-gui" "$HERE/$APP_ID.desktop"; do
  if [ ! -f "$required" ]; then
    printf '%s\n' "Missing from the package: $required" >&2
    exit 1
  fi
done

install -d "$BIN_DIR" "$APP_DIR" "$DOC_DIR"
install -m 755 "$HERE/$APP_ID" "$BIN_DIR/$APP_ID"
install -m 755 "$HERE/$APP_ID-gui" "$BIN_DIR/$APP_ID-gui"
printf '  installed %s\n' "$BIN_DIR/$APP_ID"
printf '  installed %s\n' "$BIN_DIR/$APP_ID-gui"

# The desktop entry calls the wrapper by name, so make sure the name resolves
# even when the prefix is not on PATH.
sed -e "s|^Exec=$APP_ID-gui|Exec=$BIN_DIR/$APP_ID-gui|" \
  -e "s|^TryExec=$APP_ID-gui|TryExec=$BIN_DIR/$APP_ID-gui|" \
  -e "s|^Exec=$APP_ID-gui |Exec=$BIN_DIR/$APP_ID-gui |" \
  "$HERE/$APP_ID.desktop" >"$APP_DIR/$APP_ID.desktop"
chmod 644 "$APP_DIR/$APP_ID.desktop"
printf '  installed %s\n' "$APP_DIR/$APP_ID.desktop"

if [ -d "$HERE/icons/hicolor" ]; then
  while IFS= read -r icon; do
    relative="${icon#"$HERE/icons/hicolor/"}"
    install -d "$ICON_DIR/$(dirname "$relative")"
    install -m 644 "$icon" "$ICON_DIR/$relative"
  done < <(find "$HERE/icons/hicolor" -type f)
  printf '  installed icons into %s\n' "$ICON_DIR"
fi

[ -f "$HERE/README.md" ] && install -m 644 "$HERE/README.md" "$DOC_DIR/README.md"

# Refresh the caches so the launcher notices immediately.
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f "$ICON_DIR" >/dev/null 2>&1 || true
fi

printf '\nDone.\n\n'

case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *)
    printf '%s\n' "Note: $BIN_DIR is not on your PATH."
    printf '%s\n' "Add this to your shell profile to use the '$APP_ID' command:"
    printf '%s\n\n' "  export PATH=\"\$PATH:$BIN_DIR\""
    ;;
esac

printf '%s\n' "Open it from your launcher as \"$APP_NAME\", or run:"
printf '%s\n' "  $APP_ID status"
printf '%s\n' "  $APP_ID fix"
printf '\n'
