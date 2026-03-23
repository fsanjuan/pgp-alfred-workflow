#!/usr/bin/osascript -l JavaScript
// list_keys.js - Script Filter for Alfred: lists GPG public keys for recipient selection.
//
// Flow:
// - First call (from File Action): argv[0] is the file path, $filepath env var is unset.
// - Subsequent calls (user typing): argv[0] is the search term, $filepath env var is set.
//
// Alfred variables mechanism: the JSON response includes {"variables": {"filepath": "..."}}
// which Alfred passes back as an env var on subsequent Script Filter invocations.

ObjC.import('Foundation');

function run(argv) {
    const app = Application.currentApplication();
    app.includeStandardAdditions = true;

    const arg = (argv && argv.length > 0) ? String(argv[0]) : '';

    // Determine filepath and search term.
    // If $filepath env var is set, Alfred has already passed it from the previous response —
    // this is a re-run triggered by the user typing, so arg is the search term.
    // Otherwise this is the first call from the File Action, so arg is the file path.
    const env = $.NSProcessInfo.processInfo.environment;
    let filepath = ObjC.unwrap(env.objectForKey('filepath')) || '';
    let searchTerm = '';

    if (!filepath) {
        if (arg && $.NSFileManager.defaultManager.fileExistsAtPath(arg)) {
            filepath = arg;
        } else {
            searchTerm = arg;
        }
    } else {
        searchTerm = arg;
    }

    // Run gpg, prepending common install locations to PATH.
    // doShellScript throws if the command exits non-zero or is not found.
    let rawOutput = '';
    try {
        rawOutput = app.doShellScript(
            'export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"; ' +
            '${ALFRED_PGP_GPG:-gpg} --list-keys --with-colons 2>/dev/null'
        );
    } catch (e) {
        return JSON.stringify({
            variables: { filepath: filepath },
            items: [{
                title: 'GPG not found',
                subtitle: 'Install via GPG Suite (gpgtools.org) or: brew install gnupg',
                valid: false,
            }],
        });
    }

    // doShellScript returns lines separated by \r, not \n — split accordingly.
    const keys = parseKeys(rawOutput.split('\r'));

    // Filter by search term and build Alfred items, deduplicating by fingerprint.
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
            title: title,
            subtitle: subtitle,
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

    return JSON.stringify({ variables: { filepath: filepath }, items: items });
}

// NOTE: parseKeys() and buildItems() are duplicated in src/keys.js (a plain Node
// module) so they can be unit-tested with Jest. Keep the two copies in sync.
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
                name: name,
                email: email,
            });
        }
    }

    return keys;
}
