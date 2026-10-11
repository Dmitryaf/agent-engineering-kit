"""Read-only checks for the Markdown kit; Python standard library only."""

from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
INSTRUCTIONS = ("AGENTS.md", "personal/AGENTS.md", "examples/project/AGENTS.md")


def check(root: Path) -> list[str]:
    errors = []
    listed = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root,
    ).decode("utf-8").split("\0")
    files = {root / name for name in listed if name and (root / name).is_file()}
    for name in INSTRUCTIONS:
        path = root / name
        if path not in files:
            errors.append(f"Missing public instruction file: {name}")
            continue
        content = path.read_text(encoding="utf-8-sig")
        if not content.strip() or len(content.encode("utf-8")) > 32768:
            errors.append(f"Instruction file is empty or exceeds 32 KiB: {name}")
        if re.search(r"\.ai-rules/|(?:rules|profiles|workflows|sync)/|https?://", content):
            errors.append(f"Instruction file depends on old rules or remote reading: {name}")
    for path in sorted(files):
        if path.suffix != ".md":
            continue
        content = path.read_text(encoding="utf-8-sig")
        if re.search(r"\b[A-Za-z]:[\\/]|/Users/|/home/[^/\s]+/|\.local-docs/", content):
            errors.append(f"Possible private path: {path.relative_to(root)}")
        # This repository uses inline Markdown links without titles or anchors.
        for link in re.findall(r"\[[^\]]*\]\(([^)]+)\)", content):
            url = urlsplit(link)
            if url.scheme or url.netloc or not url.path:
                continue
            target = (path.parent / unquote(url.path)).resolve()
            if not target.is_relative_to(root) or target not in files:
                errors.append(f"Missing public link target: {path.relative_to(root)} -> {link}")
    return errors


if __name__ == "__main__":
    failures = check(ROOT)
    if failures:
        raise SystemExit("\n".join(failures))
    print("PASS: instruction files, public local links and private-path scan.")
