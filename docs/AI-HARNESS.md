# AI Harness

## Work loop

1. Read this guide and the ADR that covers the change.
2. Check the reference output and compiled output on `fixtures/rails61`.
3. Keep parallel edits in separate files. Assign each shared source file to one worker.
4. Add or update a case in `fixtures/navigation_tasks.json` when user-visible navigation evidence changes.
5. Run the focused test while editing. Run `bin/verify` before completion.
6. Report command output, benchmark ratios, and any limit that remains.

Every new commit must name Josh Austin (`83935880+joshaustintech@users.noreply.github.com`) as author and include `Co-authored-by: Codex <codex@openai.com>`. `bin/verify` checks the current commit. Existing commit metadata stays unchanged because correcting it changes commit hashes.

Do not change reference output rules after porting starts unless an ADR records the reason and golden tasks cover the change. Verify corrected rules against every pinned repository.

## Evidence rules

- Compare canonical JSON from the reference and compiled CLI.
- Read model constants from Ruby code inside ERB tags. Ignore template text and ERB comments.
- Keep task fixtures offline and deterministic.
- Report source paths relative to the scanned project. Include a source line for every relationship.
- Mark behavior unresolved when static source does not prove the route, view, model, or association.
- Treat a mutation as killed only when the compiled CLI fails or its JSON changes. Run isolated mutants concurrently.
- Time only each CLI process. Parse and compare its JSON after the timed interval.

## Completion

The implementation is ready when `bin/verify` passes on the pinned repositories. The gate requires exact canonical output and a Spinel median ratio no greater than 0.20 for every repository and command. It also checks pinned tool versions, mutation strength, source quality, and a native macOS build.
