# Agent Engineering Kit

Agent Engineering Kit gives AI coding agents a compact, versioned set of engineering rules for working in real repositories. It helps agents preserve task scope, use evidence, respect project boundaries, and choose checks that observe the intended result.

Connect the kit once, then keep working in your project as usual. The agent reads only the rules relevant to the current task.

## Install

You need Git and Windows PowerShell 5.1 or PowerShell 7.

```powershell
git clone https://github.com/Dmitryaf/agent-engineering-kit.git
Set-Location agent-engineering-kit
```

## Connect a project

Run this command from the hub folder and provide the path to your project:

```powershell
.\ai-rules.ps1 prompt connect -ProjectRoot C:\path\to\project
```

Copy the generated prompt into the AI agent working on that project. The agent will:

1. inspect the project;
2. select only the relevant rules;
3. show you the proposed changes;
4. wait for your approval;
5. connect the rules and verify the result.

Then return to your normal project work. You do not need to learn how the kit works or select rule files manually.

For a public project, select `public-repository`. The kit keeps three things separate:

```text
public repository       → code and documentation for external readers
local agent runtime     → AGENTS.md + .ai-rules/
Private Project Context → private, versioned internal documents and unique rules
```

Runtime files are excluded locally through Git's `info/exclude`; the public `.gitignore` is unchanged. A fresh clone can connect the kit again. Restore unique project rules from your chosen private source; ignored files alone are not a backup. Private repositories can keep the existing tracked model.

If internal files are already tracked, preview the transition and install local exclusions:

```powershell
.\ai-rules.ps1 local-only -ProjectRoot C:\path\to\project
.\ai-rules.ps1 local-only -ProjectRoot C:\path\to\project -Apply
```

These commands preserve the index, history and local files. They provide a separate instruction for untracking runtime files after saving unique rules and obtaining the owner's permission. Previously published files remain in old commits. See [private context and restoration](sync/README.md#публичный-проект-и-private-project-context) for setup and migration details.

For a new product, start with a small architecture before implementing its first scenario:

```powershell
.\ai-rules.ps1 prompt bootstrap -ProjectRoot C:\path\to\project
```

Paste the prompt with your goal and first scenario. The agent chooses where code belongs, creates only the needed parts, and checks the important dependency boundaries. Connecting an existing project does not restructure its code.

For substantial new UI or a visual redesign, ask the agent to choose a visual direction before implementation: product context, references, distinct options, then a short design contract. Small fixes and features within an established design system do not restart discovery; connecting the kit does not redesign existing projects.

For a deep project audit later, generate a dedicated prompt:

```powershell
.\ai-rules.ps1 prompt deep-audit -ProjectRoot C:\path\to\project
```

To learn how a project works through code walkthroughs and practical checks:

```powershell
.\ai-rules.ps1 prompt study -ProjectRoot C:\path\to\project
```

Study sessions track explored areas and demonstrated understanding separately. Significant decisions are maintained as a regular project practice, with a short, readable map of current choices and their reasons. Temporary audits, research and delivery evidence live separately and are reviewed when the work ends.

For a large task with independent parts, generate a prompt for Codex:

```powershell
.\ai-rules.ps1 prompt parallel -ProjectRoot C:\path\to\project
```

Paste the prompt and your task into Codex. It will assess whether parallel work helps, give each writer a bounded task and separate workspace, and assign one owner to integrate and verify the result. Ordinary tasks continue as before.

## Update rules

Preview the available changes:

```powershell
.\ai-rules.ps1 update -ProjectRoot C:\path\to\project
```

If they look correct, apply them:

```powershell
.\ai-rules.ps1 update -ProjectRoot C:\path\to\project -Apply
```

Initial `connect` and `init` create the local setup, including public-profile exclusions. Rule updates require `-Apply`; the kit preserves manually changed rules and does not run `commit`, `push`, or publishing commands.

## Kit development

The architecture and low-level commands are documented in [`hub/ARCHITECTURE.md`](hub/ARCHITECTURE.md) and [`sync/README.md`](sync/README.md). Contribution and security guidance is available in [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`.github/SECURITY.md`](.github/SECURITY.md).

[Visual Design Discovery](workflows/VISUAL_DESIGN_DISCOVERY.md) can be read directly from the hub or explicitly selected with `-Topics visual-design-discovery`.

The verified minimum environment is Git with Windows PowerShell 5.1. Automated checks also cover `pwsh` on Windows and, experimentally, on Ubuntu. Linux support is not yet declared.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/check-hub.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test-tooling.ps1
git diff --check
```
