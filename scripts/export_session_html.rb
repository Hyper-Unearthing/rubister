#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require_relative "../lib/session_html_exporter"

options = {
  pi_root: DEFAULT_PI_ROOT,
  output: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/export_session_html.rb INPUT_JSONL [options]"

  opts.on("-o", "--output PATH", "Output HTML path") do |v|
    options[:output] = v
  end

  opts.on("--pi-root PATH", "Path to pi-mono repo (default: #{DEFAULT_PI_ROOT})") do |v|
    options[:pi_root] = v
  end
end

parser.parse!
input = ARGV[0]
if input.nil?
  puts parser
  exit 1
end

output = options[:output] || "rubister-session-#{File.basename(input, ".jsonl")}.html"

exporter = SessionHtmlExporter.new(pi_root: options[:pi_root])
html = exporter.export_from_jsonl_file(input)
File.write(output, html)

puts "Wrote #{output}"
