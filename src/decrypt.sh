#!/bin/bash
# decrypt.sh - Decrypt a GPG-encrypted file.
#
# Arguments:
#   $1: path to the encrypted file (.gpg or .pgp)
#
# GPG will invoke pinentry (via gpg-agent) for the passphrase if needed.
#
# Debug mode: touch /tmp/alfred-pgp-debug to enable logging to /tmp/alfred-pgp-debug.log

# Ensure common GPG install locations are in PATH
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

debug() { [[ -f /tmp/alfred-pgp-debug ]] && echo "$*" >> /tmp/alfred-pgp-debug.log; }

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

input="$1"

# Validate input
if [[ -z "$input" ]]; then
    error_dialog "Error: no file path provided."
    exit 0
fi

if [[ ! -f "$input" ]]; then
    error_dialog "Error: file not found: $input"
    exit 0
fi

# Determine output path by stripping known encrypted extensions
if [[ "$input" == *.gpg ]] || [[ "$input" == *.pgp ]] || [[ "$input" == *.asc ]]; then
    output="${input%.*}"
else
    output="${input}.decrypted"
fi

# If output already exists, ask the user before overwriting
if [[ -f "$output" ]]; then
    response=$(confirm_overwrite "$(basename "$output")")
    if [[ "$response" != "Overwrite" ]]; then
        exit 0
    fi
fi

# Run decryption, capturing stderr for error reporting
error_log=$(mktemp)
if gpg --batch --yes \
       --decrypt \
       --output "$output" \
       "$input" 2>"$error_log"; then
    rm -f "$error_log"
    debug "gpg succeeded"
    notify "Decrypted: $(basename "$output")"
else
    error=$(cat "$error_log")
    rm -f "$error_log"
    debug "gpg failed: $error"
    short_error=$(echo "$error" | tail -1)
    error_dialog "Decryption failed: $short_error"
fi
