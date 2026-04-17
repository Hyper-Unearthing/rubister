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
  def replay_message(event)
    render_event_hash(event)
  end

  def render_agent_event(agent_event)
    event = agent_event.to_h

    case event[:type]
    when :message_update
      stream_event = event[:stream_event]
      display_stream_event(stream_event[:type], stream_event)
    when :message_end
      render_message_payload(event[:message])
    when :turn_end
      tool_result_message = {
        role: 'user',
        content: event[:tool_results].flat_map { |tool_result| tool_result[:content] }
      }
      render_message_payload(tool_result_message)
    when :agent_end
      puts("\n\r")
    else
      render_event_hash(event)
    end
  rescue StandardError => e
    puts "#{COLORS[:red]}[formatter error] #{e.message}#{COLORS[:reset]}"
  end

  def on_notify(event)
    name = event.dig(:name)
    payload = event.dig(:payload)

    if name.nil? && event[:type]
      type = event[:type].to_sym
      if stream_event?(type)
        display_stream_event(type, event)
        return
      end
    end

    if stream_event?(name)
      display_stream_event(name, payload || {})
      return
    end

    return if name == :message_update

    if name == :done
      # Ensure the newline is emitted and flushed immediately at stream end.
      puts("\n\r")
      return
    end

    event = payload unless payload.nil?
    render_event_hash(event)
  rescue StandardError => e
    puts "#{COLORS[:red]}[formatter error] #{e.message}#{COLORS[:reset]}"
  end

  def render_message_payload(message)
    render_event_hash(message)
  end

  def render_event_hash(event)
    role = event.dig(:role)

    if role
      contents = event.dig(:content)

      if role.to_s == 'user'
        display_user_message(contents)
      else
        contents.each do |content|
          # skip types that were already streamed as deltas
          next if %w[text thinking reasoning].include?(content[:type])

          display_llm_activity(content)
        end
      end
    else
      display_llm_activity(event)
    end
  end

  def stream_event?(name)
    %i[
      message_start message_delta message_end
      text_start text_delta text_end
      tool_start tool_delta tool_end
      reasoning_start reasoning_delta reasoning_end
      thinking_start thinking_delta thinking_end
    ].include?(name)
  end

  def display_stream_event(name, payload)
    case name
    when :text_delta
      puts if @last_type == 'thinking_delta'
      print payload[:delta]
      $stdout.flush
      @last_type = 'text_delta'
    when :reasoning_delta, :thinking_delta
      print "#{COLORS[:dim]}#{payload[:delta]}#{COLORS[:reset]}"
      $stdout.flush
      @last_type = 'thinking_delta'
    end
  end

  def display_user_message(contents)
    contents.each do |entry|
      if entry[:type] == 'text'
        puts "> #{entry.dig(:text)}"
      else
        display_llm_activity(entry)
      end
    end
  end

  def display_llm_activity(hash)
    case hash.dig(:type).to_s
    when 'agent_start', 'turn_start', 'message_start', 'message_update', 'message_end',
         'tool_execution_start', 'tool_execution_end', 'turn_end', 'agent_end',
         'text_start', 'text_end', 'reasoning_start', 'reasoning_end', 'thinking_start',
         'thinking_end', 'tool_start', 'tool_end', 'message_delta'
      nil
    when 'text'
      puts hash.dig(:text)
    when 'text_delta'
      puts if @last_type == 'thinking_delta'
      print hash.dig(:delta) || hash.dig(:text)
      $stdout.flush
      @last_type = 'text_delta'
    when 'thinking_delta'
      print "#{COLORS[:dim]}#{hash.dig(:delta) || hash.dig(:thinking)}#{COLORS[:reset]}"
      $stdout.flush
      @last_type = 'thinking_delta'
    when 'reasoning_delta'
      print "#{COLORS[:dim]}#{hash.dig(:delta)}#{COLORS[:reset]}"
      $stdout.flush
      @last_type = 'thinking_delta'
    when 'thinking'
      thinking = hash.dig(:thinking)
      puts "#{COLORS[:dim]}#{thinking}#{COLORS[:reset]}" unless thinking.empty?
      @last_type = 'thinking'
    when 'reasoning'
      reasoning = hash.dig(:reasoning)
      puts "#{COLORS[:dim]}#{reasoning}#{COLORS[:reset]}" unless reasoning.empty?
      @last_type = 'reasoning'
    when 'tool_use'
      @last_type = 'tool_use'
      puts
      puts "  #{COLORS[:cyan]}#{COLORS[:bold]}#{hash.dig(:name)}#{COLORS[:reset]}"
      hash.dig(:input).each do |key, value|
        puts "  #{COLORS[:dim]}#{key}: #{value}#{COLORS[:reset]}"
      end
      puts "  #{COLORS[:dim]}id: #{hash.dig(:id)}#{COLORS[:reset]}"
    when 'tool_result'
      id = hash.dig(:tool_use_id)
      id_part = id ? " (#{id})" : ''
      content = hash.dig(:content).to_s
      puts
      puts "  #{COLORS[:green]}#{COLORS[:bold]}Result#{id_part}#{COLORS[:reset]}"
      content.each_line { |line| puts "  #{line.chomp}" }
    when 'done'
      puts
    when 'error'
      puts "#{COLORS[:red]}[error] #{hash.dig(:message)}#{COLORS[:reset]}"
    else
      nil
    end
  end
end
