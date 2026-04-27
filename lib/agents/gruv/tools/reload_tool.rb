# frozen_string_literal: true

class ReloadTool < LlmGateway::Tool
  name 'reload'
  description 'Reload all supervisor-managed services by sending SIGHUP to the supervisor process.'
  input_schema({
    type: 'object',
    properties: {},
    required: []
  })

  def execute(_input)
    supervisor_pid = ENV['GRUV_SUPERVISOR_PID']
    return 'Reload is only available in daemon worker mode.' unless supervisor_pid

    Process.kill('HUP', supervisor_pid.to_i)
    'Reload requested. I sent SIGHUP to the supervisor to restart all managed services.'
  rescue Errno::ESRCH
    'I tried to reload, but the supervisor process was not found.'
  rescue => e
    "I tried to reload, but got an error: #{e.message}"
  end
end
