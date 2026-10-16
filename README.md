# rails-map

rails-map reads Rails source files. It does not start Rails or run app code.
Use it to find routes, actions, views, models, and model links. It also lists
source patterns it cannot resolve.

## Requirements

- macOS on Apple silicon
- Spinel compiler to build the CLI
- Ruby, Prism, Flay, and Reek to run the development checks

The CLI is a native executable. It does not need Ruby, Prism, or Rails at run
time.

## Build and install

Put `spinel` on your `PATH`, then build the CLI:

```sh
bin/build
```

The build writes `build/rails-map`. Copy it to a directory on your `PATH`:

```sh
mkdir -p "$HOME/.local/bin"
cp build/rails-map "$HOME/.local/bin/rails-map"
```

Add `$HOME/.local/bin` to your `PATH` if needed.

## Use

Run the command from a Rails project. The current directory is the default
project root. Use `--root` to select another project.

```sh
rails-map map --json
rails-map inspect UsersController#show --json
rails-map map --root fixtures/rails61 --json
```

`map` lists all supported navigation facts. `inspect` limits the result to
one controller action. JSON has a `schema_version` field. Paths are relative
to the project root. Each route, view, model, or association fact includes
source evidence. Confidence is `direct`, `conventional`, or `unresolved`.
The `unresolved` list shows dynamic or unsupported patterns. Static analysis
cannot prove behavior created at Rails run time.

## Verify

`bin/verify` runs only on macOS. It requires a clean checkout and the pinned
corpus. Fetch the corpus, then run the gate:

```sh
bin/fetch-corpus
bin/verify
```

The gate builds a native CLI. It runs the behavior, mutation, Flay, and Reek
checks. It then compares canonical JSON and times `map` and `inspect` on all
three pinned repositories. Each command gets one warm-up and 30 timed runs.
JSON parsing and compilation are outside the timed interval. Every timed
result must match the CRuby and Prism reference. Each Spinel median must be
at most 0.20 of the reference median. Tool versions and repository commits
must match `bench/baseline.json` and `bench/repositories.lock`.

The 2026-10-16 run used CRuby 3.4.9, Prism 1.9.0, and Spinel
`a753180b` on macOS arm64. The six Spinel-to-reference ratios were 0.0910
and 0.0816 (map and inspect) for the sample app, 0.1985 and 0.1779 for CASA,
and 0.1769 and 0.1733 for Discourse. These results apply to the pinned
checkouts. They do not show performance on every Rails project.
