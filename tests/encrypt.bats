#!/usr/bin/env bats
# Tests for src/encrypt.sh
#
# gpg is mocked via exported bash functions — functions take precedence over
# PATH binaries, so the scripts never need a real GPG installation.

setup() {
    TEST_DIR="$(mktemp -d)"
    TEST_FILE="$TEST_DIR/document.txt"
    echo "secret contents" > "$TEST_FILE"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

@test "error when filepath env var is not set" {
    unset filepath
    run bash src/encrypt.sh "RECIPIENT_FINGERPRINT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Error: file path not provided"* ]]
}

@test "error when filepath is set but file does not exist" {
    export filepath="/nonexistent/file.txt"
    run bash src/encrypt.sh "RECIPIENT_FINGERPRINT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Error: file not found"* ]]
}

@test "error when recipient argument is empty" {
    export filepath="$TEST_FILE"
    run bash src/encrypt.sh ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Error: no recipient key selected"* ]]
}

@test "error when recipient argument is missing entirely" {
    export filepath="$TEST_FILE"
    run bash src/encrypt.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Error: no recipient key selected"* ]]
}

# ---------------------------------------------------------------------------
# Successful encryption
# ---------------------------------------------------------------------------

@test "prints Encrypted message on success" {
    export filepath="$TEST_FILE"

    # Mock gpg: parse --output arg and create the file, then exit 0
    gpg() {
        local args=("$@")
        for i in "${!args[@]}"; do
            if [[ "${args[$i]}" == "--output" ]]; then
                touch "${args[$((i+1))]}"
            fi
        done
        return 0
    }
    export -f gpg

    run bash src/encrypt.sh "RECIPIENT_FINGERPRINT"
    [ "$status" -eq 0 ]
    [[ "$output" == "Encrypted: document.txt.gpg" ]]
}

@test "output file is named <input>.gpg" {
    export filepath="$TEST_FILE"

    gpg() {
        local args=("$@")
        for i in "${!args[@]}"; do
            if [[ "${args[$i]}" == "--output" ]]; then
                touch "${args[$((i+1))]}"
            fi
        done
        return 0
    }
    export -f gpg

    run bash src/encrypt.sh "RECIPIENT_FINGERPRINT"
    [ -f "${TEST_FILE}.gpg" ]
}

@test "gpg receives --recipient and --encrypt flags" {
    export filepath="$TEST_FILE"
    CAPTURED_ARGS_FILE="$TEST_DIR/args.txt"

    gpg() {
        echo "$*" > "$CAPTURED_ARGS_FILE"
        # Create output file so script considers it a success
        local args=("$@")
        for i in "${!args[@]}"; do
            if [[ "${args[$i]}" == "--output" ]]; then
                touch "${args[$((i+1))]}"
            fi
        done
        return 0
    }
    export -f gpg
    export CAPTURED_ARGS_FILE

    run bash src/encrypt.sh "MY_FINGERPRINT"
    [ "$status" -eq 0 ]
    grep -q "\-\-encrypt" "$CAPTURED_ARGS_FILE"
    grep -q "\-\-recipient" "$CAPTURED_ARGS_FILE"
    grep -q "MY_FINGERPRINT" "$CAPTURED_ARGS_FILE"
}

# ---------------------------------------------------------------------------
# GPG failure
# ---------------------------------------------------------------------------

@test "prints Encryption failed message when gpg exits non-zero" {
    export filepath="$TEST_FILE"

    gpg() {
        echo "gpg: RECIPIENT_FINGERPRINT: No public key" >&2
        return 1
    }
    export -f gpg

    run bash src/encrypt.sh "RECIPIENT_FINGERPRINT"
    [ "$status" -eq 0 ]
    [[ "$output" == "Encryption failed:"* ]]
}

@test "failure message includes last line of gpg stderr" {
    export filepath="$TEST_FILE"

    gpg() {
        printf "gpg: line one\ngpg: key not found\n" >&2
        return 1
    }
    export -f gpg

    run bash src/encrypt.sh "RECIPIENT_FINGERPRINT"
    [[ "$output" == *"key not found"* ]]
}
