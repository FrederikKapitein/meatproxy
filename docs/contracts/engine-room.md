# Meatproxy Server room contract

**Name:** `meatproxy-engine-room` · **Current version:** 1 · **Owner:** this repository

The Server room's DevOps agent watches your servers and sites and may work on them
semi-autonomously, as far as each server allows. This document is the contract between the
agent and Meatproxy. Anything that is not in it is not agreed.

| Version | Date | Adds |
| --- | --- | --- |
| 1 | 2026-11-15 | The workspace, alerts, the ops tool with per-server autonomy, decisions, the journal, the heartbeat run. |

## The workspace

The agent works in a folder that belongs to Meatproxy:
`~/Library/Application Support/Meatproxy/engine-room/`. Nothing in it is in a repository.

```
engine-room/
├── contract.yml          meatproxy-engine-room, version 1            (Meatproxy writes)
├── servers.json          your servers: name, kind, autonomy, sites,
│                         and what the last checks saw                (Meatproxy writes)
├── .claude/settings.json the agent's allowlist: the ops tool only    (Meatproxy writes)
├── alerts/               A-NNNN-<slug>.md, one per alert              (Meatproxy creates; the agent handles)
├── decisions/            D-NNNN-<slug>.md, the agent's yes/no questions (the agent creates; Meatproxy answers)
└── journal/              YYYY-MM-DD.md per run (-2, -3 …), and actions.log (Meatproxy's record of every ops action)
```

## Who writes what

| File | The agent | Meatproxy |
| --- | --- | --- |
| `contract.yml`, `servers.json`, `.claude/settings.json` | reads | writes before every run and after every check |
| `alerts/` | sets `status: handled` and writes `## Agent` | creates one file per alert, never changes it afterwards |
| `decisions/` | creates, withdraws, expires (format of the factory contract) | writes your answer into an `open` decision only |
| `journal/YYYY-MM-DD.md` | writes | reads the latest |
| `journal/actions.log` | reads | appends one line per ops action |

## Alerts: `alerts/A-NNNN-<slug>.md`

```markdown
---
id: A-0003
title: api-01 needs a look
kind: warn            # down | warn | recovered
subject: api-01       # a server's name, or a site's host
status: open          # open | handled
at: 2026-11-15T22:40:00+01:00
---

disk 91% full

## Agent
What the agent found and did.
```

A bad state is an alert only after two checks in a row; it alerts again only when it gets
worse, and once more when it is fine again (`recovered`).

## The ops tool

The agent reaches servers only through the ops tool, `Meatproxy --ops`; never with ssh
itself. `Meatproxy --ops list` prints the servers, what each allows, and the actions.

```
Meatproxy --ops <server> <action> [argument]
```

| Action | Kind | Runs on the server |
| --- | --- | --- |
| `status` | read | `uptime; df -h /; free -m` |
| `disk` | read | `df -h` |
| `memory` | read | `free -m` |
| `services` | read | failed units, and the running services |
| `docker` | read | `docker ps -a` (name, status, image); through the sudo rule below when the account has no Docker access |
| `logs <unit>` | read | the last 200 journal lines of a unit |
| `container-logs <name>` | read | the last 200 lines of a container; through the sudo rule below when needed |
| `restart <unit>` | safe fix | `sudo -n systemctl restart <unit>`, then its state |
| `restart-container <name>` | safe fix | `docker restart <name>` |
| `docker-prune` | safe fix | images and build cache older than 7 days |
| `journal-vacuum` | safe fix | `sudo -n journalctl --vacuum-time=7d` |

What a server allows is set in Meatproxy per server and checked by the tool, not by the
agent:

| Autonomy | Read actions | Safe fixes |
| --- | --- | --- |
| Leave alone (`off`) | refused | refused |
| Diagnose, ask (`observe`) | yes | refused: file a decision |
| Safe fixes (`safeFixes`) | yes | yes |

An argument is a unit or container name (letters, digits, `@ . _ : -`, at most 80). Anything
else is refused. The tool connects with ssh in batch mode with your own keys and agent;
it asks for no password and stores none. Every action, allowed or refused, is a line in
`journal/actions.log`.

## On the servers

The ops tool reads Docker directly when the login account may. Otherwise it uses `sudo -n` with a rule that allows
these two read commands and nothing else of Docker. The account is never put in the `docker` group: that is root
in all but name. On each server the rule is one file, `/etc/sudoers.d/meatproxy-docker-read` (mode 0440, checked
with `visudo -cf`), for the account the ops tool logs in as:

```
deploy ALL=(root) NOPASSWD: /usr/bin/docker ps -a --format *, /usr/bin/docker logs --tail 200 *
```

Check afterwards with `Meatproxy --ops <server> docker`. Installing or changing the rule is server work: it goes
through the devops repository, not through the ops tool. An account that already has passwordless sudo for
everything needs no rule (the reads work as they are); the narrow rule is for a login without it, such as a
dedicated ops account. What the agent may run stays limited by the ops tool's fixed actions either way.

## Decisions

Same format as the factory contract (`docs/contracts/factory.md`), in `decisions/`. They
appear in Needs you as the Server room's, and Meatproxy writes your answer into them. A
repair the tool refuses becomes a decision: what is wrong, the evidence, and the exact
action the agent wants to take on yes.

## Journal: `journal/YYYY-MM-DD.md`

Three sections, like a factory briefing: `## Briefing` (at most 5 items: health, what it
found, what it fixed), `## Needs you`, `## Done`.

## The run

Meatproxy starts the agent in the workspace on its heartbeat (a daily look round), when an
alert is raised, a few minutes after your answers, and on Run now. Runtime per Meatproxy's
setting: `claude -p` with the workspace's `.claude/settings.json` passed with `--settings`,
or `codex exec -s workspace-write` with network access for the ops tool. The prompt names
this contract and why it woke. The run ends with the journal written and each alert it
looked at handled.
