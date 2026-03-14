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

debug "--- $(date) ---"
debug "argv[1]: $1"
debug "filepath: ${filepath:-<unset>}"

recipient="$1"
input="${filepath:-}"

# Validate inputs
if [[ -z "$input" ]]; then
    echo "Error: file path not provided (filepath variable not set)"
    exit 0
fi

if [[ ! -f "$input" ]]; then
    echo "Error: file not found: $input"
    exit 0
fi

if [[ -z "$recipient" ]]; then
    echo "Error: no recipient key selected"
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
    echo "Encrypted: $(basename "$output")"
else
    error=$(cat "$error_log")
    rm -f "$error_log"
    debug "gpg failed: $error"
    if echo "$error" | grep -q "Unusable public key"; then
        printf 'gpg --edit-key %s' "$recipient" | pbcopy
        echo "Key not trusted — trust command copied to clipboard. Paste and run it in Terminal."
    else
        short_error=$(echo "$error" | tail -1)
        echo "Encryption failed: $short_error"
    fi
fi
