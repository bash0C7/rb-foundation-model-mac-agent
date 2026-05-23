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

山彦エージェント。scripted_replies に従って自律 loop demo を行う LLM 不要の
決定論的 agent。echo 単純動作 (1 reply 列で {input} 展開) は ScriptedEngine の
unit test で確認しています。
