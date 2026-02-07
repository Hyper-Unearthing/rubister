require 'tty-prompt'
require 'llm_gateway'
require_relative 'claude_code_clone'
require 'json'

# Terminal Runner for FileSearchBot
class FileSearchTerminalRunner
  AUTH_FILE_PATH = File.expand_path('~/.local/share/opencode/auth.json')

  def initialize
    @prompt = TTY::Prompt.new
  end

  def start
    puts "First, let's configure your LLM settings:\n\n"

    model, api_key, refresh_token, expires_at = setup_configuration
    bot = ClaudeCloneClone.new(model, api_key, refresh_token: refresh_token, expires_at: expires_at)

    puts "Type 'quit' or 'exit' to stop.\n\n"

    loop do
      user_input = @prompt.ask('What can i do for you?')

      break if %w[quit exit].include?(user_input.downcase)

      bot.query(user_input)
    end
  end

  private

  def setup_configuration
    model = @prompt.ask('Enter model (default: claude_code/claude-sonnet-4-5):') do |q|
      q.default 'claude_code/claude-sonnet-4-5'
    end

    # Check if using claude_code provider
    if model.start_with?('claude_code/')
      credentials = load_auth_credentials
      if credentials
        puts "Loaded OAuth credentials from #{AUTH_FILE_PATH}"
        return [model, credentials[:access], credentials[:refresh], credentials[:expires]]
      else
        puts "Warning: Could not load auth credentials from #{AUTH_FILE_PATH}"
        puts 'Falling back to manual API key entry.'
      end
    end

    api_key = @prompt.mask('Enter your API key:') do |q|
      q.required true
    end

    [model, api_key, nil, nil]
  end

  def load_auth_credentials
    return nil unless File.exist?(AUTH_FILE_PATH)

    auth_data = JSON.parse(File.read(AUTH_FILE_PATH))
    anthropic_data = auth_data['anthropic']
    return nil unless anthropic_data

    # Convert expires timestamp to Time object if present
    expires = anthropic_data['expires']
    expires_at = expires ? Time.at(expires) : nil

    {
      access: anthropic_data['access'],
      refresh: anthropic_data['refresh'],
      expires: expires_at
    }
  rescue JSON::ParserError, Errno::ENOENT => e
    puts "Error reading auth file: #{e.message}"
    nil
  end
end

# Start the bot
if __FILE__ == $0
  runner = FileSearchTerminalRunner.new
  runner.start
end
