#!/bin/bash
# encrypt.sh - Encrypt a file with GPG for a given recipient.
#
# Arguments:
#   $1: recipient key fingerprint (from Alfred Script Filter selection)
#
# Alfred env vars:
#   $filepath: path to the file to encrypt (set by Script Filter JSON variables)
#
# Debug mode: touch /tmp/alfred-pgp-debug to enable logging to /tmp/alfred-pgp-debug.log

# Ensure common GPG install locations are in PATH
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

debug() { [[ -f /tmp/alfred-pgp-debug ]] && echo "$*" >> /tmp/alfred-pgp-debug.log; }
notify() { osascript -e "display notification \"$1\" with title \"PGP Encrypt/Decrypt\""; }
error_dialog() { osascript -e "display dialog \"$1\" with title \"PGP Encrypt/Decrypt\" buttons {\"OK\"} default button \"OK\" with icon caution"; }

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
    error_dialog "Error: file not found:\n$input"
    exit 0
fi

if [[ -z "$recipient" ]]; then
    error_dialog "Error: no recipient key selected."
    exit 0
fi

output="${input}.gpg"

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
        printf 'gpg --edit-key %s' "$recipient" | pbcopy
        error_dialog "This key is not trusted by GPG.\n\nThe trust command has been copied to your clipboard:\n\ngpg --edit-key $recipient\n\nPaste and run it in Terminal, then type: trust → 5 → quit"
    else
        short_error=$(echo "$error" | tail -1)
        error_dialog "Encryption failed:\n$short_error"
    fi
fi
