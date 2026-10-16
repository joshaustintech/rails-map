# rails-map

## Introduction

Rails applications can spread navigation details across routes, controllers,
views, and models. A code search can find text, but it does not show how these
parts connect. Rails console and runtime tools can show runtime behavior, but
they need a working application and may run application code.

rails-map reads source files without starting Rails or running application
code. It links supported routes, actions, views, and models. It also reports
source evidence and patterns it cannot resolve. Use it to inspect a project
when you need a source-based map without running the application. It cannot
prove behavior created at run time.

rails-map reads Rails source files. It does not start Rails or run app code.
Use it to find routes, actions, views, models, and model links. It also lists
source patterns it cannot resolve.

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

## Benchmarked performance

The full gate ran on an Apple M1 Pro MacBook Pro. It compared CRuby 3.4.9 with
Prism 1.9.0 against Spinel `a753180b` on macOS arm64. Each result is the median
of 30 runs after one warm-up. The build time is not included. Each timed result
matched the reference JSON.

| Project | Command | CRuby + Prism | Spinel | Speedup |
| --- | --- | ---: | ---: | ---: |
| Sample Rails app | `map` | 78.312 ms | 6.743 ms | 11.6× |
| Sample Rails app | `inspect` | 79.938 ms | 6.789 ms | 11.8× |
| CASA | `map` | 148.298 ms | 28.891 ms | 5.1× |
| CASA | `inspect` | 143.354 ms | 26.620 ms | 5.4× |
| Discourse | `map` | 1002.203 ms | 175.269 ms | 5.7× |
| Discourse | `inspect` | 962.418 ms | 169.217 ms | 5.7× |

These results apply to the pinned checkouts. They do not show performance on
every Rails project.

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
