#!/bin/bash
#
# Remove everything install.sh put in place.
#
# Only symlinks that point back into this checkout are removed, so a plugin
# directory or configurator you installed some other way is left alone. Your
# dock settings in shell.json are kept unless you pass --purge-config.
#
# Usage: ./uninstall.sh [--purge-config]

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CFG="$HOME/.config/omarchy/shell.json"
HYPRLAND_LUA="$HOME/.config/hypr/hyprland.lua"
STAMP="$(date +%s)"

PURGE_CONFIG=false
for arg in "$@"; do
  case "$arg" in
    --purge-config) PURGE_CONFIG=true ;;
    -h | --help)
      sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^#\s\?//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

ok() { printf '\033[32m ✓\033[0m %s\n' "$1"; }
warn() { printf '\033[33m !\033[0m %s\n' "$1" >&2; }

unlink_ours() {
  local dest=$1
  if [[ -L $dest && "$(readlink -f "$dest")" == "$REPO"* ]]; then
    rm -f "$dest"
    ok "removed ${dest/#$HOME/\~}"
  elif [[ -e $dest ]]; then
    warn "${dest/#$HOME/\~} is not a link into this repo — left in place."
  fi
}

unlink_ours "$HOME/.config/omarchy/plugins/animated.dock"
unlink_ours "$HOME/.local/bin/omarchy-dock-config"
unlink_ours "$HOME/.config/hypr/dock.lua"

if [[ -f $HYPRLAND_LUA ]] && grep -qF 'require("hypr.dock")' "$HYPRLAND_LUA"; then
  cp "$HYPRLAND_LUA" "$HYPRLAND_LUA.bak.$STAMP"
  # Drop the require and the comment line the installer wrote above it.
  sed -i '/^-- Blur and layer rules for the dock/d; /require("hypr\.dock")/d' "$HYPRLAND_LUA"
  ok "removed the hypr.dock require (backup: hyprland.lua.bak.$STAMP)"
fi

if $PURGE_CONFIG && [[ -f $CFG ]]; then
  tmp=$(mktemp "$CFG.XXXXXX")
  if jq '.plugins = ((.plugins // []) | map(select(.id != "animated.dock")))' "$CFG" >"$tmp" 2>/dev/null &&
    jq -e . "$tmp" >/dev/null 2>&1; then
    cp "$CFG" "$CFG.bak.$STAMP"
    mv "$tmp" "$CFG"
    ok "removed the dock entry from shell.json (backup: shell.json.bak.$STAMP)"
  else
    rm -f "$tmp"
    warn "could not edit shell.json — left unchanged."
  fi
elif [[ -f $CFG ]]; then
  ok "kept your dock settings in shell.json (pass --purge-config to drop them)"
fi

command -v omarchy-shell >/dev/null 2>&1 && omarchy-shell -q shell rescanPlugins
if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl reload >/dev/null || true
fi

echo
echo "Uninstalled. This checkout is untouched — ./install.sh puts it all back."