# rb-foundation-model-mac-agent

Local-only coding agent CLI for macOS. Backed by on-device LLMs — Apple Foundation Models (Apple Intelligence) or Ollama — with built-in filesystem tools and MCP server extensibility. No network calls, no API keys, no rate limits.

## Requirements

- **macOS 26+ (Tahoe)** with Apple Silicon (only for the `apple-fm` engine)
- **Apple Intelligence enabled** and the on-device model fully downloaded (Settings → Apple Intelligence & Siri)
- **Ruby 4.0+**
- **Swift 6.3+** if you build `rb-foundation-model-mac` from source (recommended installer: [`swiftly`](https://www.swift.org/install/macos/))
- **Optional**: Ollama running locally at `http://localhost:11434` for the `ollama` engine

## Installation

In your `Gemfile`:

```ruby
gem "rb-foundation-model-mac-agent"
```

```bash
bundle install
```

This pulls in the native Swift bridge (`rb-foundation-model-mac`) and bilingual helpers (`rb-natural-language-mac`, `rb-translation-mac`). The Swift extension is built at install time via `swift build`.

## Quickstart

Start the REPL in any project directory:

```bash
bundle exec rb-foundation-model-mac-agent          # default agent: yamabiko (scripted, no LLM needed)
bundle exec rb-foundation-model-mac-agent ruby-coder
```

On first start, a `.rb-foundation-model-mac-agent/` directory is created in the cwd to hold project-local agent defs and MCP server config.

Example session with the `ruby-coder` agent (Apple FM):

```
> Read ./sample.rb and tell me what class it defines.
[assistant] I will read the file.
```tool_call
name: fs.read
args:
  path: ./sample.rb
```
[tool_result]
name: fs.read
ok: true
content: |
  class Greeter
    def initialize(name)
      ...
[assistant] It defines a class called `Greeter` with an `initialize` taking a `name` and a `hello` method that returns "Hello, <name>!".
```

## Agents

An agent is a Markdown file with YAML frontmatter and a free-form body that becomes the system prompt. The gem ships with two built-in agents in `agents/`; you can override or add new ones in `.rb-foundation-model-mac-agent/agents/` (project-local definitions win on name collision).

```markdown
---
name: ruby-coder
engine: apple-fm           # apple-fm | ollama | scripted
model: default             # ollama only; ignored by apple-fm
fs_root: .                 # workspace root for fs.* tools
allowed_builtin:
  - fs.read
  - fs.write
allowed_mcp: []            # whitelist of MCP server names
max_iters: 8               # tool-call loop budget per user turn
preprocess_input: ja-en-roundtrip  # optional, see Bilingual support
---

CRuby 4.x coding assistant. Read files with `fs.read` when needed. Keep replies concise.
```

Ship list:
- `yamabiko` — scripted echo demo, no LLM required (useful for smoke-testing TUI)
- `ruby-coder` — Apple FM Ruby coding assistant with `fs.read`/`fs.write` and ja↔en roundtrip

List discovered agents at runtime with `/agents`.

## Tools

### Built-in: filesystem

- `fs.read` (args: `path:`) — read a file within `fs_root`
- `fs.write` (args: `path:`, `content:`) — write a file within `fs_root`

Paths can be relative (resolved to `fs_root`) or absolute (must still fall inside `fs_root`).

### MCP servers

Register MCP servers in `.rb-foundation-model-mac-agent/mcp.json` or at runtime via slash commands:

```
/mcp list
/mcp add my-server stdio:/path/to/server
/mcp remove my-server
```

Tools from a registered server are addressable as `<server>.<tool>` once the server name is whitelisted in the agent's `allowed_mcp`.

## Slash commands

Inside the REPL:

- `/agents` — list available agents (gem + project-local)
- `/tools` — list tools the current agent can call
- `/mcp list|add NAME SOURCE|remove NAME` — manage MCP servers
- `/reset` — clear conversation history (engine is also reset)
- `/dump` — dump current `@messages` as YAML
- `/quit` — exit

## Engines

### `apple-fm` (default for `ruby-coder`)

- Backed by `rb-foundation-model-mac` → Apple FoundationModels framework
- ~3B parameters, 4096-token context window
- **Self-healing**: on `exceededContextWindowSize` the engine compacts history (`ContextCompactor`) and retries up to 2 times before propagating the error
- **Cancel-on-fence**: the stream is cancelled after the first complete fenced block (any language tag) to prevent run-away concatenation seen with small models
- **Tool-call parsing is permissive**: a fenced block with a YAML `name: <ns>.<tool>` payload is accepted regardless of fence language (Apple FM frequently emits `` ```ruby `` instead of `` ```tool_call ``)

### `ollama`

- HTTP client for a local Ollama server (`OLLAMA_HOST` env, default `http://localhost:11434`)
- No self-healing — assumes the model's context window is large enough; pick an appropriate model in the agent frontmatter

### `scripted`

- Deterministic echo engine for smoke tests / demos
- Configured via the agent's frontmatter `scripted_replies` array

## Bilingual support (ja↔en)

Set `preprocess_input: ja-en-roundtrip` in the agent frontmatter to enable a Japanese-friendly turn:

1. `NaturalLanguage` detects the input language
2. If `ja`, code fences and backtick spans are masked, then `Translation` (Apple) translates ja → en
3. The translated prompt goes to the LLM
4. The final assistant text is translated en → ja before display (intermediate tool calls stay in English to keep parsing clean)

Failures (model not downloaded, unsupported pair) fall back to raw input with a warning — the agent still works, just without translation.

## Known limitations

- **Apple FM format compliance** is shaky at ~3B params; the parser tolerates `` ```ruby ``-flavored fences but the model still occasionally emits malformed YAML or paraphrases the schema. When that happens the turn is treated as a final answer.
- **4096-token context** is small. Long conversations or large files will trigger the self-healing compaction path; the gem prefers correctness (compact + retry) over speed.
- **Translation framework** downloads its language pack on first use — the OS may show a system dialog. Pre-download via the System Settings → Language & Region → Translation Languages screen for unattended runs.
- **Ollama backend has no self-healing**; you are responsible for picking a model whose context fits the conversation.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Apple Intelligence unavailable: ...` | Settings → Apple Intelligence & Siri → enable, wait for model download |
| `exceededContextWindowSize` shown twice | engine retried compaction twice and gave up; `/reset` clears history |
| Translation falls back silently | `defaults read com.apple.translation` to verify language packs, or run an interactive Translation usage once to trigger download |
| MCP server `bad: Failed to spawn` | check `source` path in `.rb-foundation-model-mac-agent/mcp.json`, server must be executable |
| `Library not loaded: ...FoundationModels.framework` | macOS < 26 — this gem requires Tahoe |

## Development

```bash
bundle install
bundle exec rake test                       # full suite (~80 tests)
bundle exec rake acceptance:l1              # Apple FM, single turn, stdout trace (HITL review)
bundle exec rake acceptance:l2              # scripted yamabiko in tmux (HITL review)
bundle exec rake acceptance:l3              # Apple FM in tmux full TUI (HITL review)
bundle exec rake acceptance:l2_kill         # tear down L2 tmux session
bundle exec rake acceptance:l3_kill         # tear down L3 tmux session
```

L1/L2/L3 sessions write logs under `/tmp/agent-acceptance/`. Attach with `tmux attach -t acceptance-l3` etc.

## License

MIT
