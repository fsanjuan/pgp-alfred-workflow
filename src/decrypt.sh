#!/bin/bash
# decrypt.sh - Decrypt a GPG-encrypted file.
#
# Arguments:
#   $1: path to the encrypted file (.gpg or .pgp)
#
# GPG will invoke pinentry (via gpg-agent) for the passphrase if needed.

# Ensure common GPG install locations are in PATH
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

input="$1"

# Validate input
if [[ -z "$input" ]]; then
    echo "Error: no file path provided"
    exit 0
fi

if [[ ! -f "$input" ]]; then
    echo "Error: file not found: $input"
    exit 0
fi

# Determine output path by stripping known encrypted extensions
if [[ "$input" == *.gpg ]] || [[ "$input" == *.pgp ]] || [[ "$input" == *.asc ]]; then
    output="${input%.*}"
else
    output="${input}.decrypted"
fi

# Avoid overwriting an existing file — append a counter if needed
if [[ -f "$output" ]]; then
    base="$output"
    counter=1
    while [[ -f "$output" ]]; do
        output="${base}.${counter}"
        ((counter++))
    done
fi

# Run decryption, capturing stderr for error reporting
error_log=$(mktemp)
if gpg --batch --yes \
       --decrypt \
       --output "$output" \
       "$input" 2>"$error_log"; then
    rm -f "$error_log"
    echo "Decrypted: $(basename "$output")"
else
    error=$(cat "$error_log")
    rm -f "$error_log"
    short_error=$(echo "$error" | tail -1)
    echo "Decryption failed: $short_error"
fi
