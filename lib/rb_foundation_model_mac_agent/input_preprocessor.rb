# frozen_string_literal: true

module RbFoundationModelMacAgent
  class InputPreprocessor
    PLACEHOLDER_PREFIX = "__SAFE_"
    PLACEHOLDER_SUFFIX = "__"
    PLACEHOLDER_RE = /#{PLACEHOLDER_PREFIX}\d+#{PLACEHOLDER_SUFFIX}/

    def initialize(nl_module: nil, translation_module: nil)
      @nl = nl_module || default_nl
      @trans = translation_module || default_translation
    end

    def preprocess(text)
      lang = detect_language_safe(text)
      return { text: text, original_lang: "en" } if lang != "ja"

      masked, placeholders = mask(text)
      translated_result = translate_safe(masked, from: "ja-JP", to: "en-US")

      if translated_result[:ok]
        out = unmask(translated_result[:text], placeholders)
        { text: out, original_lang: "ja" }
      else
        # Silent fallback: preserve raw, but remember the lang so postprocess can still try
        { text: text, original_lang: "ja" }
      end
    end

    def postprocess(text, original_lang:)
      return text if original_lang != "ja"

      masked, placeholders = mask(text)
      translated_result = translate_safe(masked, from: "en-US", to: "ja-JP")
      if translated_result[:ok]
        unmask(translated_result[:text], placeholders)
      else
        text  # silent fallback
      end
    end

    # --- mask / unmask ---

    def mask(text)
      placeholders = []
      idx = 0
      # Triple-backtick code fences first (greedy multiline)
      masked = text.gsub(/```.*?```/m) do |m|
        ph = "#{PLACEHOLDER_PREFIX}#{idx}#{PLACEHOLDER_SUFFIX}"
        placeholders << [ph, m]
        idx += 1
        ph
      end
      # Then inline backtick spans
      masked = masked.gsub(/`[^`\n]+`/) do |m|
        ph = "#{PLACEHOLDER_PREFIX}#{idx}#{PLACEHOLDER_SUFFIX}"
        placeholders << [ph, m]
        idx += 1
        ph
      end
      [masked, placeholders]
    end

    def unmask(text, placeholders)
      out = text.dup
      placeholders.each do |ph, original|
        unless out.include?(ph)
          warn "InputPreprocessor: placeholder #{ph} mangled by translation, returning partial output"
          return out
        end
        out = out.sub(ph, original)
      end
      out
    end

    private

    def detect_language_safe(text)
      raw = @nl.detect_language(text)
      raw.to_s.empty? ? "en" : raw
    rescue StandardError => e
      warn "InputPreprocessor: detect_language failed (#{e.class}: #{e.message}); defaulting to en"
      "en"
    end

    def translate_safe(text, from:, to:)
      r = @trans.translate(text, from: from, to: to)
      if r.respond_to?(:success) && r.success
        { ok: true, text: r.text }
      else
        err = r.respond_to?(:error) ? r.error : "unknown"
        warn "InputPreprocessor: translate #{from}->#{to} failed: #{err}; raw fallback"
        { ok: false }
      end
    rescue StandardError => e
      warn "InputPreprocessor: translate #{from}->#{to} raised (#{e.class}: #{e.message}); raw fallback"
      { ok: false }
    end

    def default_nl
      require "natural_language_mac"
      NaturalLanguageMac
    end

    def default_translation
      require "translation_mac"
      TranslationMac
    end
  end
end
