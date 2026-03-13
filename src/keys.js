// keys.js - Pure GPG key parsing and filtering logic.
//
// Exported as a Node.js module so tests can import it directly.
// list_keys.js (JXA/osascript) keeps its own copy of these functions
// because osascript cannot require() Node modules.

'use strict';

/**
 * Parse GPG colon-format output (from `gpg --list-keys --with-colons`)
 * into an array of key objects.
 *
 * @param {string[]} lines - Lines split from gpg output (\n or \r)
 * @returns {{ keyId: string, fingerprint: string, name: string, email: string }[]}
 */
function parseKeys(lines) {
    const keys = [];
    let currentKeyId = null;
    let currentFingerprint = null;

    for (const line of lines) {
        const parts = line.split(':');
        if (parts.length < 2) continue;

        const record = parts[0];
        const validity = parts[1];

        if (record === 'pub') {
            currentKeyId = parts[4] || null;
            currentFingerprint = null;
        } else if (record === 'fpr') {
            currentFingerprint = parts[9] || currentFingerprint;
        } else if (record === 'uid' && currentKeyId) {
            // Skip revoked (r), expired (e), disabled (d), invalid (n)
            if (['r', 'e', 'd', 'n'].includes(validity)) continue;

            const uidString = parts[9] || '';
            const match = uidString.match(/^(.*?)\s*(?:<([^>]+)>)?$/);
            const name = match ? match[1].trim() : uidString;
            const email = (match && match[2]) ? match[2] : '';

            keys.push({
                keyId: currentKeyId,
                fingerprint: currentFingerprint || currentKeyId,
                name,
                email,
            });
        }
    }

    return keys;
}

/**
 * Filter and deduplicate keys, then build Alfred result items.
 *
 * @param {{ keyId: string, fingerprint: string, name: string, email: string }[]} keys
 * @param {string} searchTerm - User's filter string (case-insensitive)
 * @returns {object[]} Alfred items array
 */
function buildItems(keys, searchTerm) {
    const term = searchTerm.toLowerCase();
    const seen = new Set();
    const items = [];

    for (const key of keys) {
        if (seen.has(key.fingerprint)) continue;
        seen.add(key.fingerprint);

        if (term && !key.name.toLowerCase().includes(term) && !key.email.toLowerCase().includes(term)) {
            continue;
        }

        const title = key.name || key.email || key.keyId;
        const subtitle = key.email || ('Key ID: ' + key.keyId);

        items.push({
            uid: key.fingerprint,
            title,
            subtitle,
            arg: key.fingerprint,
            valid: true,
            autocomplete: title,
        });
    }

    if (items.length === 0) {
        items.push(
            keys.length === 0
                ? { title: 'No public keys in keyring', subtitle: 'Import a key: gpg --import key.asc', valid: false }
                : { title: 'No keys matching "' + searchTerm + '"', subtitle: 'Try a different name or email', valid: false }
        );
    }

    return items;
}

module.exports = { parseKeys, buildItems };
