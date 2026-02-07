# Purpose 
Just an exploration of building my own agent


# Running

## Development Mode

```bash
git clone git@github.com:Hyper-Unearthing/rubister.git
cd rubister

bundle exec ruby ./run_agent.rb --model "claude_code/claude-sonnet-4-5" -m "whats this app" | ./format_output.rb

bundle exec ruby ./run_agent.rb --model "claude_code/claude-sonnet-4-5" | ./format_output.rb # Interactive mode

bundle exec ruby ./run_agent.rb --model "claude_code/claude-sonnet-4-5" # no formatting
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
