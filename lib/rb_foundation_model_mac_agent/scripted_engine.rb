# frozen_string_literal: true

module RbFoundationModelMacAgent
  class ScriptedEngine
    def initialize(replies:, **)
      @replies = replies.dup
      @index = 0
    end

    def stream(messages, &block)
      raise "ScriptedEngine: out of scripted replies" if @index >= @replies.size
      text = @replies[@index].gsub("{input}", messages.last.fetch(:content))
      @index += 1
      block.call(text)
    end

    def reset
      @index = 0
    end

    def close
    end
  end
end
