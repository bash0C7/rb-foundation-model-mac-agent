# frozen_string_literal: true

require_relative "test_helper"

class TestAppleFmEngine < Test::Unit::TestCase
  def setup
    @session = RbFoundationModelMacAgent::AppleFmEngine.new(system_prompt: "You answer in one word.")
  rescue AppleFoundationModel::UnavailableError => e
    omit "Apple Intelligence not available: #{e.message}"
  end

  def teardown
    @session&.close
  end

  def test_stream_yields_chunks_from_apple_fm
    out = +""
    @session.stream([{ role: "user", content: "Say hello." }]) { |c| out << c }
    assert_false(out.empty?)
  end
end
