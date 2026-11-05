# Team settings for the review skills

Copy to `~/.claude/review-team.md` and fill in your own data. This file is personal and is never committed to the
skills repository: it holds internal URLs and colleagues' names.

Read by `/pr-template` (task link in "Why", reviewer suggestion) and by all review skills (output language).
No file — the skills still work: English output, no task link, no reviewer suggestion.

## Output language

Output language: English

The language of everything the skills write for Bitbucket: PR descriptions, review comments, thread replies.
`English` uses the English PR template headings; `Russian` uses the Russian ones (`Что изменено`, `Зачем`, …).
Any other language keeps the English headings and writes the body in that language.

## Issue tracker

Default URL: https://example.atlassian.net

Task link: `<URL>/browse/<KEY>`.

## Projects and reviewers

The PR author is excluded from the reviewer list.

| Project | Repositories (remote or folder name) | Tracker URL, if not the default | Reviewers in order |
| --- | --- | --- | --- |
| Shop | shop-backend, shop-checkout | | Alice, Bob, Carol |
| Billing | billing-api | https://billing.example.com | Bob, Carol |

## Who is who

To exclude the author, the skill maps a name in the table to `git config user.name`.

| Name in the team | git user.name |
| --- | --- |
| Alice | alice smith |
| Bob | bob jones |
| Carol | carol white |
