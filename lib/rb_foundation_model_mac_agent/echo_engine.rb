# frozen_string_literal: true

module RbFoundationModelMacAgent
  class EchoEngine
    def initialize(**); end

    def stream(messages, &block)
      block.call(messages.last.fetch(:content))
    end

    def close; end
  end
end
