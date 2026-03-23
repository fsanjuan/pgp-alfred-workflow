#!/usr/bin/env bats
# Tests for src/list_keys.js
#
# Runs the real list_keys.js via osascript with a mock gpg binary.
# ALFRED_PGP_GPG overrides the gpg binary used by the script.

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR

    # A real file path is needed so list_keys.js detects it as a filepath on first call
    ENCRYPTED_FILE="$TEST_DIR/document.pdf.gpg"
    touch "$ENCRYPTED_FILE"
    export ENCRYPTED_FILE
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: write a mock gpg script that outputs given colon-format lines
mock_gpg() {
    local mock="$TEST_DIR/mock-gpg"
    cat > "$mock" <<SCRIPT
#!/bin/bash
cat <<'EOF'
$1
EOF
SCRIPT
    chmod +x "$mock"
    export ALFRED_PGP_GPG="$mock"
}

# Helper: mock gpg that exits non-zero (simulates gpg not found / broken)
mock_gpg_fail() {
    local mock="$TEST_DIR/mock-gpg"
    printf '#!/bin/bash\nexit 1\n' > "$mock"
    chmod +x "$mock"
    export ALFRED_PGP_GPG="$mock"
}

# Standard two-key keyring used across multiple tests
TWO_KEYS="pub:u:4096:1:AAAA1111AAAA1111:1609459200::u:::scESC:
fpr:::::::::AAAA1111AAAA1111AAAA1111AAAA1111AAAA1111:
uid:u::::1609459200::H1::Alice Example <alice@example.com>:::::::::0:
pub:u:4096:1:BBBB2222BBBB2222:1609459200::u:::scESC:
fpr:::::::::BBBB2222BBBB2222BBBB2222BBBB2222BBBB2222:
uid:u::::1609459200::H2::Bob Builder <bob@example.com>:::::::::0:"

# ---------------------------------------------------------------------------
# Basic output
# ---------------------------------------------------------------------------

@test "returns Alfred JSON containing all keys" {
    mock_gpg "$TWO_KEYS"
    run osascript -l JavaScript src/list_keys.js "$ENCRYPTED_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Alice Example"* ]]
    [[ "$output" == *"Bob Builder"* ]]
}

@test "includes fingerprint as arg and uid" {
    mock_gpg "$TWO_KEYS"
    run osascript -l JavaScript src/list_keys.js "$ENCRYPTED_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AAAA1111AAAA1111AAAA1111AAAA1111AAAA1111"* ]]
}

@test "stores filepath in variables" {
    mock_gpg "$TWO_KEYS"
    run osascript -l JavaScript src/list_keys.js "$ENCRYPTED_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"filepath"'* ]]
    [[ "$output" == *"document.pdf.gpg"* ]]
}

@test "shows prompt item when filepath is set and no search term" {
    mock_gpg "$TWO_KEYS"
    run osascript -l JavaScript src/list_keys.js "$ENCRYPTED_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Select a key to encrypt with"* ]]
}

@test "prompt shows filename" {
    mock_gpg "$TWO_KEYS"
    run osascript -l JavaScript src/list_keys.js "$ENCRYPTED_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"document.pdf.gpg"* ]]
}

# ---------------------------------------------------------------------------
# Filtering
# ---------------------------------------------------------------------------

@test "filters by name when search term matches" {
    mock_gpg "$TWO_KEYS"
    export filepath="$ENCRYPTED_FILE"
    run osascript -l JavaScript src/list_keys.js "alice"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Alice Example"* ]]
    [[ "$output" != *"Bob Builder"* ]]
}

@test "filters by email when search term matches" {
    mock_gpg "$TWO_KEYS"
    export filepath="$ENCRYPTED_FILE"
    run osascript -l JavaScript src/list_keys.js "bob@example"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Bob Builder"* ]]
    [[ "$output" != *"Alice Example"* ]]
}

@test "search is case insensitive" {
    mock_gpg "$TWO_KEYS"
    export filepath="$ENCRYPTED_FILE"
    run osascript -l JavaScript src/list_keys.js "ALICE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Alice Example"* ]]
}

# ---------------------------------------------------------------------------
# Key validity filtering
# ---------------------------------------------------------------------------

@test "skips revoked keys" {
    mock_gpg "pub:u:4096:1:AAAA1111AAAA1111:1609459200::u:::scESC:
fpr:::::::::AAAA1111AAAA1111AAAA1111AAAA1111AAAA1111:
uid:u::::1609459200::H1::Alice Example <alice@example.com>:::::::::0:
pub:r:4096:1:CCCC3333CCCC3333:1609459200::r:::scESC:
fpr:::::::::CCCC3333CCCC3333CCCC3333CCCC3333CCCC3333:
uid:r::::1609459200::H3::Revoked User <revoked@example.com>:::::::::0:"
    run osascript -l JavaScript src/list_keys.js "$ENCRYPTED_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Revoked User"* ]]
    [[ "$output" == *"Alice Example"* ]]
}

@test "skips expired keys" {
    mock_gpg "pub:u:4096:1:AAAA1111AAAA1111:1609459200::u:::scESC:
fpr:::::::::AAAA1111AAAA1111AAAA1111AAAA1111AAAA1111:
uid:u::::1609459200::H1::Alice Example <alice@example.com>:::::::::0:
pub:e:4096:1:DDDD4444DDDD4444:1609459200::e:::scESC:
fpr:::::::::DDDD4444DDDD4444DDDD4444DDDD4444DDDD4444:
uid:e::::1609459200::H4::Expired User <expired@example.com>:::::::::0:"
    run osascript -l JavaScript src/list_keys.js "$ENCRYPTED_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Expired User"* ]]
    [[ "$output" == *"Alice Example"* ]]
}

@test "deduplicates keys with same fingerprint" {
    mock_gpg "pub:u:4096:1:AAAA1111AAAA1111:1609459200::u:::scESC:
fpr:::::::::AAAA1111AAAA1111AAAA1111AAAA1111AAAA1111:
uid:u::::1609459200::H1::Alice Example <alice@example.com>:::::::::0:
uid:u::::1609459200::H1B::Alice Alt <alice.alt@example.com>:::::::::0:"
    run osascript -l JavaScript src/list_keys.js "$ENCRYPTED_FILE"
    [ "$status" -eq 0 ]
    # Count occurrences of the fingerprint as an arg value — should be exactly one item
    count=$(echo "$output" | grep -o '"arg":"AAAA1111AAAA1111AAAA1111AAAA1111AAAA1111"' | wc -l | tr -d ' ')
    [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Empty / error states
# ---------------------------------------------------------------------------

@test "returns no public keys item when keyring is empty" {
    mock_gpg ""
    run osascript -l JavaScript src/list_keys.js "$ENCRYPTED_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No public keys in keyring"* ]]
}

@test "returns no matching keys item when search has no results" {
    mock_gpg "$TWO_KEYS"
    export filepath="$ENCRYPTED_FILE"
    run osascript -l JavaScript src/list_keys.js "zzznomatch"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No keys matching"* ]]
}

@test "returns GPG not found item when gpg command fails" {
    mock_gpg_fail
    run osascript -l JavaScript src/list_keys.js "$ENCRYPTED_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GPG not found"* ]]
}
