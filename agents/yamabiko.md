---
name: yamabiko
engine: scripted
fs_root: .
allowed_builtin:
  - fs.read
scripted_replies:
  - "Let me check the demo file.\n```tool_call\nname: fs.read\nargs:\n  path: ./sample.rb\n```"
  - "I read it. The class defined is Greeter."
---

山彦エージェント。scripted_repliesに従って、fs.readを1回呼ぶ自律loopを再生する。LLMを使わない。
