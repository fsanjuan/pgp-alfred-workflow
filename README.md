# PGP Encrypt/Decrypt — Alfred Workflow

An Alfred workflow to encrypt and decrypt files using PGP/GPG, directly from Alfred's Universal Actions (file browser or Finder selection).

---

## Requirements

- **macOS** with [Alfred](https://www.alfredapp.com/) 4 or 5 and a **Powerpack** licence (required for File/Universal Actions and workflows)
- **GPG** installed — choose one:
  - [GPG Suite](https://gpgtools.org) *(recommended)*: installs `gpg`, a keychain-integrated passphrase manager, and a macOS-native pinentry dialog
  - Homebrew: `brew install gnupg`
- **osascript** — ships with macOS, no installation needed (`/usr/bin/osascript`)

---

## Installation

### 1. Build the workflow file

From the project directory, run:

```bash
bash build.sh
```

This creates `PGP Encrypt Decrypt.alfredworkflow` in the same folder.

### 2. Install into Alfred

Double-click `PGP Encrypt Decrypt.alfredworkflow` in Finder, or run:

```bash
open "PGP Encrypt Decrypt.alfredworkflow"
```

Alfred will prompt you to import the workflow. Click **Import**.

---

## Setup

### Import recipient public keys (for encryption)

Before encrypting a file for someone, you need their public key in your GPG keyring.

**From a `.asc` or `.gpg` key file:**

```bash
gpg --import recipient_key.asc
```

**From a public keyserver:**

```bash
gpg --keyserver keys.openpgp.org --search-keys "name or email"
```

**Verify your keyring:**

```bash
gpg --list-keys
```

### Set up your own key pair (for decryption)

To decrypt files sent to you, you need a private key. If you don't have one yet:

```bash
gpg --full-generate-key
```

Follow the prompts. Choose RSA 4096-bit or Ed25519 for best security.

---

## Usage

### Encrypting a file

1. Open Alfred and navigate to the file, **or** use Alfred's Universal Action on a file selected in Finder (`⌘ Space` then type the filename, or trigger Alfred's file action via your configured hotkey).
2. Press `→` (or `Tab`) to open Universal Actions.
3. Select **Encrypt with PGP**.
4. A list of your GPG public keys appears. Type to filter by name or email.
5. Select the recipient and press `↵`.

The encrypted file is saved next to the original with a `.gpg` extension (e.g. `document.pdf` → `document.pdf.gpg`). A notification confirms success or reports an error.

### Decrypting a file

1. Navigate to the encrypted file (`.gpg`, `.pgp`, or `.asc`) in Alfred.
2. Press `→` (or `Tab`) to open Universal Actions.
3. Select **Decrypt with PGP**.

GPG will ask for your passphrase via the pinentry dialog (handled automatically by gpg-agent — you won't see a terminal prompt). The decrypted file is saved next to the encrypted one with the encrypted extension stripped (e.g. `document.pdf.gpg` → `document.pdf`). If a file with that name already exists, a numeric suffix is added (e.g. `document.pdf.1`).

---

## How it works

### Encrypt flow

```
File Action "Encrypt with PGP"
    ↓  passes file path
Script Filter (list_keys.py)
    ↓  queries gpg --list-keys, user picks a recipient
    ↓  file path is preserved via Alfred workflow variables
Run Script (encrypt.sh)
    ↓  runs: gpg --encrypt --recipient <fingerprint> <file>
Post Notification
    "Encrypted: document.pdf.gpg"
```

### Decrypt flow

```
File Action "Decrypt with PGP"
    ↓  passes file path
Run Script (decrypt.sh)
    ↓  runs: gpg --decrypt --output <file> <file.gpg>
    ↓  gpg-agent handles passphrase via pinentry
Post Notification
    "Decrypted: document.pdf"
```

### Key picker (Script Filter)

`list_keys.py` parses `gpg --list-keys --with-colons` and builds an Alfred result list. Revoked, expired, and disabled keys are automatically excluded. The list is filterable by name or email as you type.

The file path is threaded through the encrypt flow using Alfred's [workflow variables](https://www.alfredapp.com/help/workflows/advanced/variables/) mechanism: `list_keys.py` embeds the path in its JSON response, and Alfred makes it available as a `$filepath` environment variable to subsequent scripts.

---

## File reference

| File | Purpose |
|------|---------|
| `info.plist` | Alfred workflow definition (nodes, connections, layout) |
| `list_keys.js` | Script Filter: reads GPG keyring, outputs Alfred JSON (JXA) |
| `encrypt.sh` | Runs `gpg --encrypt` for the selected recipient |
| `decrypt.sh` | Runs `gpg --decrypt` and handles output file naming |
| `build.sh` | Packages the workflow into a `.alfredworkflow` file |

---

## Troubleshooting

**"GPG not found" in the key picker**

GPG is not installed or not in a standard location. Install [GPG Suite](https://gpgtools.org) or run `brew install gnupg`. The scripts search `/usr/local/bin`, `/opt/homebrew/bin`, and `/usr/bin`.

**"No public keys in keyring"**

You have no imported public keys. Import a recipient's key first — see [Setup](#setup) above.

**"Encryption failed: No public key"**

The selected key fingerprint could not be found during encryption. This can happen if the key was deleted after the key list was loaded. Retry the action.

**"Decryption failed: No secret key"**

You don't have the private key corresponding to the encrypted file's recipient. Decryption is only possible with your own private key.

**Passphrase dialog doesn't appear**

This usually means `gpg-agent` is not running or pinentry is misconfigured. GPG Suite handles this automatically. If using Homebrew GPG, try:

```bash
gpgconf --launch gpg-agent
```

And ensure `~/.gnupg/gpg-agent.conf` contains:

```
pinentry-program /usr/local/bin/pinentry-mac
```

(Install `pinentry-mac` with `brew install pinentry-mac`.)

**Alfred doesn't show the file actions**

Make sure you have an Alfred Powerpack licence. Universal Actions require Alfred 4+ with Powerpack.

---

## Notes

- Encrypted output is **binary GPG format** (`.gpg`), not ASCII-armored. If you need ASCII-armored output (`.asc`), add `--armor` to the `gpg` command in `encrypt.sh`.
- Encryption is **asymmetric** (public-key): the file is encrypted to the recipient's public key. Only the holder of the corresponding private key can decrypt it.
- Signing is not included by default. To also sign encrypted files, add `--sign` (uses your default key) to the `gpg` command in `encrypt.sh`.
- The original file is **not deleted** after encryption. Delete it yourself if needed, and consider using a secure deletion tool.
