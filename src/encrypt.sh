#!/bin/bash
# encrypt.sh - Encrypt a file with GPG for a given recipient.
#
# Arguments:
#   $1: recipient key fingerprint (from Alfred Script Filter selection)
#
# Alfred env vars:
#   $filepath: path to the file to encrypt (set by Script Filter JSON variables)

# Ensure common GPG install locations are in PATH
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

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
    echo "Encrypted: $(basename "$output")"
else
    error=$(cat "$error_log")
    rm -f "$error_log"
    if echo "$error" | grep -q "Unusable public key"; then
        echo "Key not trusted. Run in Terminal: gpg --edit-key $recipient → trust → 5 → quit"
    else
        short_error=$(echo "$error" | tail -1)
        echo "Encryption failed: $short_error"
    fi
fi
