# Purpose 
Just an exploration of building my own agent


# Running

## Setup

Authenticate with a provider before first use. This runs an OAuth flow and saves credentials to `providers.json`:

```bash
bundle exec ruby setup_provider.rb anthropic
bundle exec ruby setup_provider.rb openai
```

You can set up multiple providers — they'll all be stored in `providers.json`.

## Development Mode

```bash
git clone git@github.com:Hyper-Unearthing/rubister.git
cd rubister

# Uses the first provider in providers.json
bundle exec ruby ./run_agent.rb -m "whats this app" | ./format_output.rb

# Pick a specific provider
bundle exec ruby ./run_agent.rb -p anthropic_oauth_messages -m "whats this app" | ./format_output.rb
bundle exec ruby ./run_agent.rb -p openai_oauth_responses -m "whats this app" | ./format_output.rb

# Override the model
bundle exec ruby ./run_agent.rb --model "claude_code/claude-sonnet-4-5" -m "whats this app" | ./format_output.rb

# Interactive mode
bundle exec ruby ./run_agent.rb | ./format_output.rb

# No formatting
bundle exec ruby ./run_agent.rb -m "whats this app"
```

## Building a Standalone Bundle

Create a distributable version that doesn't require `bundle install`:

```bash
# 1. Install dependencies in standalone mode
bundle install --standalone

# 2. Test the standalone version
./rubister --help

# 3. Package for distribution
./package.sh 1.0.0

# This creates a .tar.gz file with everything bundled
```

Users can then:
```bash
# Extract
tar -xzf rubister-1.0.0-darwin-arm64.tar.gz
rubister-1.0.0-darwin-arm64/rubister --model "claude_code/claude-sonnet-4-5" -m "Hello" | rubister-1.0.0-darwin-arm64/format_output.rb
```

## Distribution

The standalone bundle includes:
- All Ruby dependencies (in `bundle/` directory)
- Application code
- Wrapper script (`rubister`)
- No need for users to run `bundle install`

**Requirements for end users:**
- Ruby 2.7 or higher
