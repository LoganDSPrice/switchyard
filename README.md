# Switchyard

> Modern environment and database parity CLI for Rails applications on Railway.

`switchyard` gives Rails developers back the effortless environment parity workflow popularized by `thoughtbot/parity`, redesigned from the ground up for **Railway** and modern cloud platforms.

---

## Features

- 🚂 **Native Railway Integration:** Scoped to Railway's project/service/environment model (`staging`, `production`, `pr-<number>`) rather than obsolete Heroku git remotes.
- ⚡ **Direct Streaming Database Restore:** Pipes `pg_dump` directly into `pg_restore` over Unix pipes with zero unencrypted `.dump` files touching your local disk.
- 🧹 **Automatic Rails Metadata Hygiene:** Resets `ar_internal_metadata` post-restore so local Rails commands don't lock or think your machine is on production.
- 🛡️ **Safety Guardrails:** Protected production environments with confirmation gates and safe, non-interpolated process execution.
- 🚀 **Zero-Friction Setup:** Built-in `switchyard install` generator to wire up binstubs in any Rails repo in seconds.

---

## Installation

### Should you install it in your `Gemfile` or globally?

| Approach | Best For | How to use |
| :--- | :--- | :--- |
| **In `Gemfile` (Recommended)** | Teams, repeatable CI/CD, project version locking | Add to `group :development`, run `bundle exec switchyard install` |
| **Globally as a CLI** | Solo developers, quick experiments across multiple repos | `gem install switchyard`, then run `switchyard` anywhere |

### Option A: In your Rails project's `Gemfile` (Recommended)

Add `switchyard` to your development group:

```ruby
# Gemfile
group :development do
  gem "switchyard", github: "LoganDSPrice/switchyard"
  # Or during local development:
  # gem "switchyard", path: "/Users/loganprice/code/gemini/switchyard"
end
```

Install the bundle and generate your project binstubs:

```bash
bundle install
bundle exec switchyard install
```

> **Tip:** If you use `asdf` and want to run commands without typing `bin/` (e.g. `staging console` instead of `bin/staging console`), pass the optional `--git-safe` flag:
> ```bash
> bundle exec switchyard install --git-safe
> ```
> This creates a local `.git/safe` directory, allowing local binstubs to **supersede** any conflicting global `asdf` shims (requires `.git/safe/../../bin` in your `$PATH`).

> **Automated PR Cleanup:** To generate a GitHub Action workflow that automatically decommissions review app environments on Railway when a PR is closed or merged:
> ```bash
> bundle exec switchyard install --github-action
> ```
> This creates `.github/workflows/switchyard-cleanup-pr.yml`.
> 
> *To enable:*
> 1. In Railway: Go to **Project Settings** → **Tokens** → **New Token**:
>    - Name suggestion: `GitHub Actions - PR Cleanup`
>    - Scope: Project Token
> 2. In GitHub: Go to your repo's **Settings** → **Secrets and variables** → **Actions** → **New repository secret**:
>    - Name: `RAILWAY_TOKEN`
>    - Secret: Paste the copied token value.

This creates executable binstubs in your Rails app's `bin/`:
- `bin/switchyard`
- `bin/dev`
- `bin/staging`
- `bin/production`
- `bin/pr`
- `.switchyard.yml`

### Option B: As a Global CLI Tool

Install system-wide:

```bash
gem install switchyard
```

Once installed globally, you can `cd` into any Rails repo and run:

```bash
switchyard install
```

---

## Usage

You can use either the unified `switchyard` command or the generated binstubs:

### Rails Console
```bash
# Via binstub:
staging console
production console

# Or via unified CLI:
switchyard console staging
switchyard console production
```

### Tail / Stream Remote Logs
```bash
# Via binstub:
staging logs
production logs

# Or via unified CLI:
switchyard logs staging
```

### Remote Migrations
```bash
staging migrate
production migrate
```

### Streaming Database Parity
Sync your local development database with remote data in seconds:

```bash
# Pull staging database into local development:
dev restore staging

# Pull production database into local development (prompts for safety):
dev restore production

# Push staging database into PR review app:
pr 142 restore staging
```

#### What happens during a restore:
1. Railway credentials (`DATABASE_URL`) are securely resolved via `railway variables --json`.
2. Target database name is extracted from your `config/database.yml` (supporting ERB and Rails 6+ multi-database setups).
3. Local database is dropped and recreated.
4. `pg_dump -Fc` streams directly into `pg_restore --dbname=... --verbose`.
5. `ar_internal_metadata` is updated to set `environment = 'development'`.

### PR / Review App Preview Environments
Deploy and interact with dynamic preview environments on Railway directly from GitHub pull requests:

```bash
# Deploy a review app on Railway directly from GitHub branch:
pr 142 deploy

# Auto-detect the current branch's PR and deploy:
pr deploy

# Deploy and immediately seed database from staging:
pr 142 deploy --seed

# Open rails console on PR #142:
pr 142 console

# View real-time logs for PR #142:
pr 142 logs

# Run migrations on PR #142:
pr 142 migrate

# Seed or refresh PR #142 database from staging:
pr 142 restore staging
```

---

## Configuration (`.switchyard.yml`)

Running `switchyard install` generates a `.switchyard.yml` file in your project root:

```yaml
adapter: railway
environments:
  development:
    database_role: primary
  staging:
    name: staging
  production:
    name: production
```

---

## Prerequisites

1. **Railway CLI**: Logged in and linked to your project:
   ```bash
   railway login
   cd /path/to/project && railway link
   ```
2. **PostgreSQL Client Tools**: `pg_dump` and `pg_restore` (e.g., `brew install libpq` or `brew install postgresql`).

---

## Troubleshooting & asdf Shim Conflicts

### Error: `No version is set for command production` (or `staging` / `dev`)

If you use **asdf** (or **rtx** / **mise**) as your version manager and type `production console` without the `bin/` prefix, you may encounter:

```text
No version is set for command production
Consider adding one of the following versions in your config file at /path/.tool-versions:
ruby 3.3.0
...
```

#### Why does this happen?
`asdf` intercepts all command invocations through global shims in `~/.asdf/shims/`. Whenever any gem executable (such as `parity` or `switchyard`) is installed into *any* Ruby version on your machine, `asdf` writes a persistent shim named `production`, `staging`, `dev`, etc. When you type `production`, `asdf` inspects your current directory's `.tool-versions`. If the currently active Ruby version doesn't have that gem installed globally, `asdf` halts execution.

#### Resolution Options:

##### Approach 1: Always use the project binstub (Standard & Recommended)
Prefix the command with `bin/`:
```bash
bin/staging console
bin/dev restore staging
bin/production console
```
Because `switchyard install` places standalone binstubs in your repository's `bin/` folder, calling `bin/...` executes with your project's bundled Ruby and dependencies directly, bypassing `asdf` shims entirely.

##### Approach 2: Enable Thoughtbot's `.git/safe` (Best for omitting `bin/`)
If you want to type bare commands (`staging console`, `dev restore staging`) without prefixing `bin/`, you can configure your shell to automatically prioritize trusted local `bin/` directories over `asdf` shims.

1. Ensure `.git/safe/../../bin` is in your shell's `$PATH` (typically in `~/.zshrc` or `~/.bashrc`):
   ```bash
   export PATH=".git/safe/../../bin:$PATH"
   ```
2. Enable it in your repository via the installer:
   ```bash
   bundle exec switchyard install --git-safe
   ```
   *(Or manually create the trust marker: `mkdir -p .git/safe`)*.

Because `.git/safe/../../bin` precedes `~/.asdf/shims` in your `$PATH`, your shell finds and executes `./bin/production` directly. **This supersedes any conflicting global `asdf` shims** from older Ruby versions.

##### Approach 3: Global Install & Reshim
If you prefer global CLI access across projects:
```bash
gem install switchyard
asdf reshim ruby
```
*(Note: If you switch between different Ruby versions in `.tool-versions`, you must run this inside each Ruby version where you want global shims available).*

---

## License

MIT License.
