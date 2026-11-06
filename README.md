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

This creates executable binstubs in your Rails app's `bin/`:
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
Railway generates dynamic environments for pull requests (e.g. `pr-142`). Switchyard handles them seamlessly:

```bash
# Open rails console on PR #142:
pr 142 console

# View logs for PR #142:
pr 142 logs

# Run migrations on PR #142:
pr 142 migrate

# Seed PR #142 database from staging:
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

## License

MIT License.
