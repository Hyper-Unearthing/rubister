COLORS = {
  reset: "\e[0m",
  bold: "\e[1m",
  dim: "\e[2m",
  cyan: "\e[36m",
  green: "\e[32m",
  yellow: "\e[33m",
  red: "\e[31m",
  blue: "\e[34m"
}.freeze

class Formatter
  attr_reader :in_delta

  def initialize
    @in_delta = false
    @last_role = nil
    @saw_stream_delta = false
  end

  def on_notify(event)
    name = fetch(event, :name).to_s
    payload = fetch(event, :payload)

    # Global debug events are noisy in the UI.
    return if name == 'debug'
    # In interactive mode, user input is already visible on the prompt line.
    return if name == 'user_message'

    if name == 'done'
      puts if @in_delta
      @in_delta = false
      puts
      return
    end

    event = payload unless payload.nil?

    role = fetch(event, :role)

    if role
      puts if @in_delta
      @in_delta = false

      contents = Array(fetch(event, :content))

      if role.to_s == 'user'
        puts if @last_role
        display_user_message(contents)
      else
        # If we already streamed deltas for this assistant turn, skip replaying
        # finalized text/thinking blocks (and tool_use blocks that are rendered
        # via dedicated tool_use events).
        if name == 'assistant_message' && @saw_stream_delta
          contents = contents.reject do |content|
            %w[text thinking tool_use].include?(fetch(content, :type).to_s)
          end
        end

        contents.each do |content|
          display_llm_activity(content)
        end
      end

      @last_role = role.to_s
      @saw_stream_delta = false if name == 'assistant_message'
    else
      display_llm_activity(event)
      type_s = fetch(event, :type).to_s
      @saw_stream_delta = true if %w[text_delta thinking_delta].include?(type_s)
    end
  rescue StandardError => e
    puts if @in_delta
    @in_delta = false
    puts "#{COLORS[:red]}[formatter error] #{e.message}#{COLORS[:reset]}"
  end

  def display_user_message(contents)
    text_contents = Array(contents).select { |c| fetch(c, :type).to_s == 'text' }
    first = text_contents.first
    return if first.nil?

    puts "> #{fetch(first, :text)}"
    text_contents.drop(1).each { |content| puts fetch(content, :text) }
  end

  def display_llm_activity(hash)
    type_s = fetch(hash, :type).to_s

    case type_s
    when 'text'
      puts fetch(hash, :text)
    when 'text_delta'
      @in_delta = true
      print fetch(hash, :text)
    when 'thinking_delta'
      @in_delta = true
      print "#{COLORS[:dim]}#{fetch(hash, :thinking)}#{COLORS[:reset]}"
    when 'thinking'
      thinking = fetch(hash, :thinking).to_s
      puts "#{COLORS[:dim]}#{thinking}#{COLORS[:reset]}" unless thinking.empty?
    when 'tool_use'
      puts if @in_delta
      @in_delta = false
      puts
      puts "  #{COLORS[:cyan]}#{COLORS[:bold]}#{fetch(hash, :name)}#{COLORS[:reset]}"
      Array(fetch(hash, :input)).each do |key, value|
        puts "  #{COLORS[:dim]}#{key}: #{value}#{COLORS[:reset]}"
      end
      puts "  #{COLORS[:dim]}id: #{fetch(hash, :id)}#{COLORS[:reset]}"
    when 'tool_result'
      puts if @in_delta
      @in_delta = false
      id = fetch(hash, :tool_use_id)
      id_part = id ? " (#{id})" : ''
      content = fetch(hash, :content).to_s
      puts
      puts "  #{COLORS[:green]}#{COLORS[:bold]}Result#{id_part}#{COLORS[:reset]}"
      content.each_line { |line| puts "  #{line.chomp}" }
    when 'done'
      puts if @in_delta
      @in_delta = false
      puts
    when 'error'
      puts if @in_delta
      @in_delta = false
      puts "#{COLORS[:red]}[error] #{fetch(hash, :message)}#{COLORS[:reset]}"
    else
      puts if @in_delta
      @in_delta = false
      puts "#{COLORS[:dim]}#{hash.inspect}#{COLORS[:reset]}"
    end
  end

  private

  def fetch(hash, key)
    return nil unless hash.is_a?(Hash)

    hash[key] || hash[key.to_s]
  end
end
