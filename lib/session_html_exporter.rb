# frozen_string_literal: true

require "json"
require "erb"
require "base64"
require "pathname"
require "time"

DEFAULT_PI_ROOT = "/Users/seb/work/pi-mono"
PI_EXPORT_DIR = "packages/coding-agent/src/core/export-html"
PI_DARK_THEME = "packages/coding-agent/src/modes/interactive/theme/dark.json"

class SessionHtmlExporter
  def initialize(pi_root:)
    @pi_root = pi_root
  end

  def export_from_jsonl_file(input_path)
    raise "Input file not found: #{input_path}" unless File.exist?(input_path)

    session_row, raw_entries = load_jsonl(input_path)
    export_from_transcript(raw_entries, session_row: session_row, fallback_session_id: File.basename(input_path, ".jsonl"))
  end

  def export_from_transcript(raw_entries, session_row: nil, fallback_session_id: "session")
    tool_name_by_call_id = build_tool_call_name_map(raw_entries)

    entries = raw_entries.map do |entry|
      map_entry(entry, tool_name_by_call_id)
    end.compact

    leaf_id = entries.last&.dig(:id)
    header = build_header(session_row, entries, fallback_session_id)

    session_data = {
      header: header,
      entries: entries,
      leafId: leaf_id,
      systemPrompt: nil,
      tools: nil,
      renderedTools: nil
    }

    generate_html(session_data)
  end

  private

  def load_jsonl(input_path)
    session_row = nil
    entries = []

    File.foreach(input_path) do |line|
      next if line.strip.empty?

      row = JSON.parse(line, symbolize_names: true)
      if row[:type] == "session"
        session_row = row
      else
        entries << row
      end
    end

    [session_row, entries]
  end

  def build_tool_call_name_map(raw_entries)
    map = {}

    raw_entries.each do |entry|
      next unless entry[:type] == "message"

      data = entry[:data]
      next unless data[:role] == "assistant"
      next unless data[:content].is_a?(Array)

      data[:content].each do |block|
        next unless block[:type] == "tool_use"

        map[block[:id]] = block[:name]
      end
    end

    map
  end

  def map_entry(entry, tool_name_by_call_id)
    case entry[:type]
    when "message"
      map_message_entry(entry, tool_name_by_call_id)
    when "compaction"
      {
        id: entry[:id],
        parentId: entry[:parent_id],
        timestamp: entry[:timestamp],
        type: "compaction",
        summary: entry.dig(:data, :summary).to_s,
        tokensBefore: entry.dig(:data, :tokens_before) || entry.dig(:usage, :input_tokens) || 0
      }
    else
      nil
    end
  end

  def map_message_entry(entry, tool_name_by_call_id)
    data = entry[:data]

    mapped = {
      id: entry[:id],
      parentId: entry[:parent_id],
      timestamp: entry[:timestamp],
      type: "message",
      message: nil
    }

    if data[:role] == "user" && tool_result_message?(data)
      tool_result_block = data[:content].find { |block| block[:type] == "tool_result" }
      mapped[:message] = {
        role: "toolResult",
        toolCallId: tool_result_block[:tool_use_id],
        toolName: tool_name_by_call_id[tool_result_block[:tool_use_id]],
        content: normalize_tool_result_content(tool_result_block[:content]),
        isError: false,
        details: nil
      }
      return mapped
    end

    mapped[:message] = {
      role: data[:role],
      content: normalize_message_content(data[:content]),
      stopReason: normalize_stop_reason(data[:stop_reason]),
      errorMessage: data[:error_message],
      provider: data[:provider],
      model: data[:model],
      usage: normalize_usage(data[:usage])
    }

    mapped
  end

  def tool_result_message?(data)
    return false unless data[:content].is_a?(Array)

    data[:content].all? { |block| block[:type] == "tool_result" }
  end

  def normalize_stop_reason(stop_reason)
    return nil if stop_reason.nil?

    case stop_reason
    when "tool_use"
      "toolUse"
    else
      stop_reason
    end
  end

  def normalize_usage(usage)
    return nil if usage.nil?

    {
      input: usage[:input_tokens] || 0,
      output: usage[:output_tokens] || 0,
      cacheRead: usage[:cache_read_tokens] || 0,
      cacheWrite: usage[:cache_write_tokens] || 0
    }
  end

  def normalize_message_content(content)
    return [] unless content.is_a?(Array)

    content.filter_map do |block|
      case block[:type]
      when "text", "input_text", "output_text"
        { type: "text", text: block[:text].to_s }
      when "thinking"
        { type: "thinking", thinking: block[:thinking].to_s }
      when "reasoning"
        { type: "thinking", thinking: block[:reasoning].to_s }
      when "tool_use"
        {
          type: "toolCall",
          id: block[:id],
          name: block[:name],
          arguments: block[:input] || {}
        }
      else
        nil
      end
    end
  end

  def normalize_tool_result_content(content)
    blocks = []

    if content.is_a?(Array)
      content.each do |item|
        if item.is_a?(String)
          blocks << { type: "text", text: item }
        elsif item.is_a?(Hash)
          if item[:type] == "text"
            blocks << { type: "text", text: item[:text].to_s }
          elsif item[:type] == "image"
            blocks << {
              type: "image",
              data: item[:data],
              mimeType: item[:mime_type] || item[:mimeType]
            }
          else
            blocks << { type: "text", text: JSON.pretty_generate(item) }
          end
        else
          blocks << { type: "text", text: item.to_s }
        end
      end
    else
      blocks << { type: "text", text: content.to_s }
    end

    blocks
  end

  def build_header(session_row, entries, fallback_session_id)
    first_timestamp = entries.first&.dig(:timestamp)

    {
      id: session_row&.dig(:id) || fallback_session_id,
      timestamp: normalize_header_timestamp(session_row&.dig(:timestamp), first_timestamp)
    }
  end

  def normalize_header_timestamp(raw, fallback)
    return fallback if raw.nil?

    if raw.match?(/\A\d{8}_\d{6}\z/)
      year = raw[0, 4]
      month = raw[4, 2]
      day = raw[6, 2]
      hour = raw[9, 2]
      min = raw[11, 2]
      sec = raw[13, 2]
      return "#{year}-#{month}-#{day}T#{hour}:#{min}:#{sec}Z"
    end

    raw
  end

  def generate_html(session_data)
    template_html = read_pi_file("template.html")
    template_css = read_pi_file("template.css")
    template_js = customize_template_js(read_pi_file("template.js"))
    marked_js = read_pi_file("vendor/marked.min.js")
    highlight_js = read_pi_file("vendor/highlight.min.js")

    css = template_css
      .gsub("{{THEME_VARS}}", dark_theme_vars)
      .gsub("{{BODY_BG}}", "#18181e")
      .gsub("{{CONTAINER_BG}}", "#1e1e24")
      .gsub("{{INFO_BG}}", "#3c3728")

    session_data_base64 = Base64.strict_encode64(JSON.generate(session_data))

    template_erb = template_html
      .gsub("{{CSS}}", "<%= css %>")
      .gsub("{{JS}}", "<%= js %>")
      .gsub("{{SESSION_DATA}}", "<%= session_data_base64 %>")
      .gsub("{{MARKED_JS}}", "<%= marked_js %>")
      .gsub("{{HIGHLIGHT_JS}}", "<%= highlight_js %>")

    ERB.new(template_erb).result_with_hash(
      css: css,
      js: template_js,
      session_data_base64: session_data_base64,
      marked_js: marked_js,
      highlight_js: highlight_js
    )
  end

  def customize_template_js(js)
    js.gsub(
      "        const tokenParts = [];\n        if (globalStats.tokens.input) tokenParts.push(`↑${formatTokens(globalStats.tokens.input)}`);\n        if (globalStats.tokens.output) tokenParts.push(`↓${formatTokens(globalStats.tokens.output)}`);\n        if (globalStats.tokens.cacheRead) tokenParts.push(`R${formatTokens(globalStats.tokens.cacheRead)}`);\n        if (globalStats.tokens.cacheWrite) tokenParts.push(`W${formatTokens(globalStats.tokens.cacheWrite)}`);\n",
      "        const tokenParts = [];\n        if (globalStats.tokens.input || globalStats.tokens.cacheRead || globalStats.tokens.cacheWrite) {\n          const inMain = formatTokens(globalStats.tokens.input || 0);\n          const cacheRead = formatTokens(globalStats.tokens.cacheRead || 0);\n          const cacheWrite = formatTokens(globalStats.tokens.cacheWrite || 0);\n          tokenParts.push(`↑${inMain} (R${cacheRead} W${cacheWrite})`);\n        }\n        if (globalStats.tokens.output) tokenParts.push(`↓${formatTokens(globalStats.tokens.output)}`);\n"
    )
  end

  def dark_theme_vars
    theme = JSON.parse(read_file(File.join(@pi_root, PI_DARK_THEME)), symbolize_names: true)
    vars = theme[:vars]
    colors = theme[:colors]

    lines = colors.map do |key, value|
      resolved = if value.nil? || value == ""
        "#e5e5e7"
      elsif vars.key?(value.to_sym)
        vars[value.to_sym]
      else
        value
      end
      "--#{key}: #{resolved};"
    end

    lines.join("\n      ")
  end

  def read_pi_file(relative_path)
    read_file(File.join(@pi_root, PI_EXPORT_DIR, relative_path))
  end

  def read_file(path)
    File.read(path)
  end
end
