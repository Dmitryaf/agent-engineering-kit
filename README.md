# AI Rules Hub

AI Rules Hub is a local, versioned policy layer for coding agents. It keeps reusable engineering rules in one repository while each connected project retains its own instructions, exceptions, and approval boundaries.

The hub is not a hosted service or agent runtime. A connected project receives an autonomous snapshot under `.ai-rules/upstream/` and can use it without access to the hub.

## Quick start

Clone and validate the hub, then generate a project-specific connection request:

```powershell
git clone https://github.com/Dmitryaf/ai-rules-hub.git
Set-Location ai-rules-hub
.\ai-rules.ps1 doctor
.\ai-rules.ps1 prompt connect -ProjectRoot C:\path\to\project
```

Paste the generated request into a coding agent running in the target project. It will inspect the project, recommend the smallest relevant composition, prepare local routing, show a Plan, and stop before `-Apply` for explicit approval.

If the composition is already known, connect directly:

```powershell
.\ai-rules.ps1 connect `
  -ProjectRoot C:\path\to\project `
  -Profiles standard-product

# Run only after reviewing the Plan
.\ai-rules.ps1 connect `
  -ProjectRoot C:\path\to\project `
  -Profiles standard-product `
  -Apply
```

Shared rules do not need to be copied manually. After the first Apply, use `.\ai-rules.ps1 prompt audit` or the canonical [`workflows/PROJECT_AUDIT_PROMPT.md`](workflows/PROJECT_AUDIT_PROMPT.md) to complete local routing and audit the project without fixing unrelated gaps.

## Safety model

```text
Plan → Review → Apply → Verify
```

- `Plan` is read-only and shows every managed path and action.
- `Apply` requires an explicit flag, a full Git commit SHA, and a clean hub checkout.
- Managed writes and lock-file replacement are transactional on handled failures.
- Locally changed managed files become conflicts and remain untouched.
- Deselected files become visible orphan states and are not deleted automatically.
- Paths through symlinks, junctions, or other reparse points are rejected.
- The hub never runs `git pull`, commits, pushes, publishes, rewrites history, or changes remote services.

The synchronization layer owns only `.ai-rules/upstream/` and `.ai-rules/lock.json`. Project-owned `AGENTS.md`, `.ai-rules/manifest.json`, `.ai-rules/RULESET.md`, and `.ai-rules/PROJECT_RULES.md` are preserved after their initial optional seed.

## Rule model

- [`rules/CORE.md`](rules/CORE.md) contains the minimal baseline.
- [`rules/`](rules/) contains task-relevant portable policies.
- [`profiles/`](profiles/) contains reusable compositions for stable project properties.
- [`workflows/`](workflows/) contains explicit task processes such as connection, audit, and project study.
- [`templates/`](templates/) contains project-owned starter documents.
- [`evals/`](evals/) contains human-reviewed behavioral cases for checking whether key rules change agent behavior.

Profiles and topics are selected in `.ai-rules/manifest.json`; `.ai-rules/lock.json` records the exact installed revision and normalized SHA-256 values. The compatible `project-study` topic identifier currently materializes a workflow and is not selected by any profile.

## Inspect and update

```powershell
.\ai-rules.ps1 status -ProjectRoot C:\path\to\project
.\ai-rules.ps1 doctor -ProjectRoot C:\path\to\project
.\ai-rules.ps1 update -ProjectRoot C:\path\to\project

# Run only after reviewing the update Plan
.\ai-rules.ps1 update -ProjectRoot C:\path\to\project -Apply
```

`status` distinguishes synchronized, inconsistent, unpinned, newer, older, diverged, and locally unavailable revisions. The CLI does not fetch or switch Git revisions automatically.

For the full low-level contract, ownership boundaries, state definitions, and recovery guidance, see [`sync/README.md`](sync/README.md). Repository architecture is documented in [`hub/ARCHITECTURE.md`](hub/ARCHITECTURE.md).

## Status and requirements

AI Rules Hub is an early-stage public project without a stable compatibility promise. The verified workflow currently requires Git and Windows PowerShell 5.1 or PowerShell 7+ with `powershell.exe` available.

Run repository validation with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/check-hub.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test-tooling.ps1
git diff --check
```

See [`CONTRIBUTING.md`](CONTRIBUTING.md), [`.github/SECURITY.md`](.github/SECURITY.md), and [`LICENSE`](LICENSE) for contribution, vulnerability reporting, and licensing information.
