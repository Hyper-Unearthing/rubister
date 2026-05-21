require 'fileutils'

require_relative '../coding_agent/agent'

class BaseGruvAgent < CodingAgent
  FEATURES_BUILT_PATH = File.join(__dir__, '..', '..', 'instance', 'features-built.md')
  SOUL_PATH = File.join(__dir__, '..', '..', 'instance', 'soul.md')
  LEARNT_BEHAVIOURS_PATH = File.join(__dir__, '..', '..', 'instance', 'learnt-behaviours.md')

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

  TOOLS = (CodingAgent::TOOLS + [
    GetMeTool,
    SqlTool,
    TranscribeVoiceTool,
  ]).freeze

  def system_prompt
    ensure_runtime_prompt_docs!

    [
      File.read(FEATURES_BUILT_PATH),
      File.read(SOUL_PATH),
      File.read(LEARNT_BEHAVIOURS_PATH),
      File.read(self.class::SYSTEM_PROMPT_PATH)
    ].join("\n\n")
  end

  def ensure_runtime_prompt_docs!
    RUNTIME_PROMPT_DEFAULTS.each do |path, default_content|
      next if File.exist?(path)

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, default_content)
    end
  end
end
