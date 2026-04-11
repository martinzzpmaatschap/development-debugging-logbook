# Case #003: Espanso Detection Failure on Ubuntu 24.04 — GNOME Shortcuts Workaround

> **TL;DR:** Espanso 2.3.0 installed correctly on Ubuntu 24.04 + GNOME + Xorg, parsed YAML correctly, could inject text — but completely failed to detect keystrokes. Workaround: bind GNOME custom keyboard shortcuts directly to `espanso match exec --trigger "..."` commands, bypassing Espanso's broken detection layer entirely.

## Environment

| Component | Version |
|-----------|---------|
| OS | Ubuntu 24.04 LTS |
| Kernel | 6.8.0-106-generic |
| Desktop | GNOME 46 |
| Display Server | Xorg (pure, no Xwayland) |
| Espanso | 2.3.0 (X11 AppImage from GitHub releases) |
| Browser | Google Chrome (current stable) |
| Target app | claude.ai (Lexical contenteditable editor) |

## Goal

Install 4 custom prompt templates as Espanso text expansion triggers:
- `;trustcheck` — Communication risk audit (~1700 chars)
- `;trustreview` — Weekly trust review (~1200 chars)
- `;trustpitch` — Pitch translator (~1100 chars)
- `;trustfix` — Recovery protocol (~1000 chars)

Each prompt is a multi-section LLM system prompt with a `$|$` cursor anchor at the end so the user can immediately type/paste their content after expansion.

## Initial Symptom

After clean installation and `espanso restart`:
- `espanso status` returned `espanso is running` ✅
- `espanso match list` correctly listed all 4 triggers ✅
- Typing `;trustcheck` in any text field (Chrome, gedit, terminal) → **nothing happened** ❌
- No new entries in `espanso log` after typing ❌

## Debugging Timeline

### Hypothesis 1: YAML config error
```bash
espanso match list | grep trust
```
**Result:** All 4 matches loaded correctly with full content. ❌ Not the cause.

### Hypothesis 2: Service not running
```bash
espanso status
ps aux | grep espanso
```
**Result:** Daemon, worker, and service processes all running. ❌ Not the cause.

### Hypothesis 3: Wayland session despite X11 reporting
```bash
echo $XDG_SESSION_TYPE
# → x11
ps aux | grep -E "Xorg|Xwayland" | grep -v grep
# → /usr/lib/xorg/Xorg vt2 -displayfd 3 -auth ... (no Xwayland)
```
**Result:** Pure Xorg session confirmed. ❌ Not the cause.

The misleading log line:
```
[INFO] kdotool missing or not available for the current wayland DE.
```
This appears even on pure X11 sessions and is **not** an indicator of the actual problem.

### Hypothesis 4: Chrome contenteditable rejection
Tested in gedit (native GTK textarea, not contenteditable):
```bash
gedit &
# Click in document, type ;trustcheck
```
**Result:** Failed in gedit too. ❌ Not Chrome-specific.

### Hypothesis 5: Wrong injection backend (inject vs clipboard)
Updated YAML with `force_mode: clipboard` for all triggers — recommended fix from [official Espanso docs](https://espanso.org/docs/matches/basics/) for unreliable expansions in browser contenteditables.

```yaml
matches:
  - trigger: ";trustcheck"
    force_mode: clipboard
    replace: |
      ...
```
**Result:** No improvement when typing trigger. ⚠️ But this fix mattered later.

### Hypothesis 6 (BREAKTHROUGH): Test detection and injection separately

The key realization: Espanso has two independent components — **detection** (sees keystrokes) and **injection** (writes text). They can fail independently. We should test them separately.

```bash
# Test injection ONLY (no detection involved)
gedit &
# Click in gedit, then in terminal:
sleep 5 && espanso match exec --trigger ";trustcheck"
```

**Result:** ✅ The full TrustGuard prompt appeared in gedit, with cursor positioned correctly at the `$|$` anchor.

**Conclusion:** Injection works perfectly. Clipboard mode works perfectly. Cursor positioning works perfectly. The ONLY broken component is **detection** — Espanso's `X11Source` keystroke listener doesn't see typed input on this system.

This matches symptoms in:
- [Espanso issue #2373](https://github.com/espanso/espanso/issues/2373) — Ubuntu 24.04 not working
- [Espanso issue #2334](https://github.com/espanso/espanso/issues/2334) — Service start failures on 24.10
- [Espanso issue #672](https://github.com/espanso/espanso/issues/672) — Detection failures across apps

## The Workaround

If detection is broken but injection works, we just need a way to **trigger `espanso match exec` without typing a string trigger**. Solution: GNOME custom keyboard shortcuts that execute the command directly.

GNOME's keybinding system operates at a different layer than Espanso's keylogger and works reliably on Ubuntu 24.04.

### Implementation

```bash
#!/bin/bash
# setup-trust-shortcuts.sh
# Binds 4 GNOME custom shortcuts to Espanso match exec commands

SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
KB_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# Register the 4 keybinding paths
gsettings set $SCHEMA custom-keybindings \
  "['$KB_PATH/trust1/', '$KB_PATH/trust2/', '$KB_PATH/trust3/', '$KB_PATH/trust4/']"

# Helper function
bind_shortcut() {
  local id=$1
  local name=$2
  local trigger=$3
  local key=$4
  local schema_path="$SCHEMA.custom-keybinding:$KB_PATH/trust$id/"
  
  gsettings set $schema_path name "$name"
  gsettings set $schema_path command "/usr/local/bin/espanso match exec --trigger \"$trigger\""
  gsettings set $schema_path binding "$key"
}

bind_shortcut 1 "Trust Check"  ";trustcheck"  "<Control><Alt>1"
bind_shortcut 2 "Trust Review" ";trustreview" "<Control><Alt>2"
bind_shortcut 3 "Trust Pitch"  ";trustpitch"  "<Control><Alt>3"
bind_shortcut 4 "Trust Fix"    ";trustfix"    "<Control><Alt>4"

echo "Done. Test with Ctrl+Alt+1 in any text field."
```

### Verification

```bash
# Confirm shortcuts registered
gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings
# Should output 4 paths

# Confirm shortcuts visible in GUI
gnome-control-center keyboard
# Settings → Keyboard → View and Customize Shortcuts → Custom Shortcuts
# Should show: Trust Check (Ctrl+Alt+1), Trust Review (Ctrl+Alt+2), etc.
```

### Functional test

1. Open Chrome → claude.ai
2. Click in chat input field
3. Press `Ctrl+Alt+1`
4. ✅ Full TrustGuard prompt appears in textarea, cursor at `$|$` anchor

**Result:** Works in claude.ai, gedit, Gmail compose, Slack web — every app where paste works.

## Why This Solution Is Actually Better

| Aspect | Original (typed trigger) | Workaround (keyboard shortcut) |
|--------|--------------------------|-------------------------------|
| Requires Espanso detection | Yes (broken) | No |
| Works in Electron apps | Unreliable | Yes |
| Works in contenteditables | Unreliable | Yes |
| Speed | Type 11 chars + wait | 1 key combination |
| Cognitive load | Remember 4 trigger spellings | Remember 1-2-3-4 |
| Conflict risk | Possible with normal text | Almost none |

`Ctrl+Alt+1` is faster than typing `;trustcheck`. The workaround is strictly superior to the intended solution for this use case.

## Lessons Learned

### 1. Test components independently before debugging the whole system
Espanso = detection + injection. They fail independently. The breakthrough came from testing them separately with `espanso match exec --trigger`. This should be the **first** diagnostic step for any Espanso bug, not the last.

### 2. Misleading log lines waste hours
The line `kdotool missing or not available for the current wayland DE` appears even on pure X11 systems. It's not an indicator of the actual problem. Don't trust log warnings without verification.

### 3. Layer-bypass workarounds beat fighting broken layers
Instead of debugging why Espanso's keylogger fails on this system, we bypassed the keylogger entirely by using GNOME's keybinding layer. When a component is structurally broken, route around it instead of trying to fix it.

### 4. Premature optimization is real even for personal tools
~90 minutes spent on tool installation for prompts that hadn't been used yet in real conversations. The user-facing value (the prompt content) was complete in 5 minutes. The remaining 85 minutes were spent on a delivery mechanism that hadn't proven its necessity.

### 5. "Facts, no assumptions"
Every wrong hypothesis (Wayland, Chrome contenteditable, clipboard backend) was a plausible-sounding assumption. Only direct testing with the right diagnostic command revealed the actual cause.

## Files

- [`trust_prompts.yml`](./trust_prompts.yml) — Espanso match file with `force_mode: clipboard`
- [`setup-trust-shortcuts.sh`](./setup-trust-shortcuts.sh) — GNOME shortcut binding script

## References

- [Espanso official docs — matches basics](https://espanso.org/docs/matches/basics/)
- [Espanso GitHub issue #2373](https://github.com/espanso/espanso/issues/2373)
- [Espanso GitHub issue #2334](https://github.com/espanso/espanso/issues/2334)
- [Espanso GitHub issue #672](https://github.com/espanso/espanso/issues/672)
- [Espanso GitHub issue #1575](https://github.com/espanso/espanso/issues/1575)

---

**Status:** ✅ Resolved
**Time invested:** ~90 minutes
**Outcome:** Working solution that's better than the original goal
