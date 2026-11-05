# Self-check before sending the PR

Don't spend time on style (pint / phpstan / phpmd / PSR-12).

Look for what the reviewer would mark `blocker:`:

- repeated processing of a payment/refund/callback;
- no auth on a new action;
- `$request->all()` / mass assignment;
- a migration that locks a large table, or no index for a new query;
- N+1;
- several writes without a transaction;
- a public API change without compatibility (especially an API used by other services or a mobile app — that is High);
- a High-risk PR without edge cases and failure scenarios in the description (§7.1 of the process);
- uncommitted files the author considers part of the PR.

Found a blocker — fix it right away, don't leave it to the reviewer.
