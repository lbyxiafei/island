#!/usr/bin/env python3
"""Issue tooling for the HAI issue convention (single source of truth).

Detail pages in ``{root}/issue/*.md`` carry a fixed YAML frontmatter block; the
summary table ``{root}/ISSUES.md`` is *derived* from it and is rebuilt with
``sync``. ``check`` fails when the two disagree, so drift cannot survive CI.

Only the Python standard library is used: the tooling is copied into every new
repo and must run without installing anything.

Exit codes: 0 ok, 1 the derived table drifted, 2 invalid input or frontmatter.
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from pathlib import Path

TYPES = ("feat", "bug", "chore", "style", "refactor", "test", "docs")
STATUSES = ("new", "open", "in-progress", "solved", "closed")
FIELDS = ("type", "name", "title", "status", "created_ts", "updated_ts")

TIMESTAMP_FMT = "%Y-%m-%dT%H:%M:%S%z"
FILENAME_RE = re.compile(r"^(\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2})-(.+)$")
SLUG_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
MAX_SLUG_WORDS = 5

DEFAULT_BODY = "## 背景\n\n## 期望结果\n\n## 备注\n"

INDEX_PREAMBLE = """\
# ISSUES

> 本文件由 `make sync-issue` 从 `./issue/*.md` 的 frontmatter 全量重建，请勿手工编辑。

| type | name | title | status | created_ts | updated_ts |
|---|---|---|---|---|---|
"""


class IssueError(Exception):
    """Invalid input, invalid frontmatter, or an inconsistent issue tree."""


class IndexDrift(IssueError):
    """`ISSUES.md` no longer matches the detail pages."""


# --- validation ---------------------------------------------------------------


def validate_type(value: str) -> str:
    if value not in TYPES:
        raise IssueError(f"unknown issue type {value!r}, expected one of {', '.join(TYPES)}")
    return value


def validate_status(value: str) -> str:
    if value not in STATUSES:
        raise IssueError(f"unknown issue status {value!r}, expected one of {', '.join(STATUSES)}")
    return value


def validate_slug(slug: str) -> str:
    if not SLUG_RE.match(slug):
        raise IssueError(f"invalid slug {slug!r}: lowercase words joined by single '-' required")
    if len(slug.split("-")) > MAX_SLUG_WORDS:
        raise IssueError(f"invalid slug {slug!r}: at most {MAX_SLUG_WORDS} words")
    return slug


def _validate_ts(value: str, field: str) -> str:
    try:
        dt.datetime.strptime(value, TIMESTAMP_FMT)
    except ValueError as exc:
        raise IssueError(f"{field} must be RFC 3339 with offset, got {value!r}") from exc
    return value


# --- frontmatter --------------------------------------------------------------


def parse_document(text: str) -> tuple[dict[str, str], str]:
    """Split a detail page into (frontmatter, body). Strict on purpose."""
    if not text.startswith("---\n"):
        raise IssueError("detail page must start with a '---' frontmatter block")
    end = text.find("\n---", 4)
    if end == -1:
        raise IssueError("frontmatter block is not closed with '---'")

    front: dict[str, str] = {}
    for line in text[4:end].splitlines():
        if not line.strip():
            continue
        key, sep, raw = line.partition(":")
        if not sep:
            raise IssueError(f"frontmatter line is not 'key: value': {line!r}")
        key, raw = key.strip(), raw.strip()
        if key not in FIELDS:
            raise IssueError(f"unknown frontmatter field {key!r}, expected one of {', '.join(FIELDS)}")
        if key in front:
            raise IssueError(f"duplicate frontmatter field {key!r}")
        front[key] = raw

    missing = [field for field in FIELDS if field not in front]
    if missing:
        raise IssueError(f"frontmatter is missing {', '.join(missing)}")

    title = front["title"]
    if not (title.startswith('"') and title.endswith('"') and len(title) >= 2):
        raise IssueError('title must be wrapped in double quotes')
    front["title"] = title[1:-1]

    validate_type(front["type"])
    validate_status(front["status"])
    validate_slug(front["name"])
    _validate_ts(front["created_ts"], "created_ts")
    _validate_ts(front["updated_ts"], "updated_ts")

    return front, text[end + 4 :].lstrip("\n").rstrip("\n")


def render_issue(front: dict[str, str], body: str = "") -> str:
    lines = ["---"]
    for field in FIELDS:
        value = front[field]
        lines.append(f'{field}: "{value}"' if field == "title" else f"{field}: {value}")
    lines.append("---")
    document = "\n".join(lines) + "\n"
    if body.strip():
        document += "\n" + body.strip() + "\n"
    return document


def now_ts() -> str:
    """Local time, RFC 3339 with a colon in the offset."""
    stamped = dt.datetime.now().astimezone().strftime(TIMESTAMP_FMT)
    return f"{stamped[:-2]}:{stamped[-2:]}"


def filename_timestamp(timestamp: str) -> str:
    return timestamp[:19].replace("T", "-").replace(":", "-")


# --- tree access --------------------------------------------------------------


def parse_filename(filename: str) -> str:
    stem = Path(filename).stem
    match = FILENAME_RE.match(stem)
    if not match:
        raise IssueError(f"{filename}: expected {{YYYY-MM-DD-HH-MM-SS}}-{{slug}}.md")
    return match.group(2)


def issue_dir(root: Path) -> Path:
    return root / "issue"


def index_path(root: Path) -> Path:
    return root / "ISSUES.md"


def load_issues(root: Path) -> list[dict[str, str]]:
    """All detail pages as dicts carrying frontmatter fields plus filename/body."""
    directory = issue_dir(root)
    if not directory.is_dir():
        return []
    issues = []
    for path in sorted(directory.glob("*.md")):
        front, body = parse_document(path.read_text(encoding="utf-8"))
        if front["name"] != parse_filename(path.name):
            raise IssueError(f"{path.name}: name {front['name']!r} does not match the filename")
        issues.append({**front, "filename": path.name, "body": body})
    return issues


def find_issue(root: Path, name: str) -> dict[str, str]:
    for issue in load_issues(root):
        if issue["name"] == name:
            return issue
    raise IssueError(f"no issue named {name!r} under {issue_dir(root)}")


def write_issue(root: Path, issue: dict[str, str]) -> Path:
    path = issue_dir(root) / issue["filename"]
    path.parent.mkdir(parents=True, exist_ok=True)
    front = {field: issue[field] for field in FIELDS}
    path.write_text(render_issue(front, issue.get("body", "")), encoding="utf-8")
    return path


# --- derived index ------------------------------------------------------------


def sort_key(issue: dict[str, str]) -> tuple[int, float]:
    updated = dt.datetime.strptime(issue["updated_ts"], TIMESTAMP_FMT).timestamp()
    return STATUSES.index(issue["status"]), -updated


def render_index(issues: list[dict[str, str]]) -> str:
    rows = []
    for issue in sorted(issues, key=sort_key):
        title = issue["title"].replace("|", r"\|")
        link = f"[{issue['name']}](./issue/{issue['filename']})"
        rows.append(
            f"| {issue['type']} | {link} | {title} | {issue['status']} "
            f"| {issue['created_ts']} | {issue['updated_ts']} |"
        )
    return INDEX_PREAMBLE + "".join(row + "\n" for row in rows)


def sync_index(root: Path) -> Path:
    path = index_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_index(load_issues(root)), encoding="utf-8")
    return path


# --- commands -----------------------------------------------------------------


def cmd_create(args: argparse.Namespace) -> int:
    root = Path(args.root)
    validate_type(args.type)
    validate_slug(args.slug)
    if any(issue["name"] == args.slug for issue in load_issues(root)):
        raise IssueError(f"issue {args.slug!r} already exists")

    timestamp = now_ts()
    issue = {
        "type": args.type,
        "name": args.slug,
        "title": args.title,
        "status": "new",
        "created_ts": timestamp,
        "updated_ts": timestamp,
        "filename": f"{filename_timestamp(timestamp)}-{args.slug}.md",
        "body": Path(args.body_file).read_text(encoding="utf-8") if args.body_file else DEFAULT_BODY,
    }
    path = write_issue(root, issue)
    sync_index(root)
    print(path)
    return 0


def cmd_touch(args: argparse.Namespace) -> int:
    root = Path(args.root)
    issue = find_issue(root, args.name)
    issue["updated_ts"] = now_ts()
    write_issue(root, issue)
    sync_index(root)
    print(f"{issue['filename']}: updated_ts -> {issue['updated_ts']}")
    return 0


def cmd_set_status(args: argparse.Namespace) -> int:
    root = Path(args.root)
    validate_status(args.status)
    issue = find_issue(root, args.name)
    issue["status"] = args.status
    issue["updated_ts"] = now_ts()
    write_issue(root, issue)
    sync_index(root)
    print(f"{issue['filename']}: status -> {args.status}")
    return 0


def cmd_sync(args: argparse.Namespace) -> int:
    root = Path(args.root)
    issues = load_issues(root)
    print(f"{sync_index(root)}: {len(issues)} issue(s)")
    return 0


def cmd_check(args: argparse.Namespace) -> int:
    root = Path(args.root)
    issues = load_issues(root)
    path = index_path(root)
    if not path.exists():
        if not issues:
            print("ok: no issues yet")
            return 0
        raise IndexDrift(f"{path} is missing, run `make sync-issue`")
    if path.read_text(encoding="utf-8") != render_index(issues):
        raise IndexDrift(f"{path} disagrees with the detail pages, run `make sync-issue`")
    print(f"ok: {len(issues)} issue(s) consistent")
    return 0


# --- wiring -------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="issue.py", description=__doc__.splitlines()[0])
    parser.add_argument("--root", default="hai", help="HAI directory, default: hai")
    commands = parser.add_subparsers(dest="command", required=True)

    create = commands.add_parser("create", help="create a detail page and refresh the index")
    create.add_argument("--type", required=True, choices=TYPES)
    create.add_argument("--slug", required=True)
    create.add_argument("--title", required=True)
    create.add_argument("--body-file", help="file providing the body, default: a section skeleton")
    create.set_defaults(func=cmd_create)

    touch = commands.add_parser("touch", help="bump updated_ts")
    touch.add_argument("--name", required=True)
    touch.set_defaults(func=cmd_touch)

    set_status = commands.add_parser("set-status", help="change status and bump updated_ts")
    set_status.add_argument("--name", required=True)
    set_status.add_argument("--status", required=True, choices=STATUSES)
    set_status.set_defaults(func=cmd_set_status)

    sync = commands.add_parser("sync", help="rebuild ISSUES.md from the detail pages")
    sync.set_defaults(func=cmd_sync)

    check = commands.add_parser("check", help="fail when ISSUES.md drifted")
    check.set_defaults(func=cmd_check)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except IndexDrift as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
    except IssueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2) from exc


if __name__ == "__main__":  # pragma: no cover - entry point wiring
    sys.exit(main())
