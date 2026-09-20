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

# The exact lines install.sh writes, plus the legacy forms older installs left
# behind. Removal is anchored so only our own lines are ever touched.
MINE_COMMENT='-- Blur and layer rules for the dock (see the AnimatedDock repo).'
REQUIRE_LINE='pcall(require, "hypr.dock") -- AnimatedDock'
REQUIRE_DETECT='^[[:space:]]*(pcall\(require, "hypr\.dock"\)( -- AnimatedDock)?|require\("hypr\.dock"\))([[:space:]]|$)'

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
  local dest=$1 base target
  base=$(readlink -f "$REPO")
  # A resolvable base is required; without it the "$base"/* pattern would
  # degrade to /* and match anything. If the checkout itself is gone there
  # is nothing this script can safely claim, so leave all links alone.
  [[ -n $base ]] || return 0
  target=$(readlink -f "$dest") 2>/dev/null
  # Owned if it resolves to the repo root itself or to a path *under* it —
  # boundary-aware so a sibling like "$REPO-old" is never matched. The bin
  # and hypr links resolve to files inside the repo, hence the "$base/"*
  # arm; a plain exact compare against $base would miss those.
  if [[ -L $dest && -n $target && ( $target == "$base" || $target == "$base"/* ) ]]; then
    rm -f "$dest"
    ok "removed ${dest/#$HOME/\~}"
  elif [[ -e $dest ]]; then
    warn "${dest/#$HOME/\~} is not a link into this repo — left in place."
  fi
}

unlink_ours "$HOME/.config/omarchy/plugins/animated.dock"
unlink_ours "$HOME/.local/bin/omarchy-dock-config"
unlink_ours "$HOME/.config/hypr/dock.lua"

if [[ -f $HYPRLAND_LUA ]] && grep -Eq "$REQUIRE_DETECT" "$HYPRLAND_LUA"; then
  cp "$HYPRLAND_LUA" "$HYPRLAND_LUA.bak.$STAMP"
  # Drop only the exact comment and require lines the installer wrote (in the
  # current or legacy forms) — never any other line that merely mentions
  # require(...).
  sed -E -i -e "/^-- Blur and layer rules for the dock (see the AnimatedDock repo)\.$/d" \
    -e "/^pcall\(require, \"hypr\.dock\"\)( -- AnimatedDock)?$/d" \
    -e "/^require\(\"hypr\.dock\"\)$/d" "$HYPRLAND_LUA"
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