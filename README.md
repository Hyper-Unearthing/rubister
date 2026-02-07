# Purpose 
Just an exploration of building my own agent


# Running

```bash
git clone git@github.com:Hyper-Unearthing/rubister.git
cd rubister

bundle exec ruby ./run_agent.rb --model "claude_code/claude-sonnet-4-5" -m "whats this app" | ./format_output.rb

bundle exec ruby ./run_agent.rb --model "claude_code/claude-sonnet-4-5" | ./format_output.rb # Interactive mode

bundle exec ruby ./run_agent.rb --model "claude_code/claude-sonnet-4-5" # no formatting
```
