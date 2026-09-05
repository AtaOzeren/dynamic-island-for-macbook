#!/bin/zsh
# Shows — and with --detach repairs — which applications Control Center
# believes own NotchFlow's menu bar item on macOS 26.
#
# Control Center attributes a status item to the application that launched the
# process, and hides the item if any owning application has "Allow in the Menu
# Bar" turned off. Launching NotchFlow from an agent or IDE terminal (Codex,
# Claude Code, VS Code) therefore lets that tool's switch hide NotchFlow.
#
# The store is TCC-protected: run this from a terminal with Full Disk Access.
# --clean also drops rows left by bare dev binaries (.build/…/NotchFlow) and
# throwaway probe bundles, so the Menu Bar pane lists NotchFlow once.
# --detach leaves NotchFlow owned only by itself, writes through cfprefsd (a
# plain file copy is overwritten from cfprefsd's cache), restarts Control
# Center with SIGKILL so it cannot persist stale memory on exit, and relaunches
# the app.
set -euo pipefail
BUNDLE_ID="${NOTCHFLOW_BUNDLE_ID:-com.notchflow.NotchFlow}"
STORE="$HOME/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter"
WORK="$(mktemp -d)"
cp "$STORE.plist" "$WORK/live.plist" 2>/dev/null || { echo "cannot read Control Center store — give this terminal Full Disk Access (System Settings › Privacy & Security)"; exit 1; }
python3 - "$WORK/live.plist" "$WORK/fixed.plist" "$BUNDLE_ID" "${1:-}" <<'PY'
import plistlib, sys
src, dst, bid, mode = sys.argv[1:5]
d = plistlib.load(open(src, 'rb'))
apps = plistlib.loads(d['trackedApplications'])          # flat [key, value, key, value, ...]
def is_target(x): return isinstance(x, dict) and x.get('bundle', {}).get('_0') == bid
def name(k): return k['bundle']['_0'] if 'bundle' in k else 'adhoc:' + str(k.get('adhocBinary', {}).get('_0', {}).get('relative'))
owners = []
for i in range(0, len(apps) - 1, 2):
    key, val = apps[i], apps[i + 1]
    items = val.get('menuItemLocations', []) if isinstance(val, dict) else []
    if any(is_target(m) for m in items):
        owners.append((name(key), val.get('isAllowed')))
        if mode == '--detach' and not is_target(key):
            val['menuItemLocations'] = [m for m in items if not is_target(m)]
junk_apps = []   # tracked-application rows that only exist because a bare dev binary or a probe once showed an item
junk_items = []  # menu items of throwaway probe bundles
if mode == '--clean':
    kept = []
    for i in range(0, len(apps) - 1, 2):
        key, val = apps[i], apps[i + 1]
        n = name(key)
        if n.startswith('adhoc:') and ('/.build/' in n or n.endswith('/probe') or '/Xcode.app/Contents/Developer/' in n):
            junk_apps.append(n); continue
        if isinstance(val, dict):
            before = val.get('menuItemLocations', [])
            keep = [m for m in before if not (isinstance(m, dict) and 'bundle' in m and
                    (m['bundle']['_0'].startswith('com.notchflow.') and m['bundle']['_0'] != bid or m['bundle']['_0'].startswith('com.probe.')))]
            junk_items += [m['bundle']['_0'] for m in before if m not in keep]
            val['menuItemLocations'] = keep
            if not is_target(key):
                val['menuItemLocations'] = [m for m in val['menuItemLocations'] if not is_target(m)]
        kept += [key, val]
    apps = kept
    print('removed rows:', junk_apps or 'none'); print('removed probe items:', sorted(set(junk_items)) or 'none')
    owners = [(name(apps[i]), apps[i + 1].get('isAllowed')) for i in range(0, len(apps) - 1, 2)
              if any(is_target(m) for m in apps[i + 1].get('menuItemLocations', []))]
print(f'{bid} menu bar item is owned by:')
for n, allowed in owners: print(f'  {n:45} allowed={allowed}')
blocked = [n for n, a in owners if a is False]
print('BLOCKED by: ' + ', '.join(blocked) if blocked else 'not blocked by any owner')
if mode in ('--detach', '--clean'):
    d['trackedApplications'] = plistlib.dumps(apps, fmt=plistlib.FMT_BINARY)
    plistlib.dump(d, open(dst, 'wb'), fmt=plistlib.FMT_BINARY)
PY
if [[ "${1:-}" == "--detach" || "${1:-}" == "--clean" ]]; then
  defaults import "$STORE" "$WORK/fixed.plist"
  killall -KILL ControlCenter 2>/dev/null || true
  sleep 3
  osascript -e 'quit app "NotchFlow"' 2>/dev/null || true; sleep 2
  open -b "$BUNDLE_ID" 2>/dev/null || true
  echo "detached and relaunched; original store kept at $WORK/live.plist"
fi
