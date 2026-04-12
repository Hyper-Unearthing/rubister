require_relative '../tools'
require_relative 'agent'

class BaseGruvAgent < Agent
  FEATURES_BUILT_PATH = File.join(__dir__, '..', 'instance', 'features-built.md')
  SOUL_PATH = File.join(__dir__, '..', 'instance', 'soul.md')
  LEARNT_BEHAVIOURS_PATH = File.join(__dir__, '..', 'instance', 'learnt-behaviours.md')

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

  ALL_TOOLS = ObjectSpace.each_object(Class)
    .select { |klass| klass < LlmGateway::Tool }
    .sort_by(&:name)
    .freeze

  def system_prompt
    ensure_runtime_prompt_docs!

    content = [
      File.read(FEATURES_BUILT_PATH),
      File.read(SOUL_PATH),
      File.read(LEARNT_BEHAVIOURS_PATH),
      File.read(self.class::SYSTEM_PROMPT_PATH)
    ].join("\n\n")

    [{ role: 'system', content: content, cache_control: { 'type': 'ephemeral' } }]
  end

  def ensure_runtime_prompt_docs!
    RUNTIME_PROMPT_DEFAULTS.each do |path, default_content|
      next if File.exist?(path)

      File.write(path, default_content)
    end
  end
end
