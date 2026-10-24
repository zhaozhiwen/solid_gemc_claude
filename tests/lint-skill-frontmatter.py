#!/usr/bin/env python3
"""Lint every SKILL.md's YAML frontmatter with a strict parser.

Why: Codex CLI parses SKILL.md frontmatter with a strict YAML parser, while
Claude Code is lenient. A `: ` (colon-space) inside an unquoted scalar (e.g. a
`description:` value) is read as a nested mapping and makes Codex reject the
*whole* skill — silently, so the skill just never loads. This lint reproduces
that strictness (`yaml.safe_load`) so the bug can't regress.

Checks, per `**/SKILL.md`:
  1. A frontmatter block exists (`---` ... `---` at the top).
  2. It parses as strict YAML.
  3. It is a mapping with non-empty string `name` and `description`.
  4. `description` is at most 1024 characters (the Agent Skills limit; over it
     Codex drops the skill, again silently).
  5. The body has no shell positional parameter (`$` + digit) and no
     `${CLAUDE_PLUGIN_ROOT:...}` form: Claude Code replaces `$<digit>` with words of
     the user's request and fills in only the plain `${CLAUDE_PLUGIN_ROOT}`.

Exit 0 if all skills pass, 1 otherwise. Requires PyYAML.
"""
import pathlib
import re
import sys

try:
    import yaml
except ImportError:
    print("FAIL: PyYAML not installed (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

FRONTMATTER = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
MAX_DESCRIPTION = 1024
POSITIONAL = re.compile(r"\$[0-9]")
PLUGIN_ROOT_EXPANSION = re.compile(r"\$\{CLAUDE_PLUGIN_ROOT[:#%/]")


def check(path: pathlib.Path) -> list[str]:
    errors = []
    text = path.read_text()
    m = FRONTMATTER.match(text)
    if not m:
        return [f"{path}: no `---` frontmatter block at top of file"]
    try:
        data = yaml.safe_load(m.group(1))
    except yaml.YAMLError as e:
        return [f"{path}: invalid YAML frontmatter: {e}"]
    if not isinstance(data, dict):
        return [f"{path}: frontmatter is not a mapping"]
    for key in ("name", "description"):
        val = data.get(key)
        if not isinstance(val, str) or not val.strip():
            errors.append(f"{path}: frontmatter `{key}` missing or not a non-empty string")
    desc = data.get("description")
    if isinstance(desc, str) and len(desc) > MAX_DESCRIPTION:
        errors.append(f"{path}: `description` is {len(desc)} chars, limit {MAX_DESCRIPTION}")
    body = text[m.end():]
    for n, line in enumerate(body.splitlines(), start=text[:m.end()].count("\n") + 1):
        if POSITIONAL.search(line):
            errors.append(f"{path}:{n}: shell positional parameter (Claude Code substitutes it)")
        if PLUGIN_ROOT_EXPANSION.search(line):
            errors.append(f"{path}:{n}: use plain ${{CLAUDE_PLUGIN_ROOT}} (the only form filled in)")
    return errors


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    skills = sorted(root.glob("**/SKILL.md"))
    if not skills:
        print("no SKILL.md files found", file=sys.stderr)
        return 0
    all_errors = []
    for path in skills:
        errs = check(path)
        rel = path.relative_to(root)
        if errs:
            all_errors.extend(errs)
            print(f"[FAIL] {rel}")
        else:
            print(f"[ok]   {rel}")
    if all_errors:
        print("\n" + "\n".join(all_errors), file=sys.stderr)
        print(f"\n{len(all_errors)} problem(s) across {len(skills)} skill(s)", file=sys.stderr)
        return 1
    print(f"\nall {len(skills)} SKILL.md frontmatter blocks are strict-YAML clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
