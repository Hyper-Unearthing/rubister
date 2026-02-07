#!/usr/bin/env ruby
require 'json'

# Enable immediate output flushing for real-time streaming
$stdout.sync = true

# ANSI color codes
COLORS = {
  reset: "\e[0m",
  bold: "\e[1m",
  dim: "\e[2m",
  blue: "\e[34m",
  cyan: "\e[36m",
  green: "\e[32m",
  yellow: "\e[33m",
  red: "\e[31m",
  magenta: "\e[35m"
}.freeze

# Format Ruby hash output nicely with colors based on type
def format_hash(line)
  # Convert Ruby hash syntax to actual hash
  hash = eval(line)

  # Get color based on message type
  type = hash[:type]
  color = case type
          when 'text' then COLORS[:green]
          when 'tool_use' then COLORS[:cyan]
          when 'tool_result' then COLORS[:blue]
          when 'error' then COLORS[:red]
          else COLORS[:yellow]
          end

  # Build header with type and id (if present)
  header = type.to_s.upcase
  if hash[:id]
    header += " (ID: #{hash[:id]})"
  elsif hash[:tool_use_id]
    header += " (ID: #{hash[:tool_use_id]})"
  end

  # Print separator with type and id
  puts
  separator_length = [78 - header.length - 3, 0].max
  puts "#{color}#{COLORS[:bold]}┌─ #{header} #{COLORS[:reset]}#{color}#{'─' * separator_length}┐#{COLORS[:reset]}"

  # Handle text and tool_result specially - show raw content
  if type == 'text'
    text_content = hash[:text].to_s
    text_content.each_line do |content_line|
      puts "#{color}│#{COLORS[:reset]} #{content_line.chomp}"
    end
  elsif type == 'tool_result'
    content_text = hash[:content].to_s
    content_text.each_line do |content_line|
      puts "#{color}│#{COLORS[:reset]} #{content_line.chomp}"
    end
  else
    # Extract content to display for other types
    content = case type
              when 'tool_use'
                { name: hash[:name], input: hash[:input] }
              when 'error'
                { message: hash[:message] }
              else
                # For unknown types, show everything except type and ids
                hash.reject { |k, _v| %i[type id tool_use_id].include?(k) }
              end

    # Pretty print as JSON
    json_str = JSON.pretty_generate(JSON.parse(content.to_json))
    json_str.each_line do |json_line|
      puts "#{color}│#{COLORS[:reset]} #{json_line.chomp}"
    end
  end

  puts "#{color}└#{'─' * 78}┘#{COLORS[:reset]}"
rescue StandardError => e
  # If parsing fails, just print the line as-is
  puts "#{COLORS[:red]}[Parse Error]#{COLORS[:reset]} #{line}"
  puts "#{COLORS[:dim]}#{e.message}#{COLORS[:reset]}"
end

# Read from stdin line by line with explicit flushing
loop do
  line = STDIN.gets
  break if line.nil?

  line = line.chomp

  # Check if line looks like a Ruby hash (starts with {:)
  if line =~ /^\{:/
    format_hash(line)
  else
    # Pass through non-hash lines (like warnings, regular text)
    puts "#{COLORS[:dim]}#{line}#{COLORS[:reset]}" unless line.empty?
  end

  $stdout.flush
end
