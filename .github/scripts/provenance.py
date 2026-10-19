#!/usr/bin/env python3
"""provenance — check a git range for the AGENTS.md §3.4 / §10.7 commit trailers.

Usage::

    python3 tools/provenance <base>..<head> [--json]

Run inside a git repository. Every commit in ``base..head`` is checked; merge
commits (>= 2 parents) are skipped. A commit **fails** when any of::

    * it has no non-empty ``Agent:`` trailer;
    * it touches product code without a well-formed ``Delegated-Run:`` trailer;
    * it has neither a well-formed ``Delegated-Run:`` nor a non-empty ``Exempt:``.

A changed path is *exempt* when it ends in ``.md``, its first path segment is
``docs`` or ``.github``, its extension is one of the media extensions below
(case-insensitive), or ``.gitattributes`` — read from the range's **base**
revision, so a PR cannot exempt its own code — marks it ``linguist-generated``.
Anything else is *product code*. Both sides of a rename and a deleted path count.

``Delegated-Run:`` must look like ``YYYYMMDD-HHMMSS-<6 hex>``.

Exit: 0 = every checked commit passes · 1 = at least one fails · 2 = usage or git
error (bad range, not a repo). Text output names each failing commit (short sha,
subject, reasons, offending product paths) plus a one-line total; ``--json``
emits the same as an object with a ``failures`` list whose items carry ``sha``,
``reasons`` and ``paths``.

The rules live in the plain functions below (no git, no I/O): ``parse_trailers``,
``parse_linguist_generated`` / ``matches_linguist``, ``classify_path`` /
``is_exempt``, ``product_paths``, ``commit_reasons`` / ``judge_commit``. They are
importable (e.g. by ``tools/org-audit`` via ``importlib``) and run on data from
the GitHub API as well as on a git checkout. All git calls use
``GIT_OPTIONAL_LOCKS=0`` and nothing is written to the repository.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# --------------------------------------------------------------- rules (pure)

RUN_ID_RE = re.compile(r"^\d{8}-\d{6}-[0-9a-fA-F]{6}$")
TRAILER_RE = re.compile(r"^([A-Za-z0-9_-]+):[ \t]*(.*)$")

EXEMPT_EXTENSIONS = frozenset({
    "png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "psd",
    "mp3", "wav", "ogg", "flac", "mp4", "webm", "mov",
    "ttf", "otf", "woff", "woff2",
})
EXEMPT_SEGMENTS = frozenset({"docs", ".github"})

REASON_NO_AGENT = "no Agent: trailer"
REASON_PRODUCT_NO_RUN = "touches product code without Delegated-Run:"
REASON_NO_RUN_OR_EXEMPT = "has neither Delegated-Run: nor Exempt:"


def normalize_path(path: str) -> str:
    """POSIX-style, no leading ``./`` or ``/`` — the form git reports."""
    p = str(path).replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return p.lstrip("/")


def path_extension(path: str) -> str:
    base = normalize_path(path).rsplit("/", 1)[-1]
    return base.rsplit(".", 1)[1].lower() if "." in base else ""


def first_segment(path: str) -> str:
    return normalize_path(path).split("/", 1)[0]


def matches_linguist(path: str, patterns) -> bool:
    """True when a gitattributes-style ``linguist-generated`` pattern matches."""
    p = normalize_path(path)
    base = p.rsplit("/", 1)[-1]
    for raw in patterns:
        pat = str(raw).strip()
        if not pat or pat.startswith("#") or pat.startswith("!"):
            continue
        if pat.endswith("/"):
            pat += "**"
        if "/" not in pat:
            if fnmatch.fnmatchcase(base, pat):
                return True
        elif fnmatch.fnmatchcase(p, pat) or fnmatch.fnmatchcase(p, pat.rstrip("/") + "/**"):
            return True
    return False


def parse_linguist_generated(text: str) -> list[str]:
    """The ``linguist-generated`` patterns (order kept) in a .gitattributes text."""
    out: list[str] = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        parts = s.split()
        if len(parts) < 2:
            continue
        pattern, attrs = parts[0], parts[1:]
        for attr in attrs:
            if attr == "linguist-generated" or attr == "linguist-generated=true":
                out.append(pattern)
            elif attr in ("-linguist-generated", "linguist-generated=false"):
                break  # explicitly not generated
    return out


# alias: callers may talk about either "patterns" or "rules"
parse_linguist_patterns = parse_linguist_generated


def is_exempt(path: str, generated_patterns=()) -> bool:
    """True when a changed path is exempt from the product-code rule (item 2)."""
    p = normalize_path(path)
    if not p:
        return True
    if p.lower().endswith(".md"):
        return True
    if first_segment(p) in EXEMPT_SEGMENTS:
        return True
    if path_extension(p) in EXEMPT_EXTENSIONS:
        return True
    if matches_linguist(p, generated_patterns):
        return True
    return False


def classify_path(path: str, generated_patterns=()) -> str:
    """``"exempt"`` or ``"product"`` — the single path-class rule (item 2)."""
    return "exempt" if is_exempt(path, generated_patterns) else "product"


def product_paths(paths, generated_patterns=()) -> list[str]:
    """The changed paths that count as product code, deduplicated, in order."""
    seen: set[str] = set()
    out: list[str] = []
    for raw in paths:
        p = normalize_path(raw)
        if p in seen:
            continue
        seen.add(p)
        if not is_exempt(p, generated_patterns):
            out.append(p)
    return out


def parse_trailers(message: str) -> dict[str, str]:
    """Parse the message's trailer block the way ``git interpret-trailers`` does.

    The trailer block is the **last paragraph** of the message and only counts
    when every line in it is either a ``Key: value`` trailer or a continuation
    line (starting with whitespace). Text anywhere else in the body does not
    count. Later occurrences of a key win. The returned mapping keeps empty
    values as ``""`` — callers decide whether a value is non-empty.
    """
    lines = [ln.rstrip("\r") for ln in message.split("\n")]
    end = len(lines)
    while end > 0 and lines[end - 1].strip() == "":
        end -= 1
    start = end
    while start > 0 and lines[start - 1].strip() != "":
        start -= 1
    block = lines[start:end]
    if not block:
        return {}
    trailers: dict[str, str] = {}
    seen = 0
    for line in block:
        if line[:1] in (" ", "\t"):        # continuation of the previous trailer
            if seen == 0:
                return {}
            continue
        m = TRAILER_RE.match(line)
        if not m:
            return {}
        trailers[m.group(1)] = m.group(2).strip()
        seen += 1
    return trailers if seen else {}


def trailer_value(trailers: dict[str, str], key: str) -> str | None:
    """The non-empty value of ``key``, or None (item 3: empty values do not count)."""
    value = trailers.get(key, "").strip()
    return value or None


def has_trailer(trailers: dict[str, str], key: str) -> bool:
    return trailer_value(trailers, key) is not None


def valid_run_id(value: str | None) -> bool:
    return bool(value) and bool(RUN_ID_RE.match(value.strip()))


def commit_reasons(message: str, paths, generated_patterns=()) -> list[str]:
    """The item-4 failure reasons for one commit (empty list = it passes).

    Works on plain data: ``message`` is the raw commit message and ``paths`` the
    list of changed paths (both sides of a rename, deleted paths included).
    """
    trailers = parse_trailers(message)
    run = trailer_value(trailers, "Delegated-Run")
    run_ok = valid_run_id(run)
    exempt_ok = has_trailer(trailers, "Exempt")
    products = product_paths(paths, generated_patterns)

    reasons: list[str] = []
    if not has_trailer(trailers, "Agent"):
        reasons.append(REASON_NO_AGENT)
    if products and not run_ok:
        reasons.append(REASON_PRODUCT_NO_RUN)
    if not run_ok and not exempt_ok:
        reasons.append(REASON_NO_RUN_OR_EXEMPT)
    return reasons


def judge_commit(message: str, paths, generated_patterns=()) -> dict:
    """Judge one commit: ``{"passes", "reasons", "paths"}`` (paths = product)."""
    products = product_paths(paths, generated_patterns)
    reasons = commit_reasons(message, paths, generated_patterns)
    return {"passes": not reasons, "reasons": reasons, "paths": products}


# ------------------------------------------------------------- git plumbing

ENV = {**os.environ, "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"}


class GitError(Exception):
    pass


def git(repo: Path, *args: str) -> tuple[int, str, str]:
    try:
        p = subprocess.run(["git", "-C", str(repo), *args], env=ENV,
                           capture_output=True, text=True,
                           encoding="utf-8", errors="surrogateescape")
    except FileNotFoundError:
        raise GitError("git not found")
    return p.returncode, p.stdout, p.stderr.strip()


def is_repo(repo: Path) -> bool:
    rc, _, _ = git(repo, "rev-parse", "--git-dir")
    return rc == 0


def resolves(repo: Path, rev: str) -> bool:
    rc, _, _ = git(repo, "rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}")
    return rc == 0


def commit_list(repo: Path, base: str, head: str) -> list[str]:
    """Shas in ``base..head``, oldest first, merge commits (>= 2 parents) dropped."""
    rc, out, err = git(repo, "rev-list", "--reverse", "--parents", f"{base}..{head}")
    if rc != 0:
        raise GitError(err or f"bad range {base}..{head}")
    shas: list[str] = []
    for line in out.splitlines():
        fields = line.split()
        if not fields:
            continue
        if len(fields) - 1 >= 2:      # merge commit
            continue
        shas.append(fields[0])
    return shas


def changed_paths(repo: Path, sha: str) -> list[str]:
    """Paths a commit changed; both sides of a rename and deleted paths count.

    ``-z`` NUL-separates the records and disables the ``core.quotepath`` C-style
    quoting/octal escaping, so a path is read exactly as stored — any unicode,
    space, tab or quote in the name survives unchanged.
    """
    rc, out, err = git(repo, "diff-tree", "--no-commit-id", "--name-status",
                       "-r", "-M", "--root", "-z", sha)
    if rc != 0:
        raise GitError(err or f"cannot read {sha}")
    tokens = out.split("\0")
    paths: list[str] = []
    i = 0
    while i < len(tokens):
        status = tokens[i]
        i += 1
        if not status:
            continue
        if status[:1] in ("R", "C"):
            if i + 1 < len(tokens):
                paths.append(tokens[i])       # old side
                paths.append(tokens[i + 1])   # new side
                i += 2
        elif i < len(tokens):
            paths.append(tokens[i])
            i += 1
    return paths


def commit_message(repo: Path, sha: str) -> str:
    rc, out, err = git(repo, "log", "-1", "--format=%B", sha)
    if rc != 0:
        raise GitError(err or f"cannot read message of {sha}")
    return out


def commit_subject(repo: Path, sha: str) -> str:
    rc, out, _ = git(repo, "log", "-1", "--format=%s", sha)
    return out.strip() if rc == 0 else ""


def short_sha(repo: Path, sha: str) -> str:
    rc, out, _ = git(repo, "rev-parse", "--short", sha)
    return out.strip() if rc == 0 else sha[:7]


def load_generated_patterns(repo: Path, rev: str) -> list[str]:
    """``linguist-generated`` patterns from ``<rev>:.gitattributes`` (missing => none).

    The file is read from the revision under review — the range's *base* — not from
    the working tree: otherwise a PR could add ``* linguist-generated`` and exempt
    its own product code. ``.git/info/attributes`` is deliberately ignored.
    """
    rc, out, _ = git(repo, "show", f"{rev}:.gitattributes")
    if rc != 0:
        return []
    return parse_linguist_generated(out)


# ------------------------------------------------------------------- CLI

def render_text(rng: str, checked: int, failures: list[dict]) -> str:
    lines: list[str] = []
    for f in failures:
        lines.append(f"FAIL {f['short']} {f['subject']}")
        for reason in f["reasons"]:
            lines.append(f"  - {reason}")
        if f["paths"]:
            lines.append(f"  product: {', '.join(f['paths'])}")
    lines.append(f"provenance {rng}: {checked} commit(s) checked, "
                 f"{len(failures)} failed" if failures
                 else f"provenance {rng}: {checked} commit(s) checked, all passed")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="provenance", description="check a git range for §3.4 / §10.7 commit trailers")
    ap.add_argument("range", metavar="<base>..<head>", help="commit range to check")
    ap.add_argument("--json", action="store_true", help="emit the result as JSON")
    a = ap.parse_args(argv)

    rng = a.range
    if ".." not in rng:
        print("provenance: range must be <base>..<head>", file=sys.stderr)
        return 2
    base, _, head = rng.partition("..")
    if not base or not head:
        print("provenance: range must be <base>..<head>", file=sys.stderr)
        return 2

    repo = Path.cwd()
    if not is_repo(repo):
        print(f"provenance: not a git repository: {repo}", file=sys.stderr)
        return 2
    for rev in (base, head):
        if not resolves(repo, rev):
            print(f"provenance: bad revision {rev!r} in range {rng}", file=sys.stderr)
            return 2

    try:
        shas = commit_list(repo, base, head)
    except GitError as e:
        print(f"provenance: {e}", file=sys.stderr)
        return 2

    patterns = load_generated_patterns(repo, base)
    failures: list[dict] = []
    for sha in shas:
        try:
            message = commit_message(repo, sha)
            paths = changed_paths(repo, sha)
        except GitError as e:
            print(f"provenance: {e}", file=sys.stderr)
            return 2
        reasons = commit_reasons(message, paths, patterns)
        if reasons:
            failures.append({
                "sha": sha,
                "short": short_sha(repo, sha),
                "subject": commit_subject(repo, sha),
                "reasons": reasons,
                "paths": product_paths(paths, patterns),
            })

    if a.json:
        print(json.dumps({"range": rng, "checked": len(shas), "failures": failures},
                         ensure_ascii=False, indent=2))
    else:
        print(render_text(rng, len(shas), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
