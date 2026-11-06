# Switchyard

Modern environment and database parity CLI for Rails applications on Railway.

## Overview

Switchyard provides environment parity commands (`console`, `logs`, `migrate`, `restore`) for Rails applications deployed to modern platforms like Railway, with native support for streaming database synchronization and review app / PR preview environments.

## Features

- **Native Railway Integration:** Seamless execution across `development`, `staging`, `production`, and `pr` preview environments.
- **Streaming Database Sync:** High-performance database restore directly piping `pg_dump` into `pg_restore` with zero temporary dump files on disk.
- **Rails Metadata Hygiene:** Automatically resets `ar_internal_metadata` after a restore.
- **Safety First:** Protected production environments with confirmation gates and safe process execution.

## License

MIT License.
