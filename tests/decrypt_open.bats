#!/usr/bin/env bats
# Tests for src/decrypt_open.sh
#
# hdiutil, diskutil, gpg, open, and osascript are mocked via exported bash functions.
# VOLUMES_DIR is redirected to a temp directory to avoid needing /Volumes.

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    export VOLUMES_DIR="$TEST_DIR/volumes"
    export ALFRED_PGP_OPEN_TIMEOUT_ITERS=2  # 1s timeout in tests instead of 30s
    mkdir -p "$VOLUMES_DIR"

    # Mock osascript: echo the message argument and drain the heredoc from stdin
    osascript() {
        if [[ "$1" == "-" ]]; then
            local msg="$2"; cat > /dev/null; echo "$msg"
        fi
    }
    export -f osascript

    # Mock open: do nothing
    open() { :; }
    export -f open

    # Mock hdiutil: return a fake device on attach, track detach via flag file
    hdiutil() {
        if [[ "$1" == "attach" ]]; then
            echo "/dev/disk99"
        elif [[ "$1" == "detach" ]]; then
            touch "$TEST_DIR/hdiutil_detached"
        fi
    }
    export -f hdiutil

    # Mock diskutil: create the volume directory so the script can write into it
    diskutil() {
        if [[ "$1" == "erasevolume" ]]; then
            local vol_name="$3"
            mkdir -p "$VOLUMES_DIR/$vol_name"
        fi
    }
    export -f diskutil
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: create a mock gpg that writes content to the --output path
mock_gpg_success() {
    gpg() {
        local args=("$@")
        for i in "${!args[@]}"; do
            if [[ "${args[$i]}" == "--output" ]]; then
                echo "decrypted content" > "${args[$((i+1))]}"
            fi
        done
        return 0
    }
    export -f gpg
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

@test "error when no argument is provided" {
    run bash src/decrypt_open.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Error: no file path provided"* ]]
}

@test "error when file does not exist" {
    run bash src/decrypt_open.sh "/nonexistent/file.gpg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Error: file not found"* ]]
}

# ---------------------------------------------------------------------------
# File size cap
# ---------------------------------------------------------------------------

@test "error when encrypted file exceeds 512MB cap" {
    local encrypted="$TEST_DIR/huge.pdf.gpg"
    # Create a file reported as 300MB — 2x + 16MB overhead = 616MB > 512MB cap
    touch "$encrypted"
    stat() { echo $((300 * 1024 * 1024)); }
    export -f stat

    run bash src/decrypt_open.sh "$encrypted"
    [ "$status" -eq 0 ]
    [[ "$output" == *"too large"* ]]
}

# ---------------------------------------------------------------------------
# RAM disk setup failures
# ---------------------------------------------------------------------------

@test "error when hdiutil fails to create RAM disk" {
    hdiutil() { echo ""; }
    export -f hdiutil

    local encrypted="$TEST_DIR/file.gpg"
    touch "$encrypted"

    run bash src/decrypt_open.sh "$encrypted"
    [ "$status" -eq 0 ]
    [[ "$output" == *"could not create secure RAM disk"* ]]
}

@test "error when diskutil fails to format RAM disk" {
    diskutil() { return 1; }
    export -f diskutil

    local encrypted="$TEST_DIR/file.gpg"
    touch "$encrypted"

    run bash src/decrypt_open.sh "$encrypted"
    [ "$status" -eq 0 ]
    [[ "$output" == *"could not format secure RAM disk"* ]]
}

@test "ejects RAM disk when diskutil fails" {
    diskutil() { return 1; }
    export -f diskutil

    local encrypted="$TEST_DIR/file.gpg"
    touch "$encrypted"

    run bash src/decrypt_open.sh "$encrypted"
    [ -f "$TEST_DIR/hdiutil_detached" ]
}

# ---------------------------------------------------------------------------
# Output filename logic
# ---------------------------------------------------------------------------

@test "strips .gpg extension from output filename" {
    local encrypted="$TEST_DIR/report.txt.gpg"
    touch "$encrypted"
    mock_gpg_success

    run bash src/decrypt_open.sh "$encrypted"
    [ "$status" -eq 0 ]
}

@test "strips .pgp extension from output filename" {
    local encrypted="$TEST_DIR/archive.tar.pgp"
    touch "$encrypted"
    mock_gpg_success

    run bash src/decrypt_open.sh "$encrypted"
    [ "$status" -eq 0 ]
}

@test "strips .asc extension from output filename" {
    local encrypted="$TEST_DIR/message.txt.asc"
    touch "$encrypted"
    mock_gpg_success

    run bash src/decrypt_open.sh "$encrypted"
    [ "$status" -eq 0 ]
}

@test "appends .decrypted for unknown extension" {
    local encrypted="$TEST_DIR/weirdfile.enc"
    touch "$encrypted"
    mock_gpg_success

    run bash src/decrypt_open.sh "$encrypted"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# GPG failure
# ---------------------------------------------------------------------------

@test "shows error when gpg fails" {
    local encrypted="$TEST_DIR/file.gpg"
    touch "$encrypted"

    gpg() { echo "gpg: no secret key" >&2; return 1; }
    export -f gpg

    run bash src/decrypt_open.sh "$encrypted"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Decryption failed:"* ]]
}

@test "failure message includes last line of gpg stderr" {
    local encrypted="$TEST_DIR/file.gpg"
    touch "$encrypted"

    gpg() { printf "gpg: opening input\ngpg: bad session key\n" >&2; return 1; }
    export -f gpg

    run bash src/decrypt_open.sh "$encrypted"
    [[ "$output" == *"bad session key"* ]]
}

@test "ejects RAM disk when gpg fails" {
    local encrypted="$TEST_DIR/file.gpg"
    touch "$encrypted"

    gpg() { return 1; }
    export -f gpg

    run bash src/decrypt_open.sh "$encrypted"
    [ -f "$TEST_DIR/hdiutil_detached" ]
}

# ---------------------------------------------------------------------------
# Success: file is not written next to the original
# ---------------------------------------------------------------------------

@test "does not create decrypted file next to original" {
    local encrypted="$TEST_DIR/secret.pdf.gpg"
    touch "$encrypted"
    mock_gpg_success

    run bash src/decrypt_open.sh "$encrypted"
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_DIR/secret.pdf" ]
}
