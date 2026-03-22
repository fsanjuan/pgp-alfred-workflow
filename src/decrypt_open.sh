#!/bin/bash
# decrypt_open.sh - Decrypt a GPG-encrypted file and open it without writing to disk.
#
# Arguments:
#   $1: path to the encrypted file (.gpg, .pgp, or .asc)
#
# Creates a temporary RAM disk, decrypts into it, opens the file with the
# default macOS app, then ejects the RAM disk once the user closes the file.
# Plaintext never touches the SSD.
#
# Debug mode: touch ~/.config/alfred-pgp/debug to enable logging to ~/.config/alfred-pgp/debug.log

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

debug() { [[ -f "${HOME}/.config/alfred-pgp/debug" ]] && echo "$*" >> "${HOME}/.config/alfred-pgp/debug.log"; }

error_dialog() {
    osascript - "$1" <<'EOF'
on run argv
    display dialog (item 1 of argv) with title "PGP Encrypt/Decrypt" buttons {"OK"} default button "OK" with icon caution
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

# Determine output filename by stripping known encrypted extensions
basename=$(basename "$input")
if [[ "$basename" == *.gpg ]] || [[ "$basename" == *.pgp ]] || [[ "$basename" == *.asc ]]; then
    outname="${basename%.*}"
else
    outname="${basename}.decrypted"
fi

# Size the RAM disk: 2x the encrypted file size + 16MB overhead, minimum 32MB
# Hard cap of 512MB — files larger than this should use "Decrypt and Save" instead
file_size=$(stat -f%z "$input" 2>/dev/null || echo 0)
max_bytes=$((512 * 1024 * 1024))
min_bytes=$((32 * 1024 * 1024))
needed_bytes=$((file_size * 2 + 16 * 1024 * 1024))
if [[ $needed_bytes -gt $max_bytes ]]; then
    error_dialog "This file is too large to decrypt and open in memory (max 512 MB). Use \"Decrypt and Save\" instead."
    exit 0
fi
disk_bytes=$(( needed_bytes > min_bytes ? needed_bytes : min_bytes ))
sectors=$((disk_bytes / 512))

# Create RAM disk
vol_name="alfred-pgp-$$"
disk_dev=$(hdiutil attach -nomount ram://$sectors 2>/dev/null)
if [[ -z "$disk_dev" ]]; then
    error_dialog "Error: could not create secure RAM disk."
    exit 0
fi
disk_dev=$(echo "$disk_dev" | tr -d '[:space:]')

if ! diskutil erasevolume HFS+ "$vol_name" "$disk_dev" > /dev/null 2>&1; then
    hdiutil detach "$disk_dev" > /dev/null 2>&1
    error_dialog "Error: could not format secure RAM disk."
    exit 0
fi

volumes_dir="${VOLUMES_DIR:-/Volumes}"
tmp_output="$volumes_dir/$vol_name/$outname"

debug "RAM disk: $disk_dev mounted at $volumes_dir/$vol_name"

# Decrypt into the RAM disk
error_log=$(mktemp)
if gpg --batch --yes \
       --decrypt \
       --output "$tmp_output" \
       "$input" 2>"$error_log"; then
    rm -f "$error_log"
    debug "gpg succeeded, opening $tmp_output"
    open "$tmp_output"

    # Background: wait for the app to open the file, then wait for it to close,
    # then eject the RAM disk. Polling avoids any fixed sleep race condition.
    # ALFRED_PGP_OPEN_TIMEOUT_ITERS controls max iterations (default 60 = 30s).
    max_iters="${ALFRED_PGP_OPEN_TIMEOUT_ITERS:-60}"
    (
        # Wait up to max_iters × 0.5s for the app to open the file
        wait_count=0
        while ! lsof "$tmp_output" > /dev/null 2>&1; do
            sleep 0.5
            wait_count=$((wait_count + 1))
            [[ $wait_count -ge $max_iters ]] && break
        done

        # Wait until the app closes the file
        while lsof "$tmp_output" > /dev/null 2>&1; do
            sleep 2
        done

        hdiutil detach "$disk_dev" > /dev/null 2>&1
        debug "RAM disk ejected: $disk_dev"
    ) &
else
    error=$(cat "$error_log")
    rm -f "$error_log"
    debug "gpg failed: $error"
    hdiutil detach "$disk_dev" > /dev/null 2>&1
    short_error=$(echo "$error" | tail -1)
    error_dialog "Decryption failed: $short_error"
fi
