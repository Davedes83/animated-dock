#!/bin/bash
#
# Behaviour tests for bin/omarchy-dock-config.
#
# The configurator is the single writer of ~/.config/omarchy/shell.json — a
# file the whole shell reads — and every path here is a read-modify-write of a
# file something else may be reading. So these run against a throwaway HOME
# with a synthetic shell.json and assert on the result: the right keys change,
# everything else is untouched, the file stays valid JSON, its permissions
# survive, and a rejected input changes nothing at all.
#
# Usage: ./tests/config-test.sh        (also run by CI)

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
CONFIG="$REPO/bin/omarchy-dock-config"

command -v jq >/dev/null 2>&1 || {
  echo "jq is required to run these tests" >&2
  exit 1
}

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  printf '  \033[32mok\033[0m   %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  \033[31mFAIL\033[0m %s\n' "$1"
  [[ -n ${2:-} ]] && printf '       %s\n' "$2"
}

check() {
  local name=$1 expected=$2 actual=$3
  if [[ $expected == "$actual" ]]; then
    pass "$name"
  else
    fail "$name" "expected [$expected], got [$actual]"
  fi
}

cfg() { HOME="$SANDBOX" "$CONFIG" "$@" 2>&1; }
cfg_rc() {
  HOME="$SANDBOX" "$CONFIG" "$@" >/dev/null 2>&1
  echo $?
}
cfgfile() { echo "$SANDBOX/.config/omarchy/shell.json"; }

# The dock entry as one line of compact JSON.
entry() { jq -c '(.plugins[] | select(.id == "animated.dock"))' "$(cfgfile)"; }
# A field of the dock entry: field '.items | length'
field() { entry | jq -cr "$1"; }
# The whole document, canonicalised so reformatting is not a difference.
whole() { jq -cS . "$(cfgfile)"; }

# A fresh sandbox holding a given shell.json body.
sandbox() {
  SANDBOX=$(mktemp -d)
  mkdir -p "$SANDBOX/.config/omarchy"
  printf '%s' "$1" >"$(cfgfile)"
  chmod 644 "$(cfgfile)"
}

# An unrelated plugin is in the fixture on purpose: every write must leave the
# rest of shell.json exactly as it found it.
BASE='{"bar":{"id":"omarchy.bar"},"plugins":[{"id":"other.plugin"},{"id":"animated.dock","iconSize":44,"items":[{"desktop":"kitty"},{"spacer":true},{"showApps":true}]}]}'
BASE_CANON=$(jq -cS . <<<"$BASE")

echo "omarchy-dock-config"
echo

# ------------------------------------------------------------------ items
echo "items"
# An appId with no desktop entry anywhere pins as a match-only item, which is
# the same shape on every machine — a real appId would resolve to a desktop
# entry and change the expectation with the host's installed software.
sandbox "$BASE"
cfg pin org.example.NotARealApp >/dev/null
check "pin appends a match-only item" '{"appId":"org.example.NotARealApp","label":"org.example.NotARealApp"}' "$(field '.items[3]')"
check "pin keeps the rest" 4 "$(field '.items | length')"

cfg pin org.example.NotARealApp >/dev/null
check "pin is idempotent" 4 "$(field '.items | length')"

sandbox "$BASE"
cfg pin org.example.OtherApp 1 >/dev/null
check "pin at an index" '{"appId":"org.example.OtherApp","label":"org.example.OtherApp"}' "$(field '.items[1]')"

sandbox "$BASE"
cfg unpin 0 >/dev/null
check "unpin drops the slot" 2 "$(field '.items | length')"
check "unpin renumbers the rest" '{"spacer":true}' "$(field '.items[0]')"

sandbox "$BASE"
cfg move 0 2 >/dev/null
check "move reorders" '{"showApps":true}' "$(field '.items[1]')"
cfg move 1 99 >/dev/null
check "move clamps to the end" '{"desktop":"kitty"}' "$(field '.items[1]')"

sandbox "$BASE"
check "unpin rejects a bad index" 1 "$(cfg_rc unpin 99)"
check "move rejects a bad source" 1 "$(cfg_rc move 9 0)"
check "unpin rejects a negative index" 1 "$(cfg_rc unpin -- -1)"
check "a rejected edit changes nothing" "$BASE_CANON" "$(whole)"

# -------------------------------------------------------------------- set
echo
echo "set"
sandbox "$BASE"
cfg set iconSize 60 >/dev/null
check "set writes a number" 60 "$(field '.iconSize')"
check "set leaves items alone" '{"desktop":"kitty"}' "$(field '.items[0]')"
check "set accepts booleans" "true" "$(
  cfg set monochrome true >/dev/null
  field '.monochrome'
)"
cfg set iconSize null >/dev/null
check "set null removes the key" "null" "$(field '.iconSize')"
check "a refused key is not written" "null" "$(field '.icnoSize')"

sandbox "$BASE"
check "an unknown key is refused" 1 "$(cfg_rc set icnoSize 99)"
check "set refuses id" 1 "$(cfg_rc set id '"x"')"
check "set refuses items" 1 "$(cfg_rc set items '[]')"
check "set rejects non-JSON" 1 "$(cfg_rc set iconSize 44abc)"
check "nothing was written" "$BASE_CANON" "$(whole)"

# -------------------------------------------------------------- integrity
echo
echo "config integrity"
sandbox "$BASE"
cfg set iconSize 60 >/dev/null
check "the file stays valid JSON" "yes" "$(jq -e . "$(cfgfile)" >/dev/null 2>&1 && echo yes)"
check "the bar section survives" "omarchy.bar" "$(jq -r '.bar.id' "$(cfgfile)")"
check "other plugins survive" "1" "$(jq -r '[.plugins[] | select(.id != "animated.dock")] | length' "$(cfgfile)")"
check "permissions survive" "644" "$(stat -c '%a' "$(cfgfile)")"
check "a backup is written" "yes" "$([[ -f $(cfgfile).bak ]] && echo yes)"

# Six writes in a row must not leave the directory littered forever.
sandbox "$BASE"
for i in 1 2 3 4 5 6 7 8; do cfg set iconSize "$i" >/dev/null; done
check "backups are pruned to the newest 5" "5" "$(find "$(dirname "$(cfgfile)")" -maxdepth 1 -name 'shell.json.bak.2*' | wc -l)"

# A file with no dock entry must not gain one, and must say why.
sandbox '{"plugins":[{"id":"other.plugin"}]}'
out=$(cfg set iconSize 60)
check "a missing entry is refused" 1 "$(cfg_rc set iconSize 60)"
check "the refusal explains itself" "yes" \
  "$(grep -q 'no animated.dock entry' <<<"$out" && echo yes)"

# seed-defaults must add what is missing without touching what is there.
sandbox '{"plugins":[{"id":"animated.dock","edge":"top","iconSize":60}]}'
cfg seed-defaults >/dev/null
check "seed keeps a hand-tuned key" "top" "$(field '.edge')"
check "seed keeps a hand-tuned number" 60 "$(field '.iconSize')"
check "seed adds the style defaults" 0.75 "$(field '.backgroundOpacity')"
check "seed adds the starter items" 4 "$(field '.items | length')"
cfg seed-defaults >/dev/null
check "seed is idempotent" 4 "$(field '.items | length')"

sandbox '{"plugins":[{"id":"animated.dock"}]}'
cfg seed-defaults >/dev/null
check "a bare entry gets the full defaults" 44 "$(field '.iconSize')"

sandbox "$BASE"
check "an entry with items is left alone" "yes" \
  "$(grep -q 'already has items' <<<"$(cfg seed-defaults)" && echo yes)"
check "…and its items are untouched" 3 "$(field '.items | length')"

# ---------------------------------------------------- dock-level subcommands
# The mirroring subcommands (opacity, corner-shape, glow*) only touch the
# taskbar when the matching sync flag is on, and turning it on installs
# taskbar support — which needs a real plugins dir. With the flags off they
# are plain dock writes, and that is what is exercised here.
echo
echo "dock-level subcommands"
sandbox "$BASE"
cfg opacity 0.5 >/dev/null
check "opacity sets the dock's own value" 0.5 "$(field '.backgroundOpacity')"
check "opacity leaves the taskbar alone" "null" "$(jq -r '.bar.backgroundOpacity // "null"' "$(cfgfile)")"
check "opacity accepts a percentage" 40 "$(
  cfg opacity 40 >/dev/null
  field '.backgroundOpacity'
)"
check "opacity rejects nonsense" 1 "$(cfg_rc opacity abc)"

sandbox "$BASE"
cfg corner-shape pill >/dev/null
check "corner-shape writes the shape" "pill" "$(field '.cornerShape')"
check "corner-shape leaves the taskbar alone" "null" "$(jq -r '.bar.cornerShape // "null"' "$(cfgfile)")"
check "corner-shape rejects a bad shape" 1 "$(cfg_rc corner-shape lozenge)"

sandbox "$BASE"
cfg glow true >/dev/null
check "glow writes the flag" "true" "$(field '.glow')"
cfg glow-amount 0.25 >/dev/null
check "glow-amount writes the strength" 0.25 "$(field '.glowAmount')"
cfg glow-focus bottom >/dev/null
check "glow-focus writes the emphasis" "bottom" "$(field '.glowFocus')"
check "glow-focus rejects a bad focus" 1 "$(cfg_rc glow-focus sideways)"

# ------------------------------------------------------------- read-only
echo
echo "read-only commands"
sandbox "$BASE"
check "default-items prints an array" "yes" \
  "$(cfg default-items | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 && echo yes)"
check "default-items writes nothing" "$BASE_CANON" "$(whole)"
rm -f "$(cfgfile)"
check "default-items needs no shell.json" 0 "$(cfg_rc default-items)"

sandbox "$BASE"
check "state prints the entry" "yes" "$(cfg state | jq -e '.iconSize == 44' >/dev/null 2>&1 && echo yes)"

# The help text is generated from the same list `set` validates against, so a
# key missing from one of them shows up here.
help_lists_keys() {
  local out missing=0 k
  out=$("$CONFIG" --help)
  for k in animation autohide backgroundOpacity border cornerShape edge edgeGap \
    fullWidth gaussianZoom glyphScale iconSize labels magnify monochrome \
    runningIndicator showWhenEmpty spacing tiles tooltips zoom zoomRaise; do
    grep -qw -- "$k" <<<"$out" || missing=1
  done
  [[ $missing == 0 ]] && echo yes
}
check "--help lists every settable key" "yes" "$(help_lists_keys)"

# -------------------------------------------------------------------- done
echo
if ((FAIL > 0)); then
  printf '\033[31m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
  exit 1
fi
printf '\033[32m%d passed\033[0m\n' "$PASS"
