# Purpose 
Just an exploration of building my own agent

# Running

```
git clone git@github.com:Hyper-Unearthing/gruv.git
cd gruv
```

Using OpenAI OAuth Codex
```bash
ruby setup_provider.rb openai
./gruv -p openai_oauth_codex
```

Using Anthropic provider (OAuth from auth file if present, otherwise API key env var)
```bash
ruby setup_provider.rb anthropic
./gruv -p anthropic_apikey_messages
```

Using OpenAI API key providers
```bash
OPENAI_API_KEY=... ./gruv -p openai_apikey_completions
OPENAI_API_KEY=... ./gruv -p openai_apikey_responses
```

`-p` maps directly to llm_gateway provider keys. Use `-m` for model.
OAuth auth is read from `~/.config/gruv/auth.json`.

Stream test provider/model combinations:
```bash
# openai_apikey_completions_gpt_5_1
OPENAI_API_KEY=... ./gruv -p openai_apikey_completions -m gpt-5.1

# anthropic_apikey_messages_claude_sonnet_4
# (uses anthropic OAuth token from auth.json if present, else ANTHROPIC_API_KEY)
ANTHROPIC_API_KEY=... ./gruv -p anthropic_apikey_messages -m claude-sonnet-4-20250514

# openai_apikey_responses_gpt_5_4
OPENAI_API_KEY=... ./gruv -p openai_apikey_responses -m gpt-5.4

# openai_oauth_codex_gpt_5_4
ruby setup_provider.rb openai
./gruv -p openai_oauth_codex -m gpt-5.4
```

## Logging

Gruv uses an event-based logging system (`lib/logging.rb`) instead of direct `puts` for operational messages.

- Runtime and operational logs are emitted via `Logging.instance.notify(name, payload)`.
- Use scoped names (for example: `daemon.start`, `daemon.message.complete`, `setup.error.provider_not_found`) and include details in the payload hash.
- Logs are written to `instance/logs.jsonl` by `LogFileWriter`.


Each JSONL log entry includes:
- `name` (event name, e.g. `log`, `setup.start`, `daemon.message.complete`)
- `payload` (event data)
- `timestamp`
- `source_location` (`filepath`, `lineno`, `label`) when available

```bash
  # Single message mode
  ./gruv --message "whats this app"
```

```bash
  # resume, you can resume in -m or interactive mode
  ./gruv -s sessions/20260224_164714_1846b412-9260-4e18-aa96-c1b67eb93581.jsonl
```

## Distribution

Packaging/distributable tarball flow has been removed.
Run Gruv directly from source with Bundler (`./gruv ...`).
