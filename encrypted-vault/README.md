# Encrypted VPN Vault (gocryptfs)

This directory contains **ciphertext only** (safe to commit).
On device, it is copied to `/etc/batnet-vpn-encrypted` and mounted
to `/etc/batnet-vpn` by `batnet-vpn-unlock.service`.

Do **not** place any plaintext `.conf`/keys in this repo.
