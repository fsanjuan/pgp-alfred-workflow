# Add "Decrypt and Open" Universal Action

## Summary

Currently the workflow only supports decrypting a file and saving the output next to the original ("Decrypt with PGP"). This works well for files you want to keep, but is inconvenient when you just want to read a sensitive document — especially from cloud storage (e.g. OX Drive) where leaving a plaintext copy on disk is undesirable.

## Changes proposed

1. **Rename** the existing "Decrypt with PGP" Universal Action to **"Decrypt and Save"** — making its behaviour explicit.

2. **Add** a new **"Decrypt and Open"** Universal Action that:
   - Decrypts the file to a secure temp directory (`$TMPDIR`)
   - Opens the decrypted file with the default macOS app (e.g. Preview for PDFs)
   - Deletes the temp file immediately after opening — the app loads the file into memory so the plaintext never persists on disk
   - Supports the same file extensions as "Decrypt and Save": `.gpg`, `.pgp`, `.asc`

## Why delete immediately after `open`?

macOS apps like Preview load the entire file into memory on open, so the file on disk is no longer needed. Deleting it right after calling `open` ensures no plaintext copy is left behind, even if the user forgets or Alfred crashes.
