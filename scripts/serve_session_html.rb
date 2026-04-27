#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "sqlite3"
require "webrick"
require "cgi"
require "pathname"
require_relative "../lib/session_html_exporter"

options = {
  bind: "127.0.0.1",
  port: 9292,
  db_path: File.expand_path("../instance/gruv.sqlite3", __dir__),
  pi_root: DEFAULT_PI_ROOT,
  instance_dir: File.expand_path("../instance", __dir__)
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/serve_session_html.rb [options]"

  opts.on("--bind HOST", "Bind address (default: #{options[:bind]})") { |v| options[:bind] = v }
  opts.on("--port PORT", Integer, "Port (default: #{options[:port]})") { |v| options[:port] = v }
  opts.on("--db PATH", "Path to SQLite DB (default: #{options[:db_path]})") { |v| options[:db_path] = v }
  opts.on("--pi-root PATH", "Path to pi-mono repo (default: #{options[:pi_root]})") { |v| options[:pi_root] = v }
  opts.on("--instance-dir PATH", "Instance dir for clone sessions (default: #{options[:instance_dir]})") { |v| options[:instance_dir] = v }
end

parser.parse!

unless File.exist?(options[:db_path])
  abort "DB not found: #{options[:db_path]}"
end

exporter = SessionHtmlExporter.new(pi_root: options[:pi_root])
db = SQLite3::Database.new(options[:db_path])
db.results_as_hash = true

list_db_sessions_sql = <<~SQL
  SELECT
    session_id,
    session_start,
    COUNT(*) AS events,
    MIN(timestamp) AS first_event,
    MAX(timestamp) AS last_event
  FROM session_events
  GROUP BY session_id, session_start
  ORDER BY last_event DESC
SQL

load_events_sql = <<~SQL
  SELECT
    event_id,
    parent_id,
    timestamp,
    event_type,
    usage_json,
    data_json
  FROM session_events
  WHERE session_id = ?
  ORDER BY position ASC
SQL

latest_channel_labels_sql = <<~SQL
  SELECT
    channel_id,
    platform,
    sender_name,
    sender_username,
    timestamp
  FROM messages
  ORDER BY timestamp DESC
SQL

clone_tasks_sql = <<~SQL
  SELECT
    ct.id,
    ct.state,
    ct.session_id,
    ct.session_start,
    ct.session_path,
    ct.started_at,
    ct.completed_at,
    m.channel_id AS origin_channel_id,
    m.platform AS origin_platform
  FROM clone_tasks ct
  LEFT JOIN messages m ON m.id = ct.origin_inbox_message_id
  ORDER BY ct.created_at DESC
SQL

server = WEBrick::HTTPServer.new(
  BindAddress: options[:bind],
  Port: options[:port],
  AccessLog: []
)

server.mount_proc "/" do |req, res|
  session_id = req.query["session_id"]
  session_id = "#{session_id}" unless session_id.nil?

  session_path = req.query["session_path"]
  session_path = "#{session_path}" unless session_path.nil?

  if (session_id.nil? || session_id.empty?) && (session_path.nil? || session_path.empty?)
    source_name_by_channel_id = {}
    db.execute(latest_channel_labels_sql).each do |row|
      cid = row["channel_id"]
      next if source_name_by_channel_id.key?(cid)

      sender = row["sender_name"]
      sender = row["sender_username"] if sender.nil? || sender.empty?
      source_name_by_channel_id[cid] = sender.nil? || sender.empty? ? cid : sender
    end

    rows_data = []

    count_file_events = lambda do |path|
      return "-" unless File.exist?(path)

      count = 0
      File.foreach(path) do |line|
        next if line.strip.empty?

        begin
          row = JSON.parse(line, symbolize_names: true)
          if row.is_a?(Hash)
            count += 1 unless row[:type] == "session"
          else
            count += 1
          end
        rescue JSON::ParserError
          return "-"
        end
      end

      count.zero? ? "-" : count
    end

    db.execute(list_db_sessions_sql).each do |row|
      sid = row["session_id"]
      sstart = row["session_start"]
      source_name = source_name_by_channel_id[sid] || sid
      href = "/?session_id=#{CGI.escape(sid)}&session_start=#{CGI.escape(sstart)}"

      rows_data << {
        source: "db",
        source_name: source_name,
        session_id: sid,
        session_start: sstart,
        events: row["events"],
        first_event: row["first_event"],
        last_event: row["last_event"],
        href: href
      }
    end

    clone_rows = db.execute(clone_tasks_sql)
    clone_session_paths_seen = {}

    clone_rows.each do |row|
      path = row["session_path"]
      next if path.nil? || path.empty?
      next unless File.exist?(path)

      clone_session_paths_seen[path] = true

      href = "/?session_path=#{CGI.escape(path)}"

      rows_data << {
        source: "clone",
        source_name: "clone #{row['id']}",
        session_id: row["session_id"],
        session_start: row["session_start"],
        events: count_file_events.call(path),
        first_event: row["started_at"],
        last_event: row["completed_at"] || row["started_at"],
        href: href
      }
    end

    disk_session_glob = File.join(options[:instance_dir], "sessions", "*.jsonl")
    Dir.glob(disk_session_glob).sort.reverse.each do |path|
      next if clone_session_paths_seen[path]

      filename = File.basename(path, ".jsonl")
      session_start = filename[/\A(\d{8}_\d{6})/, 1]
      session_id = filename.sub(/\A\d{8}_\d{6}_/, "")
      source = session_id.start_with?("clone_task_") ? "clone" : "file"

      formatted_source_name = if session_start
        "#{session_start[0, 4]}-#{session_start[4, 2]}-#{session_start[6, 2]} #{session_start[9, 2]}:#{session_start[11, 2]}:#{session_start[13, 2]}"
      else
        filename
      end

      rows_data << {
        source: source,
        source_name: formatted_source_name,
        session_id: session_id,
        session_start: session_start,
        events: count_file_events.call(path),
        first_event: nil,
        last_event: nil,
        href: "/?session_path=#{CGI.escape(path)}"
      }
    end

    rows_data.sort_by! { |row| row[:last_event].to_s }
    rows_data.reverse!

    rows = rows_data.map do |row|
      "<tr data-session-id=\"#{CGI.escapeHTML(row[:session_id].to_s)}\" data-source=\"#{CGI.escapeHTML(row[:source])}\"><td>#{CGI.escapeHTML(row[:source_name].to_s)}</td><td><a href=\"#{row[:href]}\">#{CGI.escapeHTML(row[:session_id].to_s)}</a></td><td>#{CGI.escapeHTML(row[:source].to_s)}</td><td>#{CGI.escapeHTML(row[:session_start].to_s)}</td><td>#{CGI.escapeHTML(row[:events].to_s)}</td><td>#{CGI.escapeHTML(row[:first_event].to_s)}</td><td>#{CGI.escapeHTML(row[:last_event].to_s)}</td></tr>"
    end.join("\n")

    res["Content-Type"] = "text/html; charset=utf-8"
    res.body = <<~HTML
      <!doctype html>
      <html>
        <head>
          <meta charset="utf-8">
          <title>Sessions</title>
          <style>
            body { font-family: ui-sans-serif, system-ui; margin: 24px; }
            .controls { display: flex; flex-direction: column; gap: 8px; max-width: 540px; margin-bottom: 16px; }
            .control-row { display: flex; align-items: center; gap: 8px; }
            label { min-width: 100px; }
            input, select { flex: 1; padding: 6px 8px; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
            th { background: #f5f5f5; }
            .hidden { display: none; }
          </style>
        </head>
        <body>
          <h1>Available sessions</h1>
          <p>Search by session id. Clone transcripts from disk are unioned in this list.</p>

          <div class="controls">
            <div class="control-row">
              <label for="session-search">Search</label>
              <input id="session-search" type="text" placeholder="Search session_id..." />
            </div>
          </div>

          <table>
            <thead>
              <tr><th>source name</th><th>session_id</th><th>source</th><th>session_start</th><th>events</th><th>first_event</th><th>last_event</th></tr>
            </thead>
            <tbody id="sessions-body">
              #{rows}
            </tbody>
          </table>

          <script>
            const searchInput = document.getElementById('session-search');
            const allRows = Array.from(document.querySelectorAll('#sessions-body tr'));

            function applyFilters() {
              const query = searchInput.value.toLowerCase().trim();

              allRows.forEach((row) => {
                const sid = (row.dataset.sessionId || '').toLowerCase();
                const sessionMatch = query === '' || sid.includes(query);

                row.classList.toggle('hidden', !sessionMatch);
              });
            }

            searchInput.addEventListener('input', applyFilters);
          </script>
        </body>
      </html>
    HTML

    next
  end

  unless session_path.nil? || session_path.empty?
    safe_path = File.expand_path(session_path)
    sessions_root = File.expand_path(File.join(options[:instance_dir], "sessions"))

    unless safe_path.start_with?(sessions_root + File::SEPARATOR) || safe_path == sessions_root
      res.status = 400
      res["Content-Type"] = "text/plain; charset=utf-8"
      res.body = "session_path must be under #{sessions_root}\n"
      next
    end

    unless File.exist?(safe_path)
      res.status = 404
      res["Content-Type"] = "text/plain; charset=utf-8"
      res.body = "Session file not found: #{safe_path}\n"
      next
    end

    html = exporter.export_from_jsonl_file(safe_path)
    res["Content-Type"] = "text/html; charset=utf-8"
    res.body = html
    next
  end

  rows = db.execute(load_events_sql, [session_id])
  if rows.empty?
    res.status = 404
    res["Content-Type"] = "text/plain; charset=utf-8"
    res.body = "No events found for session_id=#{session_id.inspect}\n"
    next
  end

  raw_entries = rows.map do |row|
    {
      id: row["event_id"],
      parent_id: row["parent_id"],
      timestamp: row["timestamp"],
      type: row["event_type"],
      usage: row["usage_json"] ? JSON.parse(row["usage_json"], symbolize_names: true) : nil,
      data: JSON.parse(row["data_json"], symbolize_names: true)
    }
  end

  html = exporter.export_from_transcript(
    raw_entries,
    session_row: { id: session_id, timestamp: rows[0]["timestamp"] },
    fallback_session_id: session_id
  )

  res["Content-Type"] = "text/html; charset=utf-8"
  res.body = html
end

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }

puts "Serving session HTML on http://#{options[:bind]}:#{options[:port]}"
puts "Examples:"
puts "  http://#{options[:bind]}:#{options[:port]}/?session_id=1476516540672249947"
puts "  http://#{options[:bind]}:#{options[:port]}/?session_id=self_check"
puts "  http://#{options[:bind]}:#{options[:port]}/?session_path=#{CGI.escape(File.join(options[:instance_dir], 'sessions', '...clone_task....jsonl'))}"

server.start
