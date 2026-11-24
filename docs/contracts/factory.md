# Meatproxy factory contract

**Name:** `meatproxy-factory` · **Current version:** 5 · **Owner:** this repository

A Dark Software Factory is a project folder with a `factory/` folder in it. Its CEO agent
keeps the factory's state there in plain files. Meatproxy reads those files, shows them, and
writes exactly four things into them: your answers, your ideas, your mandate and your releases. This document is the
contract between the two. Anything that is not in it is not agreed: a CEO playbook, a
prompt or a factory README may add to it for their own use, but Meatproxy relies only on
what is written here.

A factory declares the version it follows in `factory/contract.yml`. Meatproxy turns a
feature on only when the factory declares a version that has it.

## Versions

| Version | Date | Adds |
| --- | --- | --- |
| 1 | 2026-11-15 | Decisions, workstreams, briefings, `autonomy.yml`, answers written by Meatproxy, the heartbeat run. |
| 2 | 2026-11-15 | Ideas (`ideas/`), sent from Meatproxy; `contract.yml`. |
| 3 | 2026-11-16 | Your mandate (`mandate.yml`), written by Meatproxy: what the CEO may do on its own (including whether it comes up with ideas of its own, `propose`), its role, your preferences. |
| 4 | 2026-11-16 | Wake-up sources in `contract.yml`: the factory's Sentry project and Tracker project. Meatproxy wakes the CEO for a new or returning error and for a story that changed (D61). |
| 5 | 2026-11-24 | To-dos (`kind: todo`, with `## How`) for what only you can do, and decisions you start yourself (`from: you`): your release of finished work. Everything the CEO needs from you is an open decision; the briefing never asks in prose alone (D81). |

A factory without `contract.yml` is treated as version 1. A factory that declares a newer
version than this Meatproxy knows is still read with what this version knows, and the app
says that it is newer.

Changing the contract means a new version here, with its row in the table, before any
factory or the app relies on it.

## Layout

```
factory/
├── contract.yml      the contract version this factory follows
├── CHARTER.md        the factory's own rules (free form; not read by Meatproxy)
├── CEO.md            the CEO's run playbook (free form; not read by Meatproxy)
├── autonomy.yml      gate levels and streaks; STOP on line 1 pauses everything
├── mandate.yml       your mandate: autonomy per item, the CEO's role, your preferences   (v3)
├── decisions/        the yes/no queue: D-NNNN-<slug>.md
├── workstreams/      the work queue: W-NNN-<slug>.md
├── ideas/            your ideas, sent from Meatproxy: I-NNNN-<slug>.md   (v2)
└── briefings/        one per CEO run: YYYY-MM-DD.md, a second run that day -2, -3, …
```

## Who writes what

| File | The CEO | Meatproxy |
| --- | --- | --- |
| `contract.yml`, `CHARTER.md`, `CEO.md`, `autonomy.yml`, `briefings/`, `workstreams/` | writes | reads |
| `decisions/` | creates, withdraws, expires | writes your answer into an `open` decision only: `status`, `answered`, `## Answer`; creates your release (v5): a new file, `from: you`, already `yes`, never overwriting one |
| `ideas/` (v2) | sets `status`, `decision`, writes `## CEO` | creates a new file; never changes it afterwards |
| `mandate.yml` (v3) | reads and follows it; never writes it | writes it whenever you change your mandate |

Meatproxy's writes are atomic (a temporary file renamed over the original), never touch a
decision that is no longer `open`, and never overwrite an idea file. Switching a project on as
a factory writes nothing.

### Setting a factory up

A factory without `contract.yml`, `CHARTER.md` and `CEO.md` is not set up: its heartbeat does
not start the CEO, not even on Run now, because the CEO would have no playbook. Meatproxy then
offers starter files: `contract.yml` (the current version), `CHARTER.md`, `README.md`,
`CEO.md`, `autonomy.yml` (every gate `ask`), `mandate.yml` (Assistant) and, unticked, the
project's `.claude/settings.json` allowlist (read, edit, the project's tests and local git;
never a push or a merge). You see each file's text first. Meatproxy writes only the files you
tick, only where no file is yet, and never replaces one; it also makes the empty `decisions/`,
`workstreams/`, `ideas/` and `briefings/` folders. After that the CEO owns the files as above.

## `contract.yml`

```yaml
contract: meatproxy-factory
version: 4
sentry: my-org/my-app        # v4, optional: the Sentry organization and project slugs
sentry-host: de.sentry.io    # v4, optional: the host the organization lives on (default sentry.io)
tracker: my-app              # v4, optional: the Tracker project's slug
```

### Wake-up sources (v4)

Every 15 minutes Meatproxy asks, with your own read tokens (kept in the macOS Keychain, never in a
file), for:

- **Sentry:** unresolved issues of level `error` or `fatal` in the project. An issue it has not seen
  before, or one that turns `regressed` or `escalating`, wakes the CEO with `.sentry`: its short id
  and title. Not when your mandate has `bugs: off`. Three Sentry wakes in a row hold the factory
  until you look (the same kind of breaker as for CI).
- **Tracker:** stories in the project that are `rejected` or `unstarted` (ready to pick up), over
  Tracker's MCP endpoint. A story that enters one of those states wakes the CEO with `.tracker`: its
  key, the state and its title.

The first look after Meatproxy starts only notes what is there. The CEO reads the details itself, with
its own access; Meatproxy passes ids and titles only. These wakes count towards the automatic runs per
day and the API-price cap. Slugs are letters, digits, `.`, `-` and `_`; a `sentry-host` must end in
`sentry.io`. Anything else is ignored.

## Decisions: `decisions/D-NNNN-<slug>.md`

```markdown
---
id: D-0007
title: Ship offline streak sync (W-002) to production?   # one yes/no question
kind: ship            # plan | ship | store | promote | stop | other | todo (v5)
gate: ship            # plan | ship | store | always-ask
status: open          # open | yes | no | expired | withdrawn
workstream: W-002     # optional
workstreams: [W-002]  # optional (v5): every workstream it is about
from: null            # v5: you, for one you started in Meatproxy
replaces: null        # the decision this one replaces after a "no"
asked: 2026-11-16T07:05:00+01:00
answered: null        # set when status leaves open
---

## Why
## How                # a to-do's steps (v5)
## Evidence
## On yes
## On no
## Answer
```

Required: `id`, `title`, `status`. An `open` decision counts in Needs you. Meatproxy writes
`status: yes|no`, `answered` (ISO 8601 with offset) and your note under `## Answer`.

### What the CEO needs from you (v5)

Everything the CEO needs from you is an open decision, so Meatproxy shows it with a button.
A line in the briefing alone is never a way to ask (D81).

- **A choice** is a yes/no question, as above.
- **Something only you can do** (sign in, allow a permission, change a setting, a manual
  step) is a to-do: `kind: todo`, an imperative title, `## Why` and `## How` with the exact
  steps. Meatproxy shows **Done** (`status: yes`) and **Not now** (`status: no`). After Done
  the CEO checks it on its next run and files a new to-do when it is still missing; after Not
  now it leaves it until something changes.
- **Your release.** Work in `ship` with no open `ship` decision and no `yes` on one shows in
  Meatproxy as ready to release (after a "no", or when the mandate keeps shipping off).
  **Release now** creates a decision with `kind: ship`, `from: you`, `status: yes`, `answered`
  and `workstreams: [...]`, with the next free D-number. It is your own instruction: it holds
  even where the mandate keeps shipping off. The CEO acts on it first and ships the way the
  factory ships.

The briefing's `## Needs you` lists only the open decisions, by id. Meatproxy's heartbeat
prompt carries these rules to every factory and asks a CEO on an older version to raise
`contract.yml` to 5.

## Workstreams: `workstreams/W-NNN-<slug>.md`

```markdown
---
id: W-002
title: Offline streak sync
type: feature         # feature | bug | chore
phase: ship           # plan | build | test | ship | done | dropped
source: product       # free text: where the work came from
branch: null
pr: null              # a URL
release: null
opened: 2026-11-12
updated: 2026-11-15
decisions: [D-0007]
---

## Goal
## Acceptance criteria
## Out of scope
## Log
- 2026-11-12 plan: proposed (D-0005).
- 2026-11-14 test → build: the tester found a reset on resume.
```

Required: `id`, `title`, `phase`. A log line `<from> → <to>: reason` (or `->`) with `<to>`
earlier than `<from>` is a step back, shown with ↩. `dropped` is final.

## Briefings: `briefings/YYYY-MM-DD.md`

Three sections in this order: `## Briefing` (at most 5 list items), `## Needs you`,
`## Delivered`. Meatproxy shows the latest one (by date, then the `-N` suffix).

## `autonomy.yml`

```yaml
level: hybrid          # assistant | hybrid | dark (derived from the gates when left out)
gates:
  plan: notify         # ask | notify
  ship: ask
  store: ask
streaks:
  ship: 5              # yeses in a row on that gate
```

`STOP` as the first line pauses the factory: Meatproxy shows it, and the CEO starts and
ships nothing.

## Your mandate: `mandate.yml` (v3)

```yaml
level: hybrid            # assistant | hybrid | dark | custom
role: orchestrator       # orchestrator (delegates all work) | hands-on (may do small things itself)
items:                   # ask: a yes/no question first · notify: do it, say so in the briefing · off: never
  propose: ask           # come up with ideas of its own: product improvements, new workstreams
  bugs: notify           # pick up Sentry and CI bugs
  dependencies: notify   # dependency and security updates
  prs: notify            # open and merge its own PRs, after an independent test
  ship: ask              # ship to production
  store: ask             # store releases
  spend: ask             # spend money (paid services, extra CI minutes)
  promote: ask           # change its own gates (promote proposals)
preferences:
  quiet_hours: "22:00-07:00"
  briefing_language: en  # en | nl
  proposals_per_run: 2
  pr_size: small         # small | medium | large
  batch_small_fixes: true
notes: |
  Your own words; part of the mandate.
team:                    # who the CEO may call in as sub-agents (subagent_type = the name), at most how many at once
  follows: own           # campus: the campus default team · own: this floor's own team
  product: 1
  developer: 2
  tester: 1
```

The levels are presets over the items: **assistant** asks everything; **hybrid** lets bugs,
dependencies and its own PRs through and asks before propose, ship, store, spend and promote;
**dark** lets everything through except spend and store; **custom** is per item. Every item is
written with its meaning as a comment, so the file explains itself to the CEO. An item a CEO
does not know yet counts as `ask`. Your own ideas (`ideas/`) are no item: they are always
handled, whatever the mandate says (below). With a mandate, the
CEO follows it on every run; it wins over `autonomy.yml` and the playbook. `autonomy.yml`
stays the CEO's record of its gates and streaks; its promote proposals remain questions for
you. Without `mandate.yml` the CEO works from `autonomy.yml` as in version 2. The floor's
darkness follows the mandate's level.

The `team` block (D79) says which helpers the CEO may call in and how many of each may work at
once. The CEO itself is always there and is not listed. There is no maximum but the user's:
the team is the CEO plus the sum of the numbers. A floor follows the campus default team until
the user gives it its own (`follows: own`); Meatproxy writes the default's numbers out either
way, so the CEO only reads this file. Each name is a Claude Code sub-agent in
`.claude/agents/<name>.md`; Meatproxy offers those files for the standard profiles (product,
developer, tester, designer, research, devops, marketing, sales), shows them first and never
replaces one. Claude Code has no limit per type of its own, so the numbers are an agreement:
Meatproxy shows it on the Team tab when more ran at once than allowed. Codex has no agent files;
there only the numbers apply. A mandate without a `team` block leaves helpers to the playbook.
Profiles you make yourself in Meatproxy (a name, what it may do, a model, how much it may touch
and a look) are offered on every floor and written as agent files the same way. Every team member
is always on the floor: a free one waits in the lounge; when the CEO calls one in, that person does
the job beside it and walks back after.

## Ideas: `ideas/I-NNNN-<slug>.md` (v2)

```markdown
---
id: I-0002
title: A gentle reminder when a daily streak is about to break   # your first line
status: new           # new | taken | declined
sent: 2026-11-15T22:40:00+01:00
workstream: null      # the workstream it became (v3); decision: the plan decision filed for it (v2)
---

What you wrote, as you wrote it.

## CEO
The CEO's reply: what it proposed, or why it declined.
```

Meatproxy creates the file with `status: new`, the next free number and an empty `## CEO`,
and wakes the CEO after the answer window. Your ideas are always handled: they are your own
proposal, so the CEO asks no yes for them. The CEO:

- takes an idea by shaping it into a workstream in `plan` straight away (v3; in v2 it filed a
  plan decision first), then sets `status: taken`, `workstream: W-NNN` and a one-line reply
  under `## CEO`; the gates after planning (ship, store, spend) follow the mandate as always;
- declines an idea only when it is outside the factory's charter or already done, with the
  reason under `## CEO`.

## The heartbeat run

Meatproxy starts the CEO in the project folder: `claude -p` with
`--permission-mode acceptEdits`, `--max-turns` and the project's `.claude/settings.json`
passed with `--settings`, or `codex exec -s workspace-write`. The prompt names this contract
and its version, points at `factory/CHARTER.md`, `factory/README.md` and `factory/CEO.md`,
says to follow `factory/mandate.yml` when it exists (v3), and ends with why the CEO woke:

| Wake | Prompt says |
| --- | --- |
| schedule | its regular heartbeat |
| caught up | a missed heartbeat while Meatproxy was closed |
| answered | which decisions you answered; act on them first |
| idea (v2) | which ideas you sent; handle new ideas first |
| run now | you asked for a run |
| CI failed | which repository and run failed |

The run must end with the briefing written. Its permissions are the project's allowlist and
nothing else; what it is denied it reports in the briefing instead of working round it.
