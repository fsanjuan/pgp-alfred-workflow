'use strict';

const { parseKeys, buildItems } = require('../src/keys');

// ---------------------------------------------------------------------------
// Helpers to build GPG colon-format lines
// ---------------------------------------------------------------------------

function pub(keyId = 'KEYID0001', validity = 'u') {
    return `pub:${validity}:4096:1:${keyId}:2023-01-01:::u:::scESC:`;
}

function fpr(fingerprint = 'FINGERPRINT0001ABCDEF') {
    return `fpr:::::::::${fingerprint}:`;
}

function uid(uidStr = 'Alice <alice@example.com>', validity = 'u') {
    return `uid:${validity}::::2023-01-01::HASH::${uidStr}:::::::0:`;
}

// A complete block for one key with one UID
function keyBlock({ keyId = 'KEYID0001', fingerprint = 'FPR0001', name = 'Alice', email = 'alice@example.com', uidValidity = 'u' } = {}) {
    return [
        pub(keyId),
        fpr(fingerprint),
        uid(`${name} <${email}>`, uidValidity),
    ];
}

// ---------------------------------------------------------------------------
// parseKeys
// ---------------------------------------------------------------------------

describe('parseKeys', () => {
    test('returns empty array for empty input', () => {
        expect(parseKeys([])).toEqual([]);
    });

    test('returns empty array for unrecognised lines', () => {
        expect(parseKeys(['junk', 'more:junk'])).toEqual([]);
    });

    test('parses a single key with name and email', () => {
        const lines = keyBlock({ keyId: 'ABCD1234', fingerprint: 'FPR_ALICE', name: 'Alice', email: 'alice@example.com' });
        const result = parseKeys(lines);

        expect(result).toHaveLength(1);
        expect(result[0]).toMatchObject({
            keyId: 'ABCD1234',
            fingerprint: 'FPR_ALICE',
            name: 'Alice',
            email: 'alice@example.com',
        });
    });

    test('parses multiple UIDs for the same pub key', () => {
        const lines = [
            pub('KEYID_MULTI'),
            fpr('FPR_MULTI'),
            uid('Alice Primary <alice@primary.com>'),
            uid('Alice Secondary <alice@secondary.com>'),
        ];
        const result = parseKeys(lines);

        expect(result).toHaveLength(2);
        expect(result[0].email).toBe('alice@primary.com');
        expect(result[1].email).toBe('alice@secondary.com');
        // Both UIDs share the same fingerprint
        expect(result[0].fingerprint).toBe('FPR_MULTI');
        expect(result[1].fingerprint).toBe('FPR_MULTI');
    });

    test('skips revoked UIDs (validity r)', () => {
        const lines = [
            pub('KEYID_REV'),
            fpr('FPR_REV'),
            uid('Revoked <rev@example.com>', 'r'),
            uid('Valid <valid@example.com>', 'u'),
        ];
        const result = parseKeys(lines);

        expect(result).toHaveLength(1);
        expect(result[0].email).toBe('valid@example.com');
    });

    test('skips expired UIDs (validity e)', () => {
        const lines = [
            pub('KEYID_EXP'),
            fpr('FPR_EXP'),
            uid('Expired <exp@example.com>', 'e'),
        ];
        expect(parseKeys(lines)).toHaveLength(0);
    });

    test('skips disabled UIDs (validity d)', () => {
        const lines = [pub('K'), fpr('F'), uid('Disabled <d@x.com>', 'd')];
        expect(parseKeys(lines)).toHaveLength(0);
    });

    test('skips invalid UIDs (validity n)', () => {
        const lines = [pub('K'), fpr('F'), uid('Invalid <n@x.com>', 'n')];
        expect(parseKeys(lines)).toHaveLength(0);
    });

    test('handles UID with no email (name only)', () => {
        const lines = [pub('K'), fpr('F'), uid('Just A Name')];
        const result = parseKeys(lines);

        expect(result).toHaveLength(1);
        expect(result[0].name).toBe('Just A Name');
        expect(result[0].email).toBe('');
    });

    test('handles UID with email only (no name before angle bracket)', () => {
        const lines = [pub('K'), fpr('F'), uid('<noname@example.com>')];
        const result = parseKeys(lines);

        expect(result).toHaveLength(1);
        expect(result[0].name).toBe('');
        expect(result[0].email).toBe('noname@example.com');
    });

    test('handles special characters in name', () => {
        const lines = [pub('K'), fpr('F'), uid('Ångström Ö\'Brian <special@example.com>')];
        const result = parseKeys(lines);

        expect(result[0].name).toBe("Ångström Ö'Brian");
        expect(result[0].email).toBe('special@example.com');
    });

    test('uses fingerprint from fpr record, falls back to keyId if fpr missing', () => {
        // No fpr line
        const lines = [pub('KEYID_ONLY'), uid('Bob <bob@example.com>')];
        const result = parseKeys(lines);

        expect(result[0].fingerprint).toBe('KEYID_ONLY');
    });

    test('uses most recent fpr for each pub block', () => {
        const lines = [
            pub('K1'),
            fpr('FPR_FIRST'),
            fpr('FPR_SECOND'),    // second fpr wins
            uid('Alice <alice@example.com>'),
        ];
        // Second fpr overwrites first because fpr record sets currentFingerprint
        const result = parseKeys(lines);
        expect(result[0].fingerprint).toBe('FPR_SECOND');
    });

    test('parses multiple separate pub blocks', () => {
        const lines = [
            ...keyBlock({ keyId: 'K1', fingerprint: 'F1', name: 'Alice', email: 'alice@example.com' }),
            ...keyBlock({ keyId: 'K2', fingerprint: 'F2', name: 'Bob', email: 'bob@example.com' }),
        ];
        const result = parseKeys(lines);

        expect(result).toHaveLength(2);
        expect(result[0].name).toBe('Alice');
        expect(result[1].name).toBe('Bob');
    });

    test('ignores sub-key (sub) records', () => {
        const lines = [
            pub('K'),
            fpr('F'),
            uid('Alice <alice@example.com>'),
            'sub:u:4096:1:SUBKEY:2023-01-01::::e:',
        ];
        const result = parseKeys(lines);
        expect(result).toHaveLength(1);
    });
});

// ---------------------------------------------------------------------------
// buildItems
// ---------------------------------------------------------------------------

describe('buildItems', () => {
    const alice = { keyId: 'K1', fingerprint: 'FPR1', name: 'Alice', email: 'alice@example.com' };
    const bob   = { keyId: 'K2', fingerprint: 'FPR2', name: 'Bob',   email: 'bob@example.com' };

    test('returns all keys when search term is empty', () => {
        const items = buildItems([alice, bob], '');
        expect(items).toHaveLength(2);
    });

    test('filters by name (case-insensitive)', () => {
        const items = buildItems([alice, bob], 'ali');
        expect(items).toHaveLength(1);
        expect(items[0].title).toBe('Alice');
    });

    test('filters by email (case-insensitive)', () => {
        const items = buildItems([alice, bob], 'BOB@EXAMPLE');
        expect(items).toHaveLength(1);
        expect(items[0].title).toBe('Bob');
    });

    test('returns no-match item when search has no results', () => {
        const items = buildItems([alice, bob], 'zzzunknown');
        expect(items).toHaveLength(1);
        expect(items[0].valid).toBe(false);
        expect(items[0].title).toMatch(/No keys matching/);
    });

    test('returns empty-keyring item when key list is empty', () => {
        const items = buildItems([], '');
        expect(items).toHaveLength(1);
        expect(items[0].valid).toBe(false);
        expect(items[0].title).toBe('No public keys in keyring');
    });

    test('deduplicates by fingerprint', () => {
        const dup = { keyId: 'K1', fingerprint: 'FPR1', name: 'Alice Alt', email: 'alt@example.com' };
        const items = buildItems([alice, dup], '');
        // Only the first occurrence of FPR1 is kept
        expect(items).toHaveLength(1);
        expect(items[0].title).toBe('Alice');
    });

    test('item has correct Alfred fields', () => {
        const items = buildItems([alice], '');
        const item = items[0];

        expect(item.uid).toBe('FPR1');
        expect(item.arg).toBe('FPR1');
        expect(item.valid).toBe(true);
        expect(item.autocomplete).toBe('Alice');
        expect(item.subtitle).toBe('alice@example.com');
    });

    test('subtitle falls back to Key ID when email is absent', () => {
        const noEmail = { keyId: 'K3', fingerprint: 'FPR3', name: 'Charlie', email: '' };
        const items = buildItems([noEmail], '');
        expect(items[0].subtitle).toBe('Key ID: K3');
    });

    test('title falls back to email when name is absent', () => {
        const noName = { keyId: 'K4', fingerprint: 'FPR4', name: '', email: 'noname@example.com' };
        const items = buildItems([noName], '');
        expect(items[0].title).toBe('noname@example.com');
    });

    test('title falls back to keyId when both name and email are absent', () => {
        const noInfo = { keyId: 'K5', fingerprint: 'FPR5', name: '', email: '' };
        const items = buildItems([noInfo], '');
        expect(items[0].title).toBe('K5');
    });
});
