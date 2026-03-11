module BasicCompaction
  def compaction(adapter, messages_to_keep: 2)
    entries_to_summarise = compaction_source_messages
    return nil if entries_to_summarise.empty?

    result = CompactionPrompt.new(adapter, entries_to_summarise, last_summary: last_summary).post
    text_parts = result[:choices]&.dig(0, :content).select { |part| part[:type] == 'text' }
    summary = text_parts[0][:text]
    raise 'Compaction Error' if summary.empty?

    compaction_entry = {
      type: 'compaction',
      usage: result[:usage],
      data: {
        summary: summary,
        first_kept_entry_id: first_kept_entry[:id]
      }
    }

    push_entry(compaction_entry)
    compaction_entry
  end
end
