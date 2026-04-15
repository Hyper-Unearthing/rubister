require_relative 'message'
require 'reline'

class InteractiveRunner < MessageMode
  def run
    with_readline do
      puts "Interactive mode (type 'exit' or 'quit' to end, Ctrl+D to send EOF)"
      puts "Type 'compaction' to compact old conversation context."
      puts '---'

      replay_transcript

      loop do
        input = Reline.readline('> ', true)
        break if input.nil? # Handle EOF (Ctrl+D)

        input = input.strip

        if input.casecmp('compaction').zero?
          @agent_session.compact
          next
        elsif input.empty?
          next
        elsif input.match?(/^(exit|quit)$/i)
          break
        end

        super(input)
      end

      puts 'Goodbye!'
    end
  end

  private

  def with_readline
    tty_in = nil
    tty_out = nil

    # Point Reline at /dev/tty so bracketed paste works even when stdout is piped
    tty_in = File.open('/dev/tty', 'r')
    tty_out = File.open('/dev/tty', 'w')
    Reline.input = tty_in
    Reline.output = tty_out

    yield
  ensure
    tty_in&.close
    tty_out&.close
  end

  def replay_transcript
    messages = @agent_session.model_input_messages
    return if messages.empty?

    messages.each do |message|
      @formatter.replay_message(message)
    end

    last = messages.last
    last_role = last[:role] if last.is_a?(Hash)
    puts if ['assistant', :assistant].include?(last_role)
  end
end
