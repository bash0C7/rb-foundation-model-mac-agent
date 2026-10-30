# frozen_string_literal: true

require "foundation_model_mac"
require_relative "context_compactor"

module RbFoundationModelMacAgent
  class AppleFmEngine
    MAX_RETRIES = 2
    COMPACTION_TARGET_TOKENS = 3500
    STOP_FENCE = "\n```\n"
    MAX_STREAM_BYTES = 4096
    FENCE_BLOCK_RE = /```\w*\n.*?\n```/m

    def initialize(system_prompt:, session_builder: nil, **)
      @system_prompt = system_prompt
      @session_builder = session_builder || ->(instr) { AppleFoundationModel::Session.new(instructions: instr) }
      @session = @session_builder.call(@system_prompt)
    end

    def stream(messages, &block)
      input = messages.last.fetch(:content)
      attempt = 0
      begin
        stream_once(input, &block)
      rescue AppleFoundationModel::GenerationError => e
        raise unless context_overflow?(e)
        attempt += 1
        raise if attempt > MAX_RETRIES
        input = compact_into_new_session(messages, COMPACTION_TARGET_TOKENS / attempt)
        retry
      end
    end

    def reset
      @session.close
      @session = @session_builder.call(@system_prompt)
    end

    def close
      @session.close
    end

    private

    def stream_once(input)
      buf = +""
      @session.stream_response(to: input, stop_at: [STOP_FENCE]) do |chunk|
        buf << chunk
        yield chunk if block_given?
        @session.cancel_stream if FENCE_BLOCK_RE.match?(buf) || buf.bytesize > MAX_STREAM_BYTES
      end
    end

    def context_overflow?(e)
      e.message.include?("exceeds the maximum allowed context")
    end

    def compact_into_new_session(messages, target_tokens)
      @session.close
      @session = @session_builder.call(@system_prompt)
      ContextCompactor.compact(messages, system_prompt_size: @system_prompt.length, target_tokens: target_tokens)
    end
  end
end
