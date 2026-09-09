# AI Rules Hub

AI Rules Hub adds ready-to-use rules for AI coding agents to your project. Once connected, keep working in your project as usual. The agent will find and read the relevant rules automatically.

## Install

You need Git and Windows PowerShell 5.1 or PowerShell 7.

```powershell
git clone https://github.com/Dmitryaf/ai-rules-hub.git
Set-Location ai-rules-hub
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

Then return to your normal project work. You do not need to learn how the hub works or select rule files manually.

## Update rules

Preview the available changes:

```powershell
.\ai-rules.ps1 update -ProjectRoot C:\path\to\project
```

If they look correct, apply them:

```powershell
.\ai-rules.ps1 update -ProjectRoot C:\path\to\project -Apply
```

The hub does not change your project without `-Apply`, overwrite rule files you changed manually, or run `commit`, `push`, or publishing commands.

## Hub development

The architecture and low-level commands are documented in [`hub/ARCHITECTURE.md`](hub/ARCHITECTURE.md) and [`sync/README.md`](sync/README.md). Contribution and security guidance is available in [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`.github/SECURITY.md`](.github/SECURITY.md).

The verified minimum environment is Git with Windows PowerShell 5.1. Automated checks also cover `pwsh` on Windows and, experimentally, on Ubuntu. Linux support is not yet declared.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/check-hub.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test-tooling.ps1
git diff --check
```
