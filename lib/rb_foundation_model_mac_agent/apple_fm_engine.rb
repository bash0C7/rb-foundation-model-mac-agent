# frozen_string_literal: true

require "foundation_model_mac"
require_relative "context_compactor"

module RbFoundationModelMacAgent
  class AppleFmEngine
    MAX_RETRIES = 2
    STOP_FENCE = "\n```\n"
    # Hard byte ceiling for one stream. Safety net for the "open fence never closes"
    # failure mode where Apple FM generates an endless body inside a single ```ruby
    # block without emitting the closing fence. ~4096 bytes ≈ 1365 rough tokens —
    # comfortably below the 4096-token context window so a single runaway turn
    # cannot push us into overflow on its own.
    MAX_STREAM_BYTES = 4096
    # Matches one complete fenced block of any language tag (```tool_call, ```ruby, ```python, ...).
    # Cancels generation after the first block so Apple FM cannot runaway-concatenate blocks.
    FENCE_BLOCK_RE = /```\w*\n.*?\n```/m

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
        next if cancelled
        if FENCE_BLOCK_RE.match?(buf) || buf.bytesize > MAX_STREAM_BYTES
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
