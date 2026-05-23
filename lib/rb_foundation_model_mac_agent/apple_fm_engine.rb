# frozen_string_literal: true

require "foundation_model_mac"

module RbFoundationModelMacAgent
  class AppleFmEngine
    def initialize(system_prompt:, **)
      @system_prompt = system_prompt
      @session = new_session
    end

    def stream(messages, &block)
      @session.stream_response(to: messages.last.fetch(:content), &block)
    end

    def reset
      @session&.close
      @session = new_session
    end

    def close
      @session&.close
    end

    private

    def new_session
      AppleFoundationModel::Session.new(instructions: @system_prompt)
    end
  end
end
