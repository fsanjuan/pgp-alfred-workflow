#!/usr/bin/env bats
# Tests for src/decrypt.sh
#
# gpg is mocked via exported bash functions — functions take precedence over
# PATH binaries, so the scripts never need a real GPG installation.

setup() {
    TEST_DIR="$(mktemp -d)"
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
# Collision avoidance
# ---------------------------------------------------------------------------

@test "appends .1 counter when output file already exists" {
    local encrypted="$TEST_DIR/report.txt.gpg"
    touch "$encrypted"
    touch "$TEST_DIR/report.txt"       # pre-existing output
    mock_gpg_success

    run bash src/decrypt.sh "$encrypted"
    [ "$status" -eq 0 ]
    [[ "$output" == "Decrypted: report.txt.1" ]]
}

@test "increments counter until a free name is found" {
    local encrypted="$TEST_DIR/report.txt.gpg"
    touch "$encrypted"
    touch "$TEST_DIR/report.txt"
    touch "$TEST_DIR/report.txt.1"
    touch "$TEST_DIR/report.txt.2"
    mock_gpg_success

    run bash src/decrypt.sh "$encrypted"
    [ "$status" -eq 0 ]
    [[ "$output" == "Decrypted: report.txt.3" ]]
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
    [[ "$output" == "Decryption failed:"* ]]
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
