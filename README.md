# rb-foundation-model-mac-agent

Local-only coding agent CLI for macOS. Backed by on-device LLMs — Apple Foundation Models (Apple Intelligence) or Ollama — with built-in filesystem tools and MCP server extensibility. No API keys, no rate limits.

## Requirements

- macOS 27+, Apple Silicon
- Apple Intelligence enabled with the on-device model downloaded (System Settings → Apple Intelligence & Siri), for the `apple-fm` engine
- Xcode 27 (the Swift binding gems build with `xcrun swift`)
- Ruby 4.0+, Bundler 4.x
- Optional: Ollama running locally, for the `ollama` engine

## Installation

The Gemfile resolves the binding gems and the shell framework from sibling checkouts. Clone them next to this repository:

```
<parent>/
├── rb-foundation-model-mac-agent/
├── rb-foundation-model-mac/
├── rb-natural-language-mac/
├── rb-translation-mac/
└── baslash/
```

```bash
for repo in rb-foundation-model-mac-agent rb-foundation-model-mac rb-natural-language-mac rb-translation-mac baslash; do
  git clone https://github.com/bash0C7/$repo.git
done
for repo in rb-foundation-model-mac rb-natural-language-mac rb-translation-mac; do
  (cd $repo && bundle install && bundle exec rake compile)
done
cd rb-foundation-model-mac-agent
bundle install
```

## Quickstart

Start the REPL in any project directory:

```bash
BUNDLE_GEMFILE=/path/to/rb-foundation-model-mac-agent/Gemfile \
  bundle exec /path/to/rb-foundation-model-mac-agent/exe/rb-foundation-model-mac-agent ruby-coder
```

Without an agent name the CLI starts `yamabiko`, a scripted demo that needs no LLM.

On start, a `.rb-foundation-model-mac-agent/` directory is created in the current directory to hold project-local agent definitions (`agents/`) and the MCP server config (`mcp.json`).

Example session with the `ruby-coder` agent:

````
> Read ./sample.rb and tell me what class it defines.
```tool_call
name: fs.read
args:
  path: ./sample.rb
```
```tool_result
name: fs.read
ok: true
content: |
  class Greeter
  ...
```
It defines a class called `Greeter` with an `initialize` taking a `name` and a `hello` method.
````

The REPL also reads lines from standard input:

```bash
printf 'Why is the sky blue?\n/exit\n' | bundle exec exe/rb-foundation-model-mac-agent ruby-coder
```

## Agents

An agent is a Markdown file with YAML frontmatter; the body becomes the system prompt. The gem ships the agents in `agents/`. Definitions in `.rb-foundation-model-mac-agent/agents/` add new agents and override shipped ones with the same name.

```markdown
---
name: ruby-coder
engine: apple-fm           # apple-fm | ollama | scripted
model: default             # ollama model name; ignored by apple-fm
fs_root: .                 # workspace root for fs.* tools
allowed_builtin:
  - fs.read
  - fs.write
allowed_mcp: []            # MCP server names the agent may call
max_iters: 8               # model calls per user turn
preprocess_input: ja-en-roundtrip  # optional, see Bilingual support
---

CRuby 4.x coding assistant. Read files with `fs.read` when needed. Keep replies concise.
```

Shipped agents:

- `yamabiko` — scripted demo of one `fs.read` loop, no LLM
- `ruby-coder` — Apple FM Ruby coding assistant with `fs.read`, `fs.write`, and ja↔en roundtrip

## Tools

A reply calls a tool with one fenced YAML block:

````
```tool_call
name: fs.read
args:
  path: ./sample.rb
```
````

The agent runs the tool and sends the result back as a `tool_result` block, then asks the model again, up to `max_iters` times per turn. A reply without a tool call ends the turn.

### Built-in: filesystem

- `fs.read` (args: `path`) — read a file within `fs_root`
- `fs.write` (args: `path`, `content`) — write a file within `fs_root`, creating parent directories

Paths are relative to `fs_root` or absolute. A path that resolves outside `fs_root`, including through a symlink, is rejected.

### MCP servers

Register MCP servers in `.rb-foundation-model-mac-agent/mcp.json` or at runtime:

```
/mcp list
/mcp add my-server /path/to/server-dir
/mcp add remote https://mcp.example.com/mcp
/mcp remove my-server
```

`/mcp add` classifies SOURCE:

- an `http://` or `https://` URL → Streamable HTTP transport
- a local directory → stdio transport, launched from `package.json` with `package-lock.json` (`node`), `pyproject.toml` (`uvx`), or a `Gemfile` with a gemspec that declares `spec.executables` (`bundle exec`)
- a git repository URL → rejected; clone it and add the local directory

`mcp.json` also accepts an explicit stdio command:

```json
{
  "servers": {
    "demo": { "kind": "stdio", "cmd": "ruby", "args": ["/path/to/server.rb"] }
  }
}
```

Tools from a server are addressable as `<server>.<tool>` once the server name is listed in the agent's `allowed_mcp`. The system prompt lists the tools of the servers connected when the session starts.

## Slash commands

- `/agents` — list available agents
- `/tools` — list the tools the current agent can call
- `/mcp list|add NAME SOURCE|remove NAME` — manage MCP servers
- `/reset` — clear the conversation history and the engine session
- `/dump` — show the conversation history as YAML
- `/help` — list slash commands
- `/exit`, `/q` — exit

Ctrl-C stops the reply in progress and returns to the prompt.

## Engines

### `apple-fm`

- Backed by `rb-foundation-model-mac` and the Apple Foundation Models framework. The on-device session keeps the transcript; each model call sends only the newest message.
- The stream stops after the first complete fenced block of any language tag, so the model emits at most one tool call per reply.
- The stream also stops once a reply exceeds `MAX_STREAM_BYTES`, which ends a fence that never closes.
- When a request exceeds the context window, the engine opens a new session, sends the history compacted by `ContextCompactor`, and retries up to `MAX_RETRIES` times with a smaller budget each time.

### `ollama`

- Calls the chat API of the Ollama server at `OLLAMA_HOST` (default `http://localhost:11434`) and sends the whole history on every call.
- Has no context compaction; choose a model whose context fits the conversation.

### `scripted`

- Replays the agent's `scripted_replies` in order; `{input}` in a reply is replaced with the last message.

## Bilingual support (ja↔en)

`preprocess_input: ja-en-roundtrip` handles Japanese input:

1. `NaturalLanguage` detects the input language.
2. For Japanese, code fences and backtick spans are masked and the text is translated to English with the Translation framework.
3. The English prompt goes to the model; tool calls stay in English.
4. The final reply is shown again translated to Japanese, with code restored unchanged.

When language detection or translation fails, the agent warns and uses the untranslated text. Translation uses only installed language models. Download the Japanese ↔ English pair once from the `rb-translation-mac` checkout:

```bash
bundle exec rake translation_mac:prepare_models
```

## Known limitations

- The on-device model does not always follow the tool-call format. It may emit malformed YAML, paraphrase the format, answer without calling a tool, or call a tool the request did not need. A reply without a parseable tool call ends the turn.
- After a tool result, the model sometimes ignores the result and answers from scratch. `/reset` and a more explicit request ("Use fs.read to open ./x.rb") help.
- A reply stopped by Ctrl-C, by the fence stop, or by `MAX_STREAM_BYTES` stays in the Apple FM session with all the text the model generated before it stopped. The next prompt sees it and the model may continue it. `/reset` starts a new session.
- The context window is small. Long conversations and large files go through compaction, which drops or truncates older content.
- The system prompt is built when the session starts; MCP servers added with `/mcp add` show their tools in the system prompt after a restart.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Apple Intelligence unavailable: ...` | Enable Apple Intelligence in System Settings → Apple Intelligence & Siri and wait for the model download |
| `error: AppleFoundationModel::GenerationError: Content contains ... tokens, which exceeds the maximum allowed context size ...` | Compaction did not fit the history; `/reset` |
| A reply ends right after a code block | The fence stop ended the reply; ask again for a plain-text answer |
| A reply ends abruptly in the middle of code | `MAX_STREAM_BYTES` ended a fence that did not close |
| `InputPreprocessor: translate ja-JP->en-US failed` | Run `bundle exec rake translation_mac:prepare_models` in the `rb-translation-mac` checkout |
| `[mcp] connect failed: NAME: Failed to spawn server process` | Check `cmd` or the directory in `mcp.json`; the server must be executable |

## Development

```bash
bundle install
bundle exec rake test                  # RBS validation and the test suite
bundle exec rake acceptance:l1         # ruby-coder on Apple FM, one turn traced to stdout
bundle exec rake acceptance:l2         # yamabiko CLI in tmux
bundle exec rake acceptance:l3         # ruby-coder CLI on Apple FM in tmux
bundle exec rake acceptance:l2_kill    # stop the L2 tmux session
bundle exec rake acceptance:l3_kill    # stop the L3 tmux session
```

Tests that call Apple Foundation Models are omitted when Apple Intelligence is unavailable. The acceptance tasks work in `/tmp/agent-acceptance/`; attach with `tmux attach -t acceptance-l3`.

`sig/rb_foundation_model_mac_agent.rbs` documents the Ruby API.

## License

MIT
