# Features Built

Tracks features gruv has built for itself.

## Entries
- Added persistent per-channel echo mode stored in `instance/channel_preferences.json`, plus an `Echo` tool for one-shot verbatim replies and enabling/disabling echo mode.
- Fixed Telegram photo processing to only download the highest quality version instead of all size variants (2026-03-19).
- Fixed clone task session initialization so background workers can resume/create file sessions from stored clone session identifiers/paths without crashing on keyword arguments (2026-03-19).
- Preserved Telegram media albums by buffering messages with the same `media_group_id` and inserting one grouped inbox row with combined attachments and album metadata (2026-03-19).
- Fixed clone task workers to reopen or create their file-backed sessions from `session_path` while preserving stored `session_id`/`session_start`, preventing Hash-vs-String crashes during startup (2026-03-20).
- Fixed clone task worker startup by removing bad `require_relative` OAuth dependencies and restoring direct provider/auth setup plus file-backed clone sessions (2026-04-03).
- Fixed session compaction to accept structured `AssistantMessage` streaming results as well as hash-style `choices` payloads, preventing clone-task crashes during compaction (2026-04-04).

## Lessons
<!-- Append entries here when a mistake is made and corrected, so it is never repeated. Format: date, what went wrong, correct approach. -->
- **2026-03-19**: Telegram photo handling - Telegram sends multiple sizes of each photo (thumbnail, small, medium, large). Was downloading ALL sizes causing storage bloat and confusion. **Correct approach**: Select only the largest photo by `file_size` field to download the best quality version.
- **2026-03-19**: Inbox SQL lookup - Queried a non-existent `inbox_items` table while looking up a message row. **Correct approach**: Use the ActiveRecord-backed `messages` table for inbox message records.
- **2026-03-19**: Clone task retrying - Starting the same failed clone task multiple times concurrently corrupted its shared session transcript and caused tool-call/tool-result mismatch errors. **Correct approach**: Ensure only one worker runs per clone task, and when a failed task's session may be dirty, spawn a fresh clone task with a new session instead of reusing the corrupted one.
- **2026-03-20**: Telegram Markdown replies - Sent an unescaped Markdown message containing filesystem output with underscores/backticks, causing `can't parse entities` errors. **Correct approach**: For raw command output or file paths, either escape Markdown-sensitive characters or send plain text with no `parse_mode`.
- **2026-04-03**: Clone task worker startup - Required non-existent `lib/openai_oauth` and `lib/anthropic_oauth` files, so background clones crashed before starting. **Correct approach**: Reuse the real provider/auth setup inline (as in `run_agent.rb`) and keep clone sessions file-backed via `FileSessionManager` using the stored `session_path` and session identity.
- **2026-04-03**: Compaction test doubles - Stubbed `client.chat` in a session compaction test, but `CompactionPrompt` actually calls `client.stream`. **Correct approach**: Match test doubles to the real adapter interface and accept extra keyword args used by the prompt wrapper.
- **2026-04-03**: Git add on ignored runtime files - Tried to `git add` an ignored `instance/` file normally, so staging failed. **Correct approach**: Use `git add -f` for intentionally tracked ignored files, or stage only non-ignored paths.
- **2026-04-04**: Session compaction result parsing - Assumed compaction responses always had a hash-style `:choices` payload, but streaming adapters can return structured `AssistantMessage` objects. **Correct approach**: In compaction code, accept both structured response objects (`content`/`usage`) and hash-style payloads before extracting text summaries.
- **2026-04-04**: Ruby require typo during inspection - Mistyped `llm_gateway` as `llub_gateway` in a quick verification command, causing a misleading `LoadError`. **Correct approach**: Reuse the exact gem/library name when probing runtime classes, especially in ad-hoc shell checks.
- **2026-04-04**: Random file sampling command - Tried to use `shuf` to pick random tracked files, but `shuf` was not installed on this machine. **Correct approach**: Use a portable Ruby one-liner (`files.sample(n)`) for random file selection instead of assuming GNU coreutils are available.
- **2026-04-04**: Session events SQL inspection - Queried `session_events` using non-existent columns like `created_at` and `payload`, causing a SQL error. **Correct approach**: Check the table schema first (`PRAGMA table_info(session_events)`) and use the actual columns such as `timestamp`, `usage_json`, and `data_json`.
- **2026-04-27**: Unified send tools registration - Tried to use `SendMessage`/`GetMe` before writer registrations were loaded into the tool runtime, so Discord replies failed with `Platform 'discord' not configured`. **Correct approach**: Ensure `lib/agents/tools.rb` requires `modes/*_writer.rb` before loading tool classes so `WriterRegistry.register_if_configured(...)` runs in tool-enabled processes.
