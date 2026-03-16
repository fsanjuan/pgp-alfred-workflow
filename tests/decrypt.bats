#!/usr/bin/env bats
# Tests for src/decrypt.sh
#
# gpg and osascript are mocked via exported bash functions.

setup() {
    TEST_DIR="$(mktemp -d)"

    # Mock osascript: echo the message argument and drain the heredoc from stdin
    osascript() {
        if [[ "$1" == "-" ]]; then
            local msg="$2"
            cat > /dev/null
            echo "$msg"
        fi
    }
    export -f osascript
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
    run bash src/decrypt.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Error: no file path provided"* ]]
}

@test "error when file does not exist" {
    run bash src/decrypt.sh "/nonexistent/file.gpg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Error: file not found"* ]]
}

# ---------------------------------------------------------------------------
# Output filename logic
# ---------------------------------------------------------------------------

@test "strips .gpg extension from output filename" {
    local encrypted="$TEST_DIR/report.txt.gpg"
    touch "$encrypted"
    mock_gpg_success

    run bash src/decrypt.sh "$encrypted"
    [ "$status" -eq 0 ]
    [[ "$output" == "Decrypted: report.txt" ]]
}

@test "strips .pgp extension from output filename" {
    local encrypted="$TEST_DIR/archive.tar.pgp"
    touch "$encrypted"
    mock_gpg_success

    run bash src/decrypt.sh "$encrypted"
    [ "$status" -eq 0 ]
    [[ "$output" == "Decrypted: archive.tar" ]]
}

@test "strips .asc extension from output filename" {
    local encrypted="$TEST_DIR/message.txt.asc"
    touch "$encrypted"
    mock_gpg_success

    run bash src/decrypt.sh "$encrypted"
    [ "$status" -eq 0 ]
    [[ "$output" == "Decrypted: message.txt" ]]
}

@test "appends .decrypted for unknown extension" {
    local encrypted="$TEST_DIR/weirdfile.enc"
    touch "$encrypted"
    mock_gpg_success

    run bash src/decrypt.sh "$encrypted"
    [ "$status" -eq 0 ]
    [[ "$output" == "Decrypted: weirdfile.enc.decrypted" ]]
}

# ---------------------------------------------------------------------------
# Overwrite prompt
# ---------------------------------------------------------------------------

@test "decrypts and overwrites when user confirms" {
    local encrypted="$TEST_DIR/report.txt.gpg"
    touch "$encrypted"
    echo "old content" > "$TEST_DIR/report.txt"

    # Distinguish confirm dialog from notify: notify messages start with "Decrypted:"
    osascript() {
        if [[ "$1" == "-" ]]; then
            local msg="$2"; cat > /dev/null
            [[ "$msg" == Decrypted:* ]] && echo "$msg" || echo "Overwrite"
        fi
    }
    export -f osascript
    mock_gpg_success

    run bash src/decrypt.sh "$encrypted"
    [ "$status" -eq 0 ]
    [[ "$output" == "Decrypted: report.txt" ]]
}

@test "exits without decrypting when user cancels overwrite" {
    local encrypted="$TEST_DIR/report.txt.gpg"
    touch "$encrypted"
    echo "old content" > "$TEST_DIR/report.txt"

    # Simulate user clicking Cancel
    osascript() { cat > /dev/null; echo "Cancel"; }
    export -f osascript

    run bash src/decrypt.sh "$encrypted"
    [ "$status" -eq 0 ]
    # Original file unchanged, no new file created
    [[ "$(cat "$TEST_DIR/report.txt")" == "old content" ]]
}

# ---------------------------------------------------------------------------
# GPG failure
# ---------------------------------------------------------------------------

@test "prints Decryption failed message when gpg exits non-zero" {
    local encrypted="$TEST_DIR/file.gpg"
    touch "$encrypted"

    gpg() {
        echo "gpg: no secret key" >&2
        return 1
    }
    export -f gpg

    run bash src/decrypt.sh "$encrypted"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Decryption failed:"* ]]
}

@test "failure message includes last line of gpg stderr" {
    local encrypted="$TEST_DIR/file.gpg"
    touch "$encrypted"

    gpg() {
        printf "gpg: opening input\ngpg: bad session key\n" >&2
        return 1
    }
    export -f gpg

    run bash src/decrypt.sh "$encrypted"
    [[ "$output" == *"bad session key"* ]]
}
