# frozen_string_literal: true

require "mcp"

server = MCP::Server.new(name: "fixture", version: "1.0.0")

server.define_tool(
  name: "echo",
  description: "Echoes the message back",
  input_schema: { properties: { message: { type: "string" } }, required: ["message"] },
) do |message:|
  MCP::Tool::Response.new([{ type: "text", text: "echo: #{message}" }])
end

server.define_tool(
  name: "fail",
  description: "Always reports a tool error",
  input_schema: { properties: {} },
) do
  MCP::Tool::Response.new([{ type: "text", text: "boom" }], error: true)
end

MCP::Server::Transports::StdioTransport.new(server).open
