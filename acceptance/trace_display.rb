# frozen_string_literal: true

# Display duck-type implementer that writes the Session's loop activity
# to an IO (typically $stdout) with labeled iter headers. Used by the L1
# acceptance harness to surface autonomous loop progress for human review.
class TraceDisplay
  def initialize(io)
    @io = io
    @iter = 0
  end

  def append(text, style: nil)
    @io.puts "[iter #{@iter}] #{style || :assistant}:"
    indent(text)
    @io.puts
  end

  def dialog(content, style: nil)
    @io.puts "[iter #{@iter}] #{style || :dialog}:"
    indent(content)
    @io.puts
  end

  def open_live(style: nil)
    @iter += 1
    LiveSlot.new(self, style)
  end

  def indent(text)
    text.to_s.each_line { |line| @io.puts "  #{line.chomp}" }
  end

  class LiveSlot
    def initialize(parent, style)
      @parent = parent
      @style  = style
      @last   = nil
    end

    def update(text)
      @last = text
    end

    def commit(final = nil)
      @parent.append((final || @last).to_s, style: @style)
    end

    def discard
    end
  end
end
