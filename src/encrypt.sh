#!/bin/bash
# encrypt.sh - Encrypt a file with GPG for a given recipient.
#
# Arguments:
#   $1: recipient key fingerprint (from Alfred Script Filter selection)
#
# Alfred env vars:
#   $filepath: path to the file to encrypt (set by Script Filter JSON variables)
#
# Debug mode: touch ~/.config/alfred-pgp/debug to enable logging to ~/.config/alfred-pgp/debug.log

# Ensure common GPG install locations are in PATH
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

debug() { [[ -f "${HOME}/.config/alfred-pgp/debug" ]] && echo "$*" >> "${HOME}/.config/alfred-pgp/debug.log"; }

notify() {
    osascript - "$1" <<'EOF'
on run argv
    display notification (item 1 of argv) with title "PGP Encrypt/Decrypt"
end run
EOF
}

error_dialog() {
    osascript - "$1" <<'EOF'
on run argv
    display dialog (item 1 of argv) with title "PGP Encrypt/Decrypt" buttons {"OK"} default button "OK" with icon caution
end run
EOF
}

confirm_overwrite() {
    osascript - "$1" <<'EOF'
on run argv
    set response to display dialog ((item 1 of argv) & " already exists." & return & return & "Do you want to overwrite it?") with title "PGP Encrypt/Decrypt" buttons {"Cancel", "Overwrite"} default button "Cancel" with icon caution
    return button returned of response
end run
EOF
}

debug "--- $(date) ---"
debug "argv[1]: $1"
debug "filepath: ${filepath:-<unset>}"

recipient="$1"
input="${filepath:-}"

# Validate inputs
if [[ -z "$input" ]]; then
    error_dialog "Error: file path not provided."
    exit 0
fi

if [[ ! -f "$input" ]]; then
    error_dialog "Error: file not found: $input"
    exit 0
fi

if [[ -z "$recipient" ]]; then
    error_dialog "Error: no recipient key selected."
    exit 0
fi

if [[ ! "$recipient" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    error_dialog "Error: invalid key fingerprint."
    exit 0
fi

output="${input}.gpg"

# If output already exists, ask the user before overwriting
if [[ -f "$output" ]]; then
    response=$(confirm_overwrite "$(basename "$output")")
    if [[ "$response" != "Overwrite" ]]; then
        exit 0
    fi
fi

# Run encryption, capturing stderr for error reporting
error_log=$(mktemp)
if gpg --batch --yes \
       --encrypt \
       --recipient "$recipient" \
       --output "$output" \
       "$input" 2>"$error_log"; then
    rm -f "$error_log"
    debug "gpg succeeded"
    notify "Encrypted: $(basename "$output")"
else
    error=$(cat "$error_log")
    rm -f "$error_log"
    debug "gpg failed: $error"
    if echo "$error" | grep -q "Unusable public key"; then
        local trust_cmd="gpg --edit-key $recipient"
        if printf '%s' "$trust_cmd" | pbcopy 2>/dev/null; then
            error_dialog "This key is not trusted by GPG.

The trust command has been copied to your clipboard:

$trust_cmd

Paste and run it in Terminal, then type: trust → 5 → quit"
        else
            error_dialog "This key is not trusted by GPG.

Run this command in Terminal, then try again:

$trust_cmd

Then type: trust → 5 → quit"
        fi
    else
        short_error=$(echo "$error" | tail -1)
        error_dialog "Encryption failed: $short_error"
    fi
fi
