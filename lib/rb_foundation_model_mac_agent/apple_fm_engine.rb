# frozen_string_literal: true

require "foundation_model_mac"
require_relative "tool_call"
require_relative "context_compactor"

module RbFoundationModelMacAgent
  class AppleFmEngine
    MAX_RETRIES = 2
    STOP_FENCE = "\n```\n"

    def initialize(system_prompt:, session_builder: nil, **)
      @system_prompt = system_prompt
      @session_builder = session_builder || ->(instr) { AppleFoundationModel::Session.new(instructions: instr) }
      @session = @session_builder.call(@system_prompt)
      @recovery_input = nil
    end

    def stream(messages, &block)
      attempt = 0
      begin
        do_stream(messages, &block)
      rescue AppleFoundationModel::GenerationError => e
        raise unless context_overflow?(e)
        attempt += 1
        raise if attempt > MAX_RETRIES
        rebuild_session_with_compaction!(messages)
        retry
      end
    end

    def reset
      @session&.close
      @session = @session_builder.call(@system_prompt)
      @recovery_input = nil
    end

    def close
      @session&.close
    end

    private

    def do_stream(messages, &block)
      input = @recovery_input || messages.last.fetch(:content)
      @recovery_input = nil
      buf = +""
      cancelled = false
      @session.stream_response(to: input, stop_at: [STOP_FENCE]) do |chunk|
        buf << chunk
        block.call(chunk) if block
        if !cancelled && ToolCall::FENCE_RE.match?(buf)
          @session.cancel_stream
          cancelled = true
        end
      end
      buf
    end

    def context_overflow?(e)
      msg = e.message.to_s
      msg.include?("exceededContextWindowSize") || msg.include?("exceeds the maximum allowed context")
    end

    def rebuild_session_with_compaction!(messages)
      @session&.close
      compacted = ContextCompactor.compact(
        messages,
        system_prompt_size: @system_prompt.length,
        target_tokens: 3500,
      )
      @session = @session_builder.call(@system_prompt)
      @recovery_input = compacted
    end
  end
end
