#!/usr/bin/env ruby
require 'json'

$stdout.sync = true

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

in_delta = false

loop do
  line = STDIN.gets
  break if line.nil?

  line = line.chomp
  next if line.empty?

  if line =~ /^\{:/
    begin
      hash = eval(line)
      type = hash[:type]

      type_s = type.to_s

      case type_s
      when "text_delta"
        in_delta = true
        print hash[:text]
      when "thinking_delta"
        in_delta = true
        print "#{COLORS[:dim]}#{hash[:thinking]}#{COLORS[:reset]}"
      when "tool_use"
        puts if in_delta
        in_delta = false
        puts
        puts "  #{COLORS[:cyan]}#{COLORS[:bold]}#{hash[:name]}#{COLORS[:reset]}"
        hash[:input].each do |key, value|
          puts "  #{COLORS[:dim]}#{key}: #{value}#{COLORS[:reset]}"
        end
        puts "  #{COLORS[:dim]}id: #{hash[:id]}#{COLORS[:reset]}"
      when "tool_result"
        puts if in_delta
        in_delta = false
        id_part = hash[:tool_use_id] ? " (#{hash[:tool_use_id]})" : ""
        content = hash[:content].to_s
        puts
        puts "  #{COLORS[:green]}#{COLORS[:bold]}Result#{id_part}#{COLORS[:reset]}"
        content.each_line do |l|
          puts "  #{l.chomp}"
        end
      when "done"
        puts if in_delta
        in_delta = false
        puts
      when "error"
        puts if in_delta
        in_delta = false
        puts "#{COLORS[:red]}[error] #{hash[:message]}#{COLORS[:reset]}"
      else
        puts if in_delta
        in_delta = false
        puts line
      end
    rescue StandardError
      puts if in_delta
      in_delta = false
      puts line
    end
  else
    puts if in_delta
    in_delta = false
    puts "#{COLORS[:dim]}#{line}#{COLORS[:reset]}"
  end

  $stdout.flush
end

puts if in_delta
