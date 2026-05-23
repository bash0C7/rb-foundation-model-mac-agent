# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/test_*.rb"]
  t.warning = false
end

task default: :test

module AcceptancePaths
  WORK = "/tmp/agent-acceptance"
  REPO = __dir__
end

namespace :acceptance do
  def apple_fm_available?
    require "foundation_model_mac"
    s = AppleFoundationModel::Session.new(instructions: "")
    s.close if s.respond_to?(:close)
    true
  rescue StandardError => e
    warn "[acceptance] Apple FM probe failed: #{e.class}: #{e.message}"
    false
  end

  desc "L1 — ruby-coder + Apple FM, Session direct, stdout trace"
  task :l1 do
    abort "Apple FM not available on this machine" unless apple_fm_available?

    require_relative "lib/rb_foundation_model_mac_agent"
    require_relative "acceptance/trace_display"
    require "fileutils"

    FileUtils.mkdir_p(AcceptancePaths::WORK)
    FileUtils.rm_rf("#{AcceptancePaths::WORK}/.rb-foundation-model-mac-agent")
    FileUtils.cp("#{AcceptancePaths::REPO}/acceptance/fixtures/sample.rb", "#{AcceptancePaths::WORK}/sample.rb")

    agent_def = RbFoundationModelMacAgent::AgentDef.load(
      "ruby-coder",
      gem_agents_dir: "#{AcceptancePaths::REPO}/agents", project_agents_dir: nil,
    ).merge(fs_root: AcceptancePaths::WORK)
    registry = RbFoundationModelMacAgent::McpRegistry.new(
      config_path: "#{AcceptancePaths::WORK}/.rb-foundation-model-mac-agent/mcp.json",
    )
    session = RbFoundationModelMacAgent::Session.new(
      agent_def: agent_def, mcp_registry: registry,
    )

    puts "━━━ L1 Agent Acceptance ━━━"
    puts "agent: #{agent_def[:name]} (engine: #{agent_def[:engine]})"
    puts "fs_root: #{AcceptancePaths::WORK}"
    prompt = "Read ./sample.rb and tell me what class it defines."
    puts "prompt: #{prompt.inspect}"
    puts

    session.turn(prompt, display: TraceDisplay.new($stdout))
    puts
    puts "━━━ end ━━━"
  ensure
    session&.close
    registry&.close_all
  end

  desc "L2 — yamabiko loop demo via exe + screen"
  task :l2 do
    session_name = "acceptance-l2"
    require "fileutils"
    FileUtils.mkdir_p(AcceptancePaths::WORK)
    FileUtils.rm_rf("#{AcceptancePaths::WORK}/.rb-foundation-model-mac-agent")
    FileUtils.cp("#{AcceptancePaths::REPO}/acceptance/fixtures/sample.rb", "#{AcceptancePaths::WORK}/sample.rb")
    sh "screen -X -S #{session_name} quit 2>/dev/null || true"

    sh <<~CMD
      screen -dmS #{session_name} bash -c "
        cd '#{AcceptancePaths::WORK}'
        export RBENV_VERSION=4.0.3
        export BUNDLE_GEMFILE='#{AcceptancePaths::REPO}/Gemfile'
        exec bundle exec '#{AcceptancePaths::REPO}/exe/rb-foundation-model-mac-agent' yamabiko 2>&1 | tee '#{AcceptancePaths::WORK}/l2.log'
      "
    CMD
    sleep 2

    [
      ["please demo loop\r", 3],
      ["/tools\r", 1],
      ["/dump\r", 1],
      ["/reset\r", 1],
      ["please demo loop again\r", 3],
    ].each do |keys, wait|
      sh %Q{screen -S #{session_name} -X stuff #{keys.inspect}}
      sleep wait
    end

    puts <<~MSG

      ━━━ L2 TUI Acceptance — driver done ━━━
      Inspect: screen -r #{session_name}
      Log:     tail -f #{AcceptancePaths::WORK}/l2.log
      Cleanup: rake acceptance:l2_kill
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    MSG
  end

  desc "Kill acceptance:l2 screen session"
  task :l2_kill do
    sh "screen -X -S acceptance-l2 quit || true"
  end

  desc "L3 — ruby-coder + Apple FM via exe + screen"
  task :l3 do
    abort "Apple FM not available on this machine" unless apple_fm_available?

    session_name = "acceptance-l3"
    require "fileutils"
    FileUtils.mkdir_p(AcceptancePaths::WORK)
    FileUtils.rm_rf("#{AcceptancePaths::WORK}/.rb-foundation-model-mac-agent")
    FileUtils.cp("#{AcceptancePaths::REPO}/acceptance/fixtures/sample.rb", "#{AcceptancePaths::WORK}/sample.rb")
    sh "screen -X -S #{session_name} quit 2>/dev/null || true"

    sh <<~CMD
      screen -dmS #{session_name} bash -c "
        cd '#{AcceptancePaths::WORK}'
        export RBENV_VERSION=4.0.3
        export BUNDLE_GEMFILE='#{AcceptancePaths::REPO}/Gemfile'
        exec bundle exec '#{AcceptancePaths::REPO}/exe/rb-foundation-model-mac-agent' ruby-coder 2>&1 | tee '#{AcceptancePaths::WORK}/l3.log'
      "
    CMD
    sleep 2

    prompt = "Read ./sample.rb and tell me what class it defines.\r"
    sh %Q{screen -S #{session_name} -X stuff #{prompt.inspect}}

    puts <<~MSG

      ━━━ L3 E2E Acceptance — driver done ━━━
      Apple FM inference is slow (~10-30s per iter, max_iters=8).
      Attach:  screen -r #{session_name}
      Log:     tail -f #{AcceptancePaths::WORK}/l3.log
      Cleanup: rake acceptance:l3_kill
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    MSG
  end

  desc "Kill acceptance:l3 screen session"
  task :l3_kill do
    sh "screen -X -S acceptance-l3 quit || true"
  end
end
