module BasicCompaction
  def compaction(adapter)
    result = CompactionPrompt.new(adapter, active_messages, last_summary: last_compaction_entry&.dig(:data, :summary)).post
    content_blocks, usage = extract_compaction_content_and_usage(result)

    text_parts = content_blocks.filter_map do |part|
      next unless part.type == 'text'

      part.text
    end

    summary = text_parts.join("\n").strip
    raise 'Compaction Error' if summary.empty?

    compaction_entry = {
      type: 'compaction',
      usage: usage,
      data: {
        summary: summary
      }
    }

    push_entry(compaction_entry)
    compaction_entry
  end

  private

  def extract_compaction_content_and_usage(result)
    [result.content, result.usage]
  end
end
