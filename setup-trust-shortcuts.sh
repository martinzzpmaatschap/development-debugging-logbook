#!/bin/bash
# =============================================================================
# setup-trust-shortcuts.sh
# 
# Binds 4 GNOME custom keyboard shortcuts to Espanso match exec commands.
# Workaround for Espanso 2.3.0 detection failure on Ubuntu 24.04.
# 
# See case-003-espanso-detection-failure.md for full context.
#
# Usage:
#   chmod +x setup-trust-shortcuts.sh
#   ./setup-trust-shortcuts.sh
#
# Verify after running:
#   gnome-control-center keyboard
#   → Settings → Keyboard → View and Customize Shortcuts → Custom Shortcuts
# =============================================================================

set -e

SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
KB_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
ESPANSO_BIN="/usr/local/bin/espanso"

# Verify Espanso is installed
if ! command -v espanso &> /dev/null; then
    echo "ERROR: espanso not found at $ESPANSO_BIN"
    echo "Install Espanso first: https://espanso.org/docs/install/linux"
    exit 1
fi

# Verify trust matches exist in Espanso config
if ! espanso match list 2>/dev/null | grep -q ";trustcheck"; then
    echo "ERROR: ;trustcheck match not found in Espanso config"
    echo "Make sure trust_prompts.yml is in ~/.config/espanso/match/"
    exit 1
fi

echo "Registering 4 custom keybindings..."

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
  gsettings set $schema_path command "$ESPANSO_BIN match exec --trigger \"$trigger\""
  gsettings set $schema_path binding "$key"
  
  echo "  ✅ $name → $key → $trigger"
}

bind_shortcut 1 "Trust Check"  ";trustcheck"  "<Control><Alt>1"
bind_shortcut 2 "Trust Review" ";trustreview" "<Control><Alt>2"
bind_shortcut 3 "Trust Pitch"  ";trustpitch"  "<Control><Alt>3"
bind_shortcut 4 "Trust Fix"    ";trustfix"    "<Control><Alt>4"

echo ""
echo "Done. Test with Ctrl+Alt+1 in any text field (claude.ai, gedit, Gmail, etc.)"
echo ""
echo "To verify in GUI:"
echo "  gnome-control-center keyboard"
echo "  → View and Customize Shortcuts → Custom Shortcuts"
