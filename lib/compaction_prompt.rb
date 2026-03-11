require 'json'

class CompactionPrompt < LlmGateway::Prompt
  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are summarizing a long-running conversation between a user and an assistant.

    Update the summary using the transcript.

    For each topic include:
    1. Topic (top-level heading)
    2. What the user asked
    3. Actions you took
    4. Next actions to take

    Rules:
    - If a topic from the previous summary continues, merge the information.
    - If a topic from the previous summary is not continued, omit it.
    - Keep the summary concise and structured by topic.
  PROMPT

  def initialize(client, messages, last_summary: nil)
    super(client)
    @client = client
    @messages = messages
    @last_summary = last_summary
  end

  def prompt
    payload = JSON.pretty_generate(compaction_messages)
    summary_text = @last_summary || 'no previous summary'

    prompt_text = <<~TEXT
      Previous summary:
      <summary>
      #{summary_text}
      </summary>

      Current conversation transcript:
      <transcript>
      #{payload}
      </transcript>
    TEXT

    [
      {
        role: 'user',
        content: [
          {
            type: 'text',
            text: prompt_text
          }
        ]
      }
    ]
  end

  def system_prompt
    [{ role: 'system', content: SYSTEM_PROMPT }]
  end

  def post(&block)
    @client.chat(
      prompt,
      tools: [],
      system: system_prompt,
      &block
    )
  end

  private

  def compaction_messages
    @messages.map do |message|
      {
        role: message[:data][:role],
        content: normalize_content_blocks(message[:data][:content])
      }
    end
  end

  def normalize_content_blocks(content)
    content.map do |block|
      case block[:type]
      when 'thinking'
        { type: 'thinking', thinking: truncate_text(block[:thinking], 600) }
      when 'text'
        { type: 'text', text: truncate_text(block[:text], 2_000) }
      when 'tool_result'
        { type: 'tool_result', tool_use_id: block[:tool_use_id], content: truncate_text(block[:content], 4_000) }
      else
        block
      end
    end
  end

  def truncate_text(text, max_chars)
    return '' if text.nil?
    return text if text.length <= max_chars

    text[0, max_chars] + "\n...[truncated for compaction]"
  end
end
