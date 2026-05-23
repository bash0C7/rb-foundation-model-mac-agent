# frozen_string_literal: true

require "foundation_model_mac"

module RbFoundationModelMacAgent
  class AppleFmEngine
    def initialize(system_prompt:, **)
      @session = AppleFoundationModel::Session.new(instructions: system_prompt)
    end

    def stream(messages, &block)
      @session.stream_response(to: messages.last.fetch(:content), &block)
    end

    def close
      @session&.close
    end
  end
end
