# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-11-18

### Added
- Auto-populate `RAILWAY_PROJECT_ID` directly into `.github/workflows/switchyard-cleanup-pr.yml` when locally linked via `railway link`, and interactively offer to run `railway link` during `switchyard install --github-action` when unlinked.
- Preserve existing non-Switchyard `bin/dev` launchers during `switchyard install` and print a notice pointing to `bin/switchyard restore <env>`.

### Fixed
- Scope PR preview branch and `PORT` updates strictly to the target PR environment using `railway environment new <env> --duplicate <base> --service-config ... --json` and `railway environment edit --environment <env> --service-config ... --json` (executed via `PTY.spawn`), replacing `railway service source connect` (which mutated `source.branch` globally across all Railway environments).
- Verify post-deploy environment configuration via `railway environment config --environment <env> --json` and retry if async environment duplication has not settled yet.
- Restore the developer's previously linked local Railway environment (`isLinked: true` in `railway environment list --json`) in an `ensure` block after creating a new PR environment.
- Resolve the target app service from the resolved duplicate base environment (`staging` -> `production` fallback) and auto-detect the app service in `console`, `logs`, `migrate`, and `seed` when `service:` is omitted from `.switchyard.yml`.
- Update `.github/workflows/switchyard-cleanup-pr.yml` and installer setup instructions to use a Railway Account Token (`RAILWAY_API_TOKEN` with **"No workspace"** selected), non-interactive `railway link`, and an existence check (`railway environment list --json` + `jq -e`) before deleting `pr-<number>`.
- Pass `-X` to `psql` in `Switchyard::Database::MetadataFixer` so local `~/.psqlrc` / `~/.psqlrc.local` files do not emit encoding errors during database restores.

## [0.1.0] - 2026-11-09

### Added
- Initial release of Switchyard with environment and database parity commands (`console`, `logs`, `migrate`, `restore`, `pr`, and `install`) for Rails applications on Railway.
