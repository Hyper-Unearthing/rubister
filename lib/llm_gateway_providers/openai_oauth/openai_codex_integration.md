# OpenAI Codex Integration via ChatGPT OAuth

Technical reference for the OpenAI Codex provider, which accesses OpenAI models through ChatGPT Plus/Pro OAuth tokens rather than the platform API. For how this provider is built on top of `llm_gateway`, see [Building Providers](building_providers.md).

## The Core Distinction: Platform API vs ChatGPT Backend

OpenAI has two completely separate API surfaces:

| | Platform API | ChatGPT Backend (Codex) |
|---|---|---|
| **Base URL** | `https://api.openai.com/v1` | `https://chatgpt.com/backend-api/codex` |
| **Auth** | API key (`sk-...`) | OAuth bearer token (JWT) |
| **Billing** | Prepaid API credits | ChatGPT Plus/Pro subscription |
| **API format** | Chat Completions or Responses | Responses only |
| **Auth header** | `Authorization: Bearer sk-...` | `Authorization: Bearer <jwt>` + `chatgpt-account-id: <uuid>` |
| **Models** | `gpt-4o`, `gpt-4.1`, etc. | `gpt-5.1-codex-mini`, `gpt-5.1`, `gpt-5.2-codex`, etc. |

A ChatGPT Plus OAuth token sent to `api.openai.com` returns **"You exceeded your current quota"** because there are no API credits on the account. The token must be routed to `chatgpt.com/backend-api/codex` instead.

## OAuth Flow

The OAuth flow uses OpenAI's auth system with PKCE (Proof Key for Code Exchange):

1. **Authorization URL**: `https://auth.openai.com/oauth/authorize`
2. **Token exchange**: `https://auth.openai.com/oauth/token`
3. **Client ID**: `app_EMoamEEZ73f0CkXaXp7hrann` (shared Codex CLI client)
4. **Redirect URI**: `http://localhost:1455/auth/callback`
5. **Scopes**: `openid profile email offline_access`

### Key OAuth Parameters

The authorization URL must include:
- `codex_cli_simplified_flow=true` — enables the simplified Codex login flow
- `id_token_add_organizations=true` — includes org info in the token
- `code_challenge` + `code_challenge_method=S256` — PKCE challenge

### Account ID Extraction

The `account_id` is **not** returned in the token response body. It must be extracted from the JWT access token payload:

```ruby
# The access token is a JWT with three base64url-encoded parts
payload = JSON.parse(Base64.urlsafe_decode64(token.split(".")[1]))
account_id = payload["https://api.openai.com/auth"]["chatgpt_account_id"]
```

This `account_id` (a UUID like `6f6473c8-41a9-4ebd-8dce-e9692a4fc18a`) is required in every API request as the `chatgpt-account-id` header. Without it, the API returns "No such organization". Note: this is **not** the `openai-organization` header used by the platform API.

### Token Refresh

Tokens expire and must be refreshed using the `refresh_token`:

```ruby
POST https://auth.openai.com/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token&refresh_token=<token>&client_id=<client_id>
```

## Codex Responses API

### Endpoint

```
POST https://chatgpt.com/backend-api/codex/responses
```

### Required Headers

```
Authorization: Bearer <oauth_access_token>
chatgpt-account-id: <account_id_from_jwt>
OpenAI-Beta: responses=experimental
Content-Type: application/json
```

### Request Body

The Codex endpoint uses the Responses API format with some specific constraints:

```json
{
  "model": "gpt-5.1-codex-mini",
  "instructions": "You are a helpful assistant.",
  "input": [
    { "role": "user", "content": [{ "type": "input_text", "text": "hello" }] }
  ],
  "store": false,
  "stream": true,
  "tools": [
    {
      "type": "function",
      "name": "my_tool",
      "description": "Does something",
      "parameters": { "type": "object", "properties": { ... } }
    }
  ]
}
```

### Codex-Specific Constraints

These will return `400 Bad Request` if violated:

| Constraint | Error Message |
|---|---|
| Must use a codex model | `The 'gpt-4o' model is not supported when using Codex with a ChatGPT account.` |
| Must include `instructions` | `Instructions are required` |
| Must set `store: false` | `Store must be set to false` |
| Cannot send `max_output_tokens` | `Unsupported parameter: max_output_tokens` |

### Differences from Standard Responses API

- **`instructions`** is mandatory (replaces system messages)
- **`store`** must be `false`
- **`max_output_tokens`** is not supported
- **`input`** uses `input_text` content type (mapped by the input mapper)
- System messages should be extracted and concatenated into the `instructions` string

### Available Models (ChatGPT Plus)

- `gpt-5.1-codex-mini` — cheapest, good for most tasks
- `gpt-5.1` — full GPT-5.1
- `gpt-5.1-codex-max` — maximum capability
- `gpt-5.2-codex` — latest
- `gpt-5.3-codex` — bleeding edge

## SSE Stream Format

The Responses API uses a different SSE format from Chat Completions. Each event has a named `event:` field and a `data:` JSON payload.

### Event Types

| Event | Description | Key Fields |
|---|---|---|
| `response.created` | Response object created | `data.id`, `data.model` |
| `response.in_progress` | Processing started | — |
| `response.output_item.added` | New output item (message, function_call, reasoning) | `data.item.type`, `data.item.call_id`, `data.item.name` |
| `response.content_part.added` | Content part added to message | `data.part.type` |
| `response.output_text.delta` | Text token delta | `data.delta` (string) |
| `response.reasoning_summary_text.delta` | Reasoning/thinking delta | `data.delta` (string) |
| `response.function_call_arguments.delta` | Tool call arguments delta | `data.delta` (string fragment of JSON) |
| `response.output_item.done` | Output item completed | `data.item` (full item with final state) |
| `response.content_part.done` | Content part completed | — |
| `response.completed` | Full response with usage stats | `data.response.usage` |

### Chat Completions vs Responses Stream Comparison

**Chat Completions** (old format):
```
event: chunk
data: {"choices":[{"delta":{"content":"Hello"}}]}
```

**Responses** (new format):
```
event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":"Hello"}
```

Key differences:
- Chat Completions has a single `chunk` event type with all data in `choices[0].delta`
- Responses has fine-grained event types (`response.output_text.delta`, `response.function_call_arguments.delta`, etc.)
- Tool calls in Responses come as separate `response.output_item.added` events with `type: "function_call"`, arguments stream via `response.function_call_arguments.delta`
- Reasoning/thinking is a first-class concept via `response.reasoning_summary_text.delta`

## Debugging Tips

The Codex endpoint returns error details in a `{"detail": "..."}` format, but `llm_gateway`'s error handler looks for `{"error": {"message": "..."}}`. This means error messages often show as generic `LlmGateway::Errors::APIStatusError` without the actual detail. To debug:

```ruby
# Make a raw request to see the actual error body
uri = URI("https://chatgpt.com/backend-api/codex/responses")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
request = Net::HTTP::Post.new(uri)
# ... set headers and body ...
response = http.request(request)
puts response.code, response.body
```

Common 400 errors and their causes:
- **"not supported when using Codex"** → wrong model name
- **"Instructions are required"** → missing `instructions` field
- **"Store must be set to false"** → missing `store: false`
- **"Unsupported parameter"** → sent a field the Codex endpoint doesn't accept

## File Structure

```
lib/llm_gateway_providers/openai_oauth/
├── oauth_flow.rb          # PKCE OAuth flow, token exchange, refresh
├── token_manager.rb       # Token expiry tracking, auto-refresh
├── client.rb              # HTTP client (extends LlmGateway::Clients::OpenAi)
├── stream_output_mapper.rb # Responses API SSE → normalized events
└── adapter.rb             # Wires client + mappers together
```
