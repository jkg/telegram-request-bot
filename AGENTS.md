# AGENTS.md

## Project Overview

**telegram-request-bot** is a Perl-based Telegram bot that acts as a lightweight ticketing/helpdesk system. Users send requests to the bot in a private chat; the bot stores them in SQLite, forwards them to a designated admin group chat, and notifies the original sender when an admin marks the request as resolved.

The application supports:

- **Multi-tenant mode**: one process runs multiple bots, each with its own config, database file, and log file.
- **Compatibility mode**: one bot from a single `config.json`, matching the legacy deployment style.

## Technology Stack

| Layer | Technology |
|---|---|
| Language | Perl 5 (strict/warnings throughout) |
| Bot framework | `Telegram::Bot` (≥ 0.023) — provides `Telegram::Bot::Brain` base class and message objects |
| ORM | `DBIx::Class` with `DBIx::Class::Schema::Loader` for schema generation |
| Database | SQLite via `DBD::SQLite` |
| Config | `Config::JSON` (reads per-bot JSON files under `customers/`; legacy single-file `config.json` also supported) |
| Logging | `Log::Dispatch` + `Log::Dispatch::FileRotate` (per-bot logs in `logs/*.log`) |
| Date handling | `DateTime` |
| Error handling | `Try::Tiny` |
| Tests | `Test2::Suite` / `Test2::V0`, `Test::DBIx::Class` (in-memory SQLite) |

## Folder Layout

```
telegram-request-bot/
├── config.json              # Compatibility-mode config for a single legacy bot
├── cpanfile                 # CPAN dependency declaration (use with cpanm or carton)
├── bin/
│   ├── bot.pl               # Entry point — multi-tenant manager + legacy compatibility mode
│   ├── create_new_db.sh     # Recreates an SQLite DB from sql/*.sql (db path optional)
│   └── dump_db.sh           # Regenerates DBIx::Class result classes from a given live DB
├── customers/               # One JSON config per customer/bot (multi-tenant mode)
├── data/                    # One SQLite database per customer/bot (multi-tenant mode)
├── logs/                    # Per-bot logs
├── lib/
│   ├── RequestBot.pm        # Main bot logic — extends Telegram::Bot::Brain
│   └── RequestBot/
│       ├── BotConfig.pm     # Loads/discovers per-customer config files
│       ├── BotManager.pm    # Starts and supervises multiple bot instances
│       ├── Schema.pm        # DBIx::Class schema (auto-generated)
│       └── Schema/Result/
│           ├── Request.pm   # ORM class for the `request` table
│           ├── String.pm    # ORM class for the `string` table (localised bot messages)
│           └── User.pm      # ORM class for the `user` table
├── sql/
│   ├── 00_schema.sql        # DDL for all three tables
│   └── 20_strings.sql       # Seed data for bot reply strings
└── t/
    ├── 01_unit.t            # Unit tests for dispatch and command logic
    └── etc/fixtures/
        ├── strings.pl       # Test fixture: string table rows
        └── user.pl          # Test fixture: user table rows
```

## Database Schema

Three SQLite tables:

- **`user`** — one row per Telegram user who has contacted the bot. Tracks `telegram_id`, `telegram_username`, `banned`, `admin`, `privacy_contact`, `seen_intro`.
- **`request`** — one row per message forwarded to the admins. Tracks `sender` (FK → user), `text`, `received` (Unix epoch), `responded` (0/1).
- **`string`** — key/value store for bot reply copy (`identifier` PK, `string_en`).

## Bot Commands

| Command | Who | Effect |
|---|---|---|
| `/start`, `/help` | Anyone | Returns help text (+ admin help if admin) |
| `/privacy` | Anyone | Returns privacy notice and contact username |
| `/whereami` | Anyone | Returns the current chat ID (debug) |
| `/open` | Admin only | Lists all unresolved requests |
| `/showrequest_N` | Admin only | Shows full text of request N |
| `/close_N` | Admin only | Marks request N resolved and notifies the original sender |

Any other private-chat message is treated as a new request: it is stored in the DB and forwarded to `target_chat_id`.

## Tooling

### Install dependencies
```bash
cpanm --installdeps .        # reads cpanfile
# or
carton install
```

### Quick Setup (Multi-tenant)

1. Create one customer config per bot under `customers/`, for example `customers/acme.json`.
2. For each customer config filename `<name>.json`, create its database at `data/<name>.db`.
3. Initialise each database:

```bash
bash bin/create_new_db.sh data/acme.db
bash bin/create_new_db.sh data/contoso.db
```

4. Start all configured bots from one process:

```bash
perl bin/bot.pl
```

Optional: point to a different customers directory:

```bash
perl bin/bot.pl --config-dir /path/to/customers
```

### Initialise / reset the database
```bash
bash bin/create_new_db.sh                 # creates requestbot.db (legacy default)
bash bin/create_new_db.sh data/acme.db    # multi-tenant per-customer database
```

### Run the bot
```bash
perl bin/bot.pl                 # multi-tenant: load all customers/*.json
perl bin/bot.pl --config-dir customers
perl bin/bot.pl config.json     # compatibility mode (single legacy config)
```

### Run tests
```bash
prove -l t/                  # -l adds lib/ to @INC
```

### Regenerate ORM classes from a live database
```bash
bash bin/dump_db.sh               # defaults to ./requestbot.db
bash bin/dump_db.sh data/acme.db  # target a specific per-customer DB
```

## Configuration

### Multi-tenant mode

Each bot/customer has one file in `customers/` with this shape:

```json
{
  "token": "<Telegram bot token>",
  "target_chat_id": <admin group chat ID (negative integer for groups)>
}
```

Example: `customers/acme.json` uses `data/acme.db` and `logs/acme.log`.

### Compatibility mode

Legacy `config.json` is still supported for single-bot startup:

```json
{
  "token": "<Telegram bot token>",
  "target_chat_id": <admin group chat ID (negative integer for groups)>
}
```

Obtain the bot token from [@BotFather](https://t.me/BotFather). Use `/whereami` in the target group to retrieve `target_chat_id`.

## Migration From Existing Installation

For each existing single-bot installation:

1. Stop the running bot process.
2. Choose a customer name, e.g. `acme`.
3. Create `customers/acme.json` with the existing token and target chat ID.
4. Copy the existing DB file to `data/acme.db`.
5. Start the new manager process once:

```bash
perl bin/bot.pl
```

Compatibility fallback is available during transition:

```bash
perl bin/bot.pl config.json
```

## Coding Conventions

- All Perl modules use `use strict; use warnings;` and `use utf8;` where necessary.
- `Mojo::Base` attribute syntax (`has`) is used for bot attributes (inherited via `Telegram::Bot::Brain`).
- DBIx::Class result classes are generated by `DBIx::Class::Schema::Loader`; do not manually edit the auto-generated section above the `md5sum` marker.
- Bot reply text is stored in the `string` table so it can be updated without code changes.
- Logging uses `Log::Dispatch`; errors are also printed to STDERR via the `Screen` output.
- Add new dependencies to `cpanfile`.