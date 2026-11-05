# Resolving conflicts without losing functionality

ours = the current feature branch (the task). theirs = the master/develop being merged in (production).

Forbidden for application code: `git checkout --ours FILE` and `--theirs FILE` on a whole file. That throws one side away.

## Order of work on a file

1. Read the file with the `<<<<<<<`, `=======`, `>>>>>>>` markers.
2. Understand what the task added and what came from the base (a fix, a contract, a new field, a migration).
3. Combine **both** behaviours unless they are mutually exclusive.
4. Both sides changed one method: embed the base's fix into the task logic; don't roll back the task and don't drop the fix.
5. Remove the markers. The file must open/parse.
6. `git add` only after that.

## By file type

| File | How |
| --- | --- |
| Migrations | Keep **all** files from both sides. Never delete the base's migrations. A conflict inside one migration that may already have run in production — prefer theirs and carry the task's change in a new migration if the old one can't be changed safely |
| `composer.json` / `package.json` | Merge the dependencies. Then do **not** hand-merge the lock file |
| `composer.lock` / `package-lock.json` / `yarn.lock` | After the json: `composer update --lock` or `composer install` / `npm install`. Take a lock file whole from one side only if our side didn't change the json |
| routes, providers, Nova | Register both the task's routes/resources and the new ones from the base |
| Policy / Request / DTO | Keep the base's new rules and the task's fields |
| Tests | Keep the tests of both sides; fix the failing ones for the combined behaviour |
| `.env.example` | Merge the keys |
| CI, pint.json, phpstan | Never drop stricter settings from the base |
| Binaries, images | Don't guess: stop and ask |

## Check after combining

- No markers: `rg '<<<<<<<|=======|>>>>>>>' --glob '!vendor/**'`
- `git diff --name-only --diff-filter=U` is empty
- The task's behaviour is in place (methods, endpoints, the task's migrations)
- The base's behaviour is in place (fixes, contracts, new mandatory things from production)
