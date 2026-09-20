#!/bin/bash
#
# Install the animated.dock Omarchy shell plugin from this repo.
#
# Everything is deployed as a symlink back into this checkout, so the repo
# stays the single source of truth: edit here, commit here, and the live
# desktop follows. The one exception is shell.json, which is shared with the
# rest of the shell and so gets a merged entry rather than a link.
#
# Safe to re-run. Existing real files are backed up before being replaced,
# and an existing dock entry in shell.json is left alone unless you pass
# --replace-config.
#
# Usage: ./install.sh [--replace-config] [--dry-run]

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CFG="$HOME/.config/omarchy/shell.json"
PLUGIN_DEST="$HOME/.config/omarchy/plugins/animated.dock"
BIN_DEST="$HOME/.local/bin/omarchy-dock-config"
HYPR_DEST="$HOME/.config/hypr/dock.lua"
HYPRLAND_LUA="$HOME/.config/hypr/hyprland.lua"
# The exact lines this installer writes into hyprland.lua, and the anchored
# pattern used to detect them (and the legacy forms from older installs) so a
# re-run never appends a duplicate. Matches lines *starting* with the require,
# never unrelated require() calls elsewhere in the file.
MINE_COMMENT='-- Blur and layer rules for the dock (see the AnimatedDock repo).'
REQUIRE_LINE='pcall(require, "hypr.dock") -- AnimatedDock'
REQUIRE_DETECT='^[[:space:]]*(pcall\(require, "hypr\.dock"\)( -- AnimatedDock)?|require\("hypr\.dock"\))([[:space:]]|$)'
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
STAMP="$(date +%s)"

REPLACE_CONFIG=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --replace-config) REPLACE_CONFIG=true ;;
    --dry-run) DRY_RUN=true ;;
    -h | --help)
      sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^#\s\?//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

# ----------------------------------------------------------------- plumbing

info() { printf '\033[36m::\033[0m %s\n' "$1"; }
ok() { printf '\033[32m ✓\033[0m %s\n' "$1"; }
warn() { printf '\033[33m !\033[0m %s\n' "$1" >&2; }
die() {
  printf '\033[31m ✗\033[0m %s\n' "$1" >&2
  exit 1
}

run() {
  if $DRY_RUN; then
    printf '   would run: %s\n' "$*"
  else
    "$@"
  fi
}

# Point $2 at $1, moving anything real that is already there out of the way.
# A link that already resolves to the right place is left untouched so the
# script stays quiet on re-runs.
link() {
  local src=$1 dest=$2

  if [[ -L $dest ]]; then
    if [[ "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
      ok "${dest/#$HOME/\~} already linked"
      return
    fi
    run rm -f "$dest"
  elif [[ -e $dest ]]; then
    run mv "$dest" "$dest.bak.$STAMP"
    warn "moved existing ${dest##*/} aside to ${dest##*/}.bak.$STAMP"
  fi

  run mkdir -p "$(dirname -- "$dest")"
  run ln -sfn "$src" "$dest"
  ok "${dest/#$HOME/\~} → ${src/#$HOME/\~}"
}

# ------------------------------------------------------------ prerequisites

command -v jq >/dev/null 2>&1 || die "jq is required but not installed."
[[ -d $OMARCHY_PATH ]] || warn "$OMARCHY_PATH not found — is this an Omarchy system?"

# ------------------------------------------------------------------- files

info "Linking plugin, configurator, and Hyprland settings"
link "$REPO" "$PLUGIN_DEST"
link "$REPO/bin/omarchy-dock-config" "$BIN_DEST"
link "$REPO/hypr/dock.lua" "$HYPR_DEST"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) warn "~/.local/bin is not on PATH — omarchy-dock-config will not be callable by name." ;;
esac

# ------------------------------------------------------- hyprland.lua wiring
#
# pcall keeps a missing dock.lua from taking the whole Hyprland config down
# with it, so removing this checkout degrades to "no blur" rather than "no
# window manager config".

info "Wiring hypr/dock.lua into hyprland.lua"
if [[ ! -f $HYPRLAND_LUA ]]; then
  warn "$HYPRLAND_LUA not found — add '$REQUIRE_LINE' to your Hyprland config by hand."
elif grep -Eq "$REQUIRE_DETECT" "$HYPRLAND_LUA"; then
  ok "hyprland.lua already requires hypr.dock"
elif $DRY_RUN; then
  printf '   would append to hyprland.lua: %s\n' "$REQUIRE_LINE"
else
  cp "$HYPRLAND_LUA" "$HYPRLAND_LUA.bak.$STAMP"
  printf '\n%s\n%s\n' "$MINE_COMMENT" "$REQUIRE_LINE" >>"$HYPRLAND_LUA"
  ok "appended require to hyprland.lua (backup: hyprland.lua.bak.$STAMP)"
fi

# ------------------------------------------------- fresh-install default items
#
# A brand-new dock starts with the four essentials — the Omarchy Menu, a file
# manager, the user's default terminal, and their default browser — so it is
# usable the moment it appears and everything else is one right-click away
# (Unpin, pin running apps). Terminal/browser are resolved from the user's own
# XDG/Omarchy defaults rather than hardcoded, so the seeded set matches the
# machine it lands on.

resolve_file_manager() {
  local apps="/usr/share/applications:$HOME/.local/share/applications"
  local cand
  for cand in org.gnome.Nautilus org.kde.dolphin thunar nemo caja pcmanfm; do
    if [[ -f /usr/share/applications/$cand.desktop || -f "$HOME/.local/share/applications/$cand.desktop" ]]; then
      echo "$cand"
      return
    fi
  done
  echo "org.gnome.Nautilus"
}

# Real desktop id (no .desktop suffix) for the user's default terminal.
resolve_terminal() {
  local id=""
  id=$(xdg-terminal-exec --print-id 2>/dev/null || true)
  id=${id%%:*}
  id=${id%.desktop}
  if [[ -n $id ]] && { [[ -f /usr/share/applications/$id.desktop ]] || [[ -f "$HOME/.local/share/applications/$id.desktop" ]]; }; then
    echo "$id"
    return
  fi
  # Omarchy's CLI reports a friendly label; map it back to a real desktop id.
  id=$(omarchy-default-terminal 2>/dev/null || true)
  case "$id" in
    kitty) echo "kitty"; return ;;
    foot) echo "foot"; return ;;
    ghostty) echo "com.mitchellh.ghostty"; return ;;
    alacritty)
      [[ -f /usr/share/applications/org.alacritty.desktop ]] && { echo "org.alacritty"; return; }
      echo "alacritty"; return
      ;;
  esac
  local cand
  for cand in kitty foot com.mitchellh.ghostty alacritty wezterm xfce4-terminal org.gnome.Terminal xterm; do
    if [[ -f /usr/share/applications/$cand.desktop || -f "$HOME/.local/share/applications/$cand.desktop" ]]; then
      echo "$cand"
      return
    fi
  done
  echo "kitty"
}

# Real desktop id for the user's default browser; `xdg-settings` is the XDG
# authority, with `$BROWSER` unset so it reports the xdg-config default.
resolve_browser() {
  local id=""
  id=$(env -u BROWSER xdg-settings get default-web-browser 2>/dev/null || true)
  id=${id%.desktop}
  if [[ -n $id ]] && { [[ -f /usr/share/applications/$id.desktop ]] || [[ -f "$HOME/.local/share/applications/$id.desktop" ]]; }; then
    echo "$id"
    return
  fi
  local cand
  for cand in firefox chromium google-chrome brave-browser microsoft-edge zen vivaldi-stable; do
    if [[ -f /usr/share/applications/$cand.desktop || -f "$HOME/.local/share/applications/$cand.desktop" ]]; then
      echo "$cand"
      return
    fi
  done
  echo "firefox"
}

# The `items` array for a fresh dock, as JSON: Menu, Files, terminal, browser.
default_items() {
  jq -nc \
    --arg fm "$(resolve_file_manager)" \
    --arg term "$(resolve_terminal)" \
    --arg browser "$(resolve_browser)" \
    '[
      { "showApps": true, "label": "Omarchy Menu", "tint": true },
      { "desktop": $fm },
      { "desktop": $term },
      { "desktop": $browser }
    ]'
}

# --------------------------------------------------------------- shell.json
#
# shell.json belongs to the whole shell, not just the dock, so it is merged
# rather than linked. The write is staged in a temp file and only swapped in
# once jq confirms the result still parses and still holds a dock entry: a
# broken shell.json costs the entire bar, not just this plugin.

info "Seeding the dock entry in shell.json"
CREATED_CFG=false
if [[ ! -f $CFG ]]; then
  if $DRY_RUN; then
    printf '   would create %s from Omarchy defaults\n' "$CFG"
  else
    CREATED_CFG=true
    mkdir -p "$(dirname -- "$CFG")"
    if [[ -f "$OMARCHY_PATH/config/omarchy/shell.json" ]]; then
      cp "$OMARCHY_PATH/config/omarchy/shell.json" "$CFG"
    else
      echo '{"plugins":[]}' >"$CFG"
    fi
    ok "created shell.json from defaults"
  fi
fi

seed_config() {
  local tmp dock
  tmp=$(mktemp "$CFG.XXXXXX") || die "could not stage a shell.json update."

  # The dock entry's style keys stay the repo's defaults from
  # config/shell.dock.json; only `items` is swapped for the per-user set.
  if ! dock=$(jq -c --argjson items "$(default_items)" '.items = $items' "$REPO/config/shell.dock.json" 2>/dev/null); then
    rm -f "$tmp"
    die "could not build the default dock entry."
  fi

  if ! jq --argjson dock "$dock" \
    '.plugins = ((.plugins // []) | map(select(.id != "animated.dock")) + [$dock])' \
    "$CFG" >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    die "failed to merge the dock entry — shell.json is unchanged."
  fi

  if ! jq -e --argjson dock "$dock" '
      .plugins[] | select(.id == "animated.dock") | .items' "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    die "merge dropped the dock items — shell.json is unchanged."
  fi

  # Nothing to preserve when this run created the file a moment ago.
  $CREATED_CFG || cp "$CFG" "$CFG.bak.$STAMP"
  mv "$tmp" "$CFG"
}

backup_note() { $CREATED_CFG || printf ' (backup: shell.json.bak.%s)' "$STAMP"; }

if $DRY_RUN; then
  printf '   would seed the dock entry with items: %s\n' "$(default_items | jq -c .)"
elif $REPLACE_CONFIG; then
  seed_config
  ok "replaced the dock entry with this machine's defaults$(backup_note)"
elif jq -e '.plugins[]? | select(.id=="animated.dock") | has("items")' "$CFG" >/dev/null 2>&1; then
  ok "kept your existing dock entry (pass --replace-config to reset it to defaults)"
else
  seed_config
  ok "seeded the default dock entry$(backup_note)"
fi

# ------------------------------------------------------------------- reload

if ! $DRY_RUN; then
  info "Reloading"
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell -q shell rescanPlugins && ok "shell rescanned plugins" ||
      warn "could not reach the shell — run 'omarchy restart shell' when it is up."
  fi
  if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null && ok "hyprland reloaded"
    errors=$(hyprctl configerrors 2>/dev/null)
    [[ $errors == "no errors" || -z $errors ]] || warn "hyprctl configerrors: $errors"
  fi
fi

cat <<EOF

Done. Hover the bottom edge of the screen to reveal the dock.

  Configure it:  omarchy-dock-config --help   (right-click the dock too)
  Remove it:     ./uninstall.sh
EOF