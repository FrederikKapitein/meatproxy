# Meatproxy factory contract

**Name:** `meatproxy-factory` · **Current version:** 4 · **Owner:** this repository

A Dark Software Factory is a project folder with a `factory/` folder in it. Its CEO agent
keeps the factory's state there in plain files. Meatproxy reads those files, shows them, and
writes exactly three things into them: your answers, your ideas and your mandate. This document is the
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
| `decisions/` | creates, withdraws, expires | writes your answer into an `open` decision only: `status`, `answered`, `## Answer` |
| `ideas/` (v2) | sets `status`, `decision`, writes `## CEO` | creates a new file; never changes it afterwards |
| `mandate.yml` (v3) | reads and follows it; never writes it | writes it whenever you change your mandate |

Meatproxy's writes are atomic (a temporary file renamed over the original), never touch a
decision that is no longer `open`, and never overwrite an idea file. Meatproxy creates no
other files in a factory: switching a project on as a factory writes nothing.

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
kind: ship            # plan | ship | store | promote | stop | other
gate: ship            # plan | ship | store | always-ask
status: open          # open | yes | no | expired | withdrawn
workstream: W-002     # optional
replaces: null        # the decision this one replaces after a "no"
asked: 2026-11-16T07:05:00+01:00
answered: null        # set when status leaves open
---

## Why
## Evidence
## On yes
## On no
## Answer
```

Required: `id`, `title`, `status`. An `open` decision counts in Needs you. Meatproxy writes
`status: yes|no`, `answered` (ISO 8601 with offset) and your note under `## Answer`.

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
