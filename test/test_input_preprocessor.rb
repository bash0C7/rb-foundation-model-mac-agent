# frozen_string_literal: true

require_relative "test_helper"
require "rb_foundation_model_mac_agent/input_preprocessor"

class TestInputPreprocessor < Test::Unit::TestCase
  P = RbFoundationModelMacAgent::InputPreprocessor

  # --- mocks ---
  module FakeNL
    def self.detect_language(s)
      s.match?(/\p{Hiragana}|\p{Katakana}|\p{Han}/) ? "ja" : "en"
    end
  end

  module FakeTrans
    Result = Struct.new(:success, :text, :error)
    def self.translate(text, from:, to:)
      if from == "ja-JP" && to == "en-US"
        Result.new(true, "[translated:ja->en] #{text}", nil)
      elsif from == "en-US" && to == "ja-JP"
        Result.new(true, "[translated:en->ja] #{text}", nil)
      else
        Result.new(false, "", "unsupported")
      end
    end
  end

  def setup
    @pre = P.new(nl_module: FakeNL, translation_module: FakeTrans)
  end

  def test_english_input_passes_through
    result = @pre.preprocess("Read sample.rb")
    assert_equal("Read sample.rb", result[:text])
    assert_equal("en", result[:original_lang])
  end

  def test_japanese_input_translates_to_english
    result = @pre.preprocess("サンプルを読んで")
    assert_includes(result[:text], "[translated:ja->en]")
    assert_equal("ja", result[:original_lang])
  end

  def test_code_fence_is_masked_and_restored
    raw = "次のコードを実行して: ```ruby\nputs 1\n``` どうなる？"
    result = @pre.preprocess(raw)
    # masked code fence should appear in final text untouched
    assert_includes(result[:text], "```ruby\nputs 1\n```")
  end

  def test_inline_backtick_is_masked_and_restored
    raw = "`foo_bar` という変数の意味"
    result = @pre.preprocess(raw)
    assert_includes(result[:text], "`foo_bar`")
  end

  def test_postprocess_translates_back_when_lang_was_ja
    out = @pre.postprocess("Hello", original_lang: "ja")
    assert_includes(out, "[translated:en->ja]")
  end

  def test_postprocess_skips_when_lang_was_en
    out = @pre.postprocess("Hello", original_lang: "en")
    assert_equal("Hello", out)
  end

  def test_postprocess_preserves_code_fences
    text = "Here is code: ```ruby\nputs 1\n```"
    out = @pre.postprocess(text, original_lang: "ja")
    assert_includes(out, "```ruby\nputs 1\n```")
  end

  def test_translation_failure_falls_back_to_raw
    failing = Module.new do
      def self.translate(text, from:, to:)
        FakeTrans::Result.new(false, "", "model not installed")
      end
    end
    pre = P.new(nl_module: FakeNL, translation_module: failing)
    result = pre.preprocess("こんにちは")
    assert_equal("こんにちは", result[:text])
    # original_lang preserved so postprocess still decides correctly (but will also fail-fallback)
    assert_equal("ja", result[:original_lang])
  end

  def test_unknown_language_defaults_to_en_no_translation
    empty_nl = Module.new { def self.detect_language(_) ; "" ; end }
    pre = P.new(nl_module: empty_nl, translation_module: FakeTrans)
    result = pre.preprocess("???")
    assert_equal("???", result[:text])
    assert_equal("en", result[:original_lang])
  end
end
