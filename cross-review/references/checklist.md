# What to check in a backend review

Don't comment on style, formatting, imports, PSR-12 naming, or pint/phpstan/phpmd findings.

## Logic

- The code solves the task from the branch/description, not a neighbouring refactoring.
- Empty input, null, a repeated request, a race, an already processed entity.
- Payments/refunds/callbacks: idempotency, provider retries, timeout, partial success, rollback.
- Public API and queue contracts: no field removed or retyped without versioning/compatibility.
- Existing scenarios don't change behaviour without a reason in the task.

## Database

- Migrations: locking a large table, drop column, rename, `change()` without doctrine/dbal, a data migration in the
  same migration as the schema change.
- New WHERE/JOIN/ORDER BY without an index.
- N+1 in loops, resources, listeners, jobs.
- Several writes that must succeed together, without a transaction.
- Soft delete / unique: creating the same entity again.

## Security

- No auth/policy/gate check on a new endpoint or a changed action.
- The request doesn't validate input; request data goes straight into a query/update.
- `$request->all()` / uncontrolled `fill` / `update` with `$guarded = []`.
- Secrets, tokens, personal data in logs.
- An ID from the client without checking that the entity belongs to the user/shop.

## Integrations and jobs

- An external HTTP call in the request flow without a timeout/retry/job.
- A job without idempotency when `tries > 1`.
- A cache is written but never invalidated.
- An event/listener changes money, stock or statuses without protection against repeats.

## When to use blocker

Only if without a fix money, data or access can be lost, a contract or production can break. Disagreeing on taste is
not a blocker.

## When question, not blocker

It's unclear why something is synchronous, why there is no job, which invariant holds. By answering, the author
documents the decision.
