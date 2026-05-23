# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RbFoundationModelMacAgent
  class OllamaEngine
    def initialize(model:, system_prompt:, host: ENV.fetch("OLLAMA_HOST", "http://localhost:11434"))
      @model = model
      @system_prompt = system_prompt
      @host  = host
    end

    def stream(messages, &block)
      uri = URI.join(@host, "/api/chat")
      payload = {
        model: @model,
        stream: true,
        messages: [{ role: "system", content: @system_prompt },
                   *messages.map { |m| { role: m[:role], content: m[:content] } }],
      }
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(payload)
        http.request(req) do |res|
          raise "ollama HTTP #{res.code}: #{res.body}" unless res.code.to_i == 200
          buffer = +""
          res.read_body do |bytes|
            buffer << bytes
            while (idx = buffer.index("\n"))
              line = buffer.slice!(0, idx + 1).chomp
              next if line.empty?
              obj = JSON.parse(line)
              chunk = obj.dig("message", "content")
              block.call(chunk) if chunk && !chunk.empty?
              break if obj["done"]
            end
          end
        end
      end
    end

    def close; end
  end
end
