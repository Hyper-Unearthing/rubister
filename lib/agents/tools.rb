# frozen_string_literal: true

Dir[File.join(__dir__, '..', '..', 'modes', '*_writer.rb')].sort.each { |path| require path }
Dir[File.join(__dir__, 'tools', '*.rb')].sort.each { |path| require path }
