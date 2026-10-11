# Agent Engineering Kit

Engineering guidelines for Codex: short everyday instructions and focused skills for data safety, code changes, and user interfaces.

## Get started

1. Open [personal/AGENTS.md](personal/AGENTS.md) and adapt the guidelines to your workflow. Save them in `AGENTS.md` under `CODEX_HOME` (default: `~/.codex`). If you already have global instructions, back them up and merge the relevant guidelines. Check for an `AGENTS.override.md` file, which takes precedence.
2. Copy the skill folders you need from `.agents/skills/` to `~/.agents/skills/` for use across projects, or to a project's `.agents/skills/` for that project only. Compare existing folders before copying; keep one copy of each skill in locations visible to Codex.
3. Use [examples/project/AGENTS.md](examples/project/AGENTS.md) for a project's purpose, run and check commands, constraints, and links to relevant decisions. Keep existing project instructions.
4. Start a new Codex session. Check the skill selector for the names below; CLI and IDE users can also use `/skills`. If a skill is missing, check its location and whether it is disabled.

The instructions are written in Russian. Adapt them to your language and project. No installation scripts or extra tools are required.

## Choose a skill

| Skill | Use it for |
| --- | --- |
| [aek-data-safety](.agents/skills/aek-data-safety/SKILL.md) | Storage, import/export, migrations, sync, retries, and recovery. |
| [aek-change-safety](.agents/skills/aek-change-safety/SKILL.md) | Module boundaries, public contracts, behavior replacement or removal, and recurring defects. |
| [aek-user-interface](.agents/skills/aek-user-interface/SKILL.md) | New or substantial GUI changes, user flows, action states, and layout. |

Codex reads global and project `AGENTS.md` instructions at the start of a session. It first sees skill names and descriptions, then reads a skill's full instructions when it selects that skill. A link alone does not load a file. Automatic skill selection is not guaranteed: select a skill in the app or name it explicitly, for example `$aek-data-safety Change the export format`. Skills keep project-specific formats and decisions in the project; they do not replace them. See the official [AGENTS.md guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md) and [skills guide](https://learn.chatgpt.com/docs/build-skills).

For projects using an earlier version of Kit, see [MIGRATION.md](MIGRATION.md).

## Contributing

To check changes to this repository, use Python 3.10+ and Git:

```sh
python scripts/check.py
git diff --check
git status --short
```

The script checks instruction files, minimal skill headers, local Markdown links, and possible private paths. See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## License

[MIT](LICENSE).
