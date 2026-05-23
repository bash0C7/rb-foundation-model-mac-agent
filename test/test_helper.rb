# frozen_string_literal: true

require "test/unit"
require "stringio"
require "rb_foundation_model_mac_agent"

# Drives Session in tests by yielding a pre-canned sequence of assistant
# strings (one per Session#turn iteration). Captures every messages array
# it was called with so tests can assert ReAct history shaping.
class SpyScriptedEngine < RbFoundationModelMacAgent::ScriptedEngine
  attr_reader :calls, :reset_count

  def initialize(replies)
    super(replies: replies)
    @calls = []
    @reset_count = 0
  end

  def stream(messages, &block)
    @calls << messages.map { |m| m.dup }
    super
  end

  def reset
    @reset_count += 1
    super
  end
end

# Backwards-compat alias for any test still saying `ScriptedEngine.new(...)`.
ScriptedEngine = SpyScriptedEngine

# Capture-only stand-in for the baslash display surface.
class FakeDisplay
  attr_reader :appended, :dialogs

  def initialize
    @appended = []
    @dialogs  = []
  end

  def append(text, style: nil)
    @appended << [text, style]
  end

  def dialog(content, style: nil)
    @dialogs << [content, style]
  end

  def open_live(style: nil)
    slot = LiveSlot.new(self, style)
    if block_given?
      yield slot
      slot.commit unless slot.committed?
    end
    slot
  end

  class LiveSlot
    attr_reader :updates, :last, :style

    def initialize(parent, style)
      @parent    = parent
      @style     = style
      @updates   = []
      @last      = nil
      @committed = false
    end

    def update(text); @updates << text; @last = text; end
    def commit(final = nil); @parent.appended << [(final || @last).to_s, @style]; @committed = true; end
    def discard; @committed = true; end
    def committed?; @committed; end
  end
end
