# Backend Cross Review Process

The backend cross-review process the skills follow. It is generic: the team's projects, reviewers, issue tracker URL
and output language are set locally in `~/.claude/review-team.md` (template: `team.example.md` in the skills repository).

## 1. Why cross-review

- catch business-logic bugs before merge;
- spread knowledge of the codebases so anyone can pick up a task in a neighbouring project;
- share a common sense of task complexity and estimate more accurately;
- stop depending on a single person per project (bus factor).

## 2. Scope

All of the team's backend repositories. The project list lives in `review-team.md`.

## 3. When a PR is ready to merge

Every backend PR is reviewed by at least one developer who did not write it. Merge when:

- there is at least one approve;
- no `blocker:` is open;
- every discussion is resolved or has an agreement.

## 4. Risk level

### 4.1. Low

Error and validation messages, small bug fixes without business-logic changes, DTO / request / response changes,
refactoring that keeps behaviour.

- review by the end of the next working day;
- merge after approve; self-merge only under section 10.

### 4.2. Medium

New business logic, endpoint changes, queues and jobs, external integrations, orders, notifications.

- review by the end of the next working day;
- merge after approve.

### 4.3. High

Payments, refunds, invoices; authentication and permissions; bulk operations; changes to an API used by other
services or by a mobile app; schema changes of large tables; background processes doing bulk processing.

- merge after approve;
- for payments and refunds the PR description must state what happens on a repeated call, an error and a timeout.

## 5. Who reviews

The reviewer is picked from the project's list in `review-team.md`. The author never reviews their own PR.

## 6. Time budget

Review time is limited: about half an hour a day per person. Therefore:

- PRs are small — up to 300 lines, excluding generated and lock files;
- the PR description gives enough context without reading the whole project;
- the reviewer focuses on logic and security; style is checked by CI (pint, phpstan, phpmd, etc.).

## 7. PR requirements

### 7.1. Description

```
## What changed
A short summary of what was done.

## Why
Link to the task and one sentence of business context.

## How to test
Steps or curl requests.

## Risks
What is affected: DB / payments / refunds / auth / integrations / queues / cache. Nothing — "none".

## Migrations
Yes / no.
```

For a High-risk PR the author also describes edge cases and failure scenarios.
A PR without a description may be returned to the author without review.

### 7.2. Size

- up to 300 lines — good;
- 300–500 — acceptable;
- over 500 — the author explains why the PR cannot be split.

## 8. Reviewer checklist (in priority order)

### 8.1. Logic

- Does the code solve the task?
- Edge cases: duplicates, empty data, concurrent requests.
- Payments and refunds: repeated call, timeout, partial execution.
- Backward compatibility of the public API.
- Existing scenarios don't change behaviour without a reason.

### 8.2. Database

- Migrations are safe for large tables.
- No N+1 queries.
- New queries have indexes.
- Related writes run in one transaction when they must be atomic.

### 8.3. Security

- Permissions are checked.
- Input is validated.
- No mass assignment.

### 8.4. Code

- Clear names, no duplication, no unnecessary complexity.

Don't review style — that's CI's job.

## 9. Comments

| Prefix | Meaning |
| --- | --- |
| `blocker:` | merge is impossible without a fix |
| `question:` | a question for understanding |
| `suggestion:` | a proposal; does not block merge |
| `nit:` | a trifle |

Examples:

```
blocker: A repeated webhook from the provider creates a second payment: nothing
checks `external_id`. The customer is charged twice.

question: Why `lockForUpdate()` outside a transaction? The lock is released
right after the query and protects nothing.

suggestion: This query could become a model scope — it is repeated
in three places.

nit: Typo in the variable name `recieved`.
```

Questions are welcome: by answering, the author documents the decision for everyone.

## 10. Self-merge and post-review

Allowed only for a production incident / hotfix, a critical bug fix, or an urgent change when no reviewer is available.
The author then:

1. leaves a PR comment with the reason and the risk area;
2. creates a post-review task;
3. gets the post-review done within the next working day.

```
Self-merged: hotfix, production incident.
Risk area: payment provider webhook handling.
Post-review required.
```

## 11. Workflow

Branch → PR → description from the template → reviewer → CI → comments → the author fixes or argues →
approve and green CI → merge.
