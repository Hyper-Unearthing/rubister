# frozen_string_literal: true

Dir[File.join(__dir__, '..', '..', 'modes', '*_writer.rb')].sort.each { |path| require path }
Dir[File.join(__dir__, 'tools', '*.rb')].sort.each { |path| require path }
Dir[File.join(__dir__, 'gruv', 'tools', '*.rb')].sort.each { |path| require path }
Dir[File.join(__dir__, 'coding_agent', 'tools', '*.rb')].sort.each { |path| require path }
Dir[File.join(__dir__, 'clone_agent', 'tools', '*.rb')].sort.each { |path| require path }
