require_relative 'prompt'

class InteractivePrompt < Prompt
  def self.tools
    super.reject { |klass| klass.respond_to?(:platform_tool?) && klass.platform_tool? }
  end
end
