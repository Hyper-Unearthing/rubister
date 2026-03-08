# Inbox System

Gruv uses a SQLite-backed inbox at `instance/gruv.sqlite3`.

## Overview

- The inbox is the `messages` table.
- Multiple writers insert messages independently.
- The daemon worker is the single reader/processor.

Writers:
- Writer processes are registered dynamically via `WriterRegistry`.
- Typical sources include chat integrations and system-produced events.
- See **Writer Registry** below for registration and boot flow.

Reader:
- `gruv` daemon worker main loop

Process model:
- `./gruv --daemon` runs a supervisor process.
- Supervisor starts 1 daemon worker plus all registered writer roles.
- `SIGINT`/`SIGTERM` on supervisor stops all children.

## Writer Registry

Writers are discovered through `WriterRegistry` (`lib/writer_registry.rb`).

How it works:
1. `gruv` requires every file matching `modes/*_writer.rb`.
2. Each writer file registers itself with a role key:
   - `WriterRegistry.register(:my_writer, MyWriterMode)`
   - or `WriterRegistry.register_if_configured(:my_writer, MyWriterMode, config_key: 'my_key')`
3. In daemon supervisor mode, `WriterRegistry.roles` is iterated and one child process is spawned per role.
4. Each writer child is started by relaunching `gruv` with `GRUV_ROLE=<role>`.
5. On boot, `gruv` resolves that role via `WriterRegistry.resolve(role)` and runs the writer mode class.

Notes:
- The registry is in-memory and process-local.
- If no writer registers, daemon supervisor starts only the daemon worker.
- `register_if_configured` checks `AppConfig.load` and skips registration if the config key is missing.

## Messages Table

```sql
CREATE TABLE messages (
  id         INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  source     VARCHAR NOT NULL,                            -- 'system' | 'clone' | 'telegram'
  source_id  VARCHAR NOT NULL,                            -- cron job name | clone PID | chat ID
  state      VARCHAR NOT NULL DEFAULT 'pending',          -- 'pending' | 'processed'
  message    TEXT NOT NULL,
  metadata   JSON NOT NULL DEFAULT '{}',
  timestamp  VARCHAR NOT NULL                             -- ISO 8601 UTC
);

CREATE INDEX index_messages_on_state ON messages(state);
CREATE INDEX index_messages_on_source ON messages(source);
CREATE INDEX index_messages_on_timestamp ON messages(timestamp);
```

Notes:
- `metadata` is a JSON column and is never nullable.
- If writers omit `metadata`, DB default `{}` is applied.
- Passing explicit `NULL` for `metadata` violates `NOT NULL`.

## Contacts Table (enrichment)

```sql
CREATE TABLE contacts (
  id                INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  name              VARCHAR,
  telegram_chat_id  VARCHAR NOT NULL,
  tags              TEXT,
  notes             TEXT,
  user_requests     TEXT,
  created_at        DATETIME(6) NOT NULL,
  updated_at        DATETIME(6) NOT NULL
);

CREATE UNIQUE INDEX index_contacts_on_telegram_chat_id
  ON contacts(telegram_chat_id);
```

`contacts` is joined at read-time to enrich pending messages.

## Telegram Metadata Shape

Current writer metadata keys:
- `update_id`
- `message_id`
- `from_id`
- `from_username`
- `from_first_name`
- `chat_type` (`private`, `group`, `supergroup`, etc.)
- `photo_file_ids` (array)
- `photo_file_paths` (array)
- `has_voice`
- `voice_file_id`

Photo flags/singular fields were removed (`has_photo`, `photo_file_id`, `photo_file_path`).
Use `photo_file_ids`/`photo_file_paths` to determine photo presence.

## Processing Flow

1. Writers insert rows with `state = 'pending'`.
2. Daemon reads pending rows with priority order:
   1. `telegram`
   2. `clone`
   3. `system`
   Then FIFO by `timestamp` within each source.
3. Agent processes each message.
4. Daemon acknowledges by marking the row processed:

```sql
UPDATE messages SET state = 'processed' WHERE id = ?;
```

## Priority Query

```sql
SELECT m.id, m.source, m.source_id, m.message, m.metadata, m.timestamp,
       c.name, c.tags, c.notes, c.user_requests
FROM messages m
LEFT JOIN contacts c ON m.source_id = c.telegram_chat_id
WHERE m.state = 'pending'
ORDER BY
  CASE m.source
    WHEN 'telegram' THEN 1
    WHEN 'clone'    THEN 2
    WHEN 'system'   THEN 3
  END,
  m.timestamp ASC;
```

## Delivery/Ack Boundary (Important)

For each message, ordering must be:
1. Execute `agent.run(...)` (inside restart catch)
2. Persist output/log events
3. `UPDATE ... state = 'processed'`
4. Only then continue restart control flow

This guarantees restart-triggering messages are acknowledged before daemon `exec`, avoiding duplicate processing after reboot.

## Retention

Messages are not deleted in normal operation; they transition `pending -> processed`.
Cleanup is handled separately (TTL / auto-purge).
