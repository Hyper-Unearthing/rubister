require_relative '../tools'

class Prompt < LlmGateway::Prompt
  TOOL_CLASSES = ObjectSpace.each_object(Class)
    .select { |klass| klass < LlmGateway::Tool }
    .sort_by(&:name)
    .freeze

  BASE_ARCHITECTURE_PATH = File.join(__dir__, '..', 'docs', 'base-architecture.md')
  FEATURES_BUILT_PATH = File.join(__dir__, '..', 'instance', 'features-built.md')
  SOUL_PATH = File.join(__dir__, '..', 'instance', 'soul.md')
  LEARNT_BEHAVIOURS_PATH = File.join(__dir__, '..', 'instance', 'learnt-behaviours.md')
  SYSTEM_PROMPT_PATH = File.join(__dir__, '..', 'docs', 'system-prompt.md')

  RUNTIME_PROMPT_DEFAULTS = {
    FEATURES_BUILT_PATH => <<~TEXT,
      # Features Built

      Tracks features gruv has built for itself.

      ## Entries
      - (none yet)
    TEXT
    SOUL_PATH => <<~TEXT,
      # Soul

      Persistent identity, intent, and core principles for gruv.

      ## Current
      - Help the user effectively.
      - Improve over time.
    TEXT
    LEARNT_BEHAVIOURS_PATH => <<~TEXT
      # Learnt Behaviours

      Behaviours gruv has learnt from interaction with the user.

      ## Current
      - (none yet)
    TEXT
  }.freeze

  def initialize(transcript, client)
    super(client.client.model_key)
    @transcript = transcript
    @client = client
  end

  def prompt
    cloned_history = Marshal.load(Marshal.dump(@transcript))
    if (last_content = cloned_history.last&.dig(:content)) && last_content.is_a?(Array) && last_content.last
      last_content.last[:cache_control] = { type: 'ephemeral' }
    end
    cloned_history.map { |h| deep_symbolize_keys(h) }
  end

  def system_prompt
    ensure_runtime_prompt_docs!

    content = [
      File.read(BASE_ARCHITECTURE_PATH),
      File.read(FEATURES_BUILT_PATH),
      File.read(SOUL_PATH),
      File.read(LEARNT_BEHAVIOURS_PATH),
      File.read(SYSTEM_PROMPT_PATH)
    ].join("\n\n")

    [{ role: 'system', content: content, cache_control: { 'type': 'ephemeral' } }]
  end

  def self.tools
    TOOL_CLASSES
  end

  def tools
    self.class.tools.map(&:definition)
  end

  def post(&block)
    @client.chat(
      prompt,
      tools: tools,
      system: system_prompt,
      &block
    )
  end

  private

  def ensure_runtime_prompt_docs!
    RUNTIME_PROMPT_DEFAULTS.each do |path, default_content|
      next if File.exist?(path)

      File.write(path, default_content)
    end
  end

  def deep_symbolize_keys(obj)
    case obj
    when Hash
      obj.each_with_object({}) { |(k, v), h| h[k.to_sym] = deep_symbolize_keys(v) }
    when Array
      obj.map { |e| deep_symbolize_keys(e) }
    else
      obj
    end
  end
end
