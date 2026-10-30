# frozen_string_literal: true

module RbFoundationModelMacAgent
  class InputPreprocessor
    PLACEHOLDER_PREFIX = "Xxyzzyx"
    PLACEHOLDER_SUFFIX = "xzzyxX"

    def initialize(nl_module: nil, translation_module: nil)
      @nl = nl_module || default_nl
      @trans = translation_module || default_translation
    end

    def preprocess(text)
      lang = detect_language_safe(text)
      return { text: text, original_lang: "en" } if lang != "ja"

      masked, placeholders = mask(text)
      translated_result = translate_safe(masked, from: "ja-JP", to: "en-US")

      text = unmask(translated_result[:text], placeholders) if translated_result[:ok]
      { text: text, original_lang: "ja" }
    end

    def postprocess(text, original_lang:)
      return text if original_lang != "ja"

      masked, placeholders = mask(text)
      translated_result = translate_safe(masked, from: "en-US", to: "ja-JP")
      translated_result[:ok] ? unmask(translated_result[:text], placeholders) : text
    end

    def mask(text)
      placeholders = []
      masked = [/```.*?```/m, /`[^`\n]+`/].reduce(text) do |acc, re|
        acc.gsub(re) do |m|
          ph = "#{PLACEHOLDER_PREFIX}#{placeholders.size}#{PLACEHOLDER_SUFFIX}"
          placeholders << [ph, m]
          ph
        end
      end
      [masked, placeholders]
    end

    def unmask(text, placeholders)
      placeholders.reduce(text) do |out, (ph, original)|
        next out.sub(ph) { original } if out.include?(ph)
        warn "InputPreprocessor: placeholder #{ph} mangled by translation"
        out
      end
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
      return { ok: true, text: r.text } if r.success
      warn "InputPreprocessor: translate #{from}->#{to} failed: #{r.error}; raw fallback"
      { ok: false }
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
