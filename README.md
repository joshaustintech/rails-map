# rails-map

rails-map scans Rails source files. It does not start Rails.

It maps routes, controller actions, views, models, and model associations. It also reports source patterns that it cannot resolve. Each fact has a relative path and a line number.

## Requirements

- macOS on Apple silicon
- Ruby 3.4 or later for development checks
- Spinel compiler
- Prism, Flay, and Reek for `bin/verify`

Install the Ruby tools with:

```sh
gem install prism flay reek
```

The installed CLI is a native executable. It does not need Ruby, Prism, or Rails at run time.

## Build

Install the Spinel compiler. Make sure `spinel` is on your `PATH`. Then run:

```sh
bin/build
```

The executable is `build/rails-map`.

## Install

Build the executable. Then copy it to a directory on your `PATH`:

```sh
mkdir -p "$HOME/.local/bin"
cp build/rails-map "$HOME/.local/bin/rails-map"
```

Add `$HOME/.local/bin` to your `PATH` if needed.

## Use

Run commands from a Rails project. The current directory is the default root.
Use `--root` to scan another project.

```sh
rails-map map --json
rails-map inspect UsersController#show --json
rails-map map --root ../shop --json
```

The JSON has a `schema_version` field. Paths are relative to the project root. Confidence is `direct`, `conventional`, or `unresolved`. The `unresolved` list names dynamic or unsupported behavior.

## Verify

Install the development tools in Requirements. Fetch the pinned repositories,
then run the full check:

```sh
bin/fetch-corpus
bin/verify
```

The benchmark runs each command once before timing it. It then runs the
command 30 times. It compares canonical JSON after every run. JSON parsing
and compilation are outside the timed interval. Spinel must be at least
10 percent faster for every repository and command.

To capture a new CRuby and Prism baseline, run:

```sh
RAILS_MAP_CORPUS=/path/to/rails-map-corpus ruby bench/run.rb --record-baseline
```

This command updates `bench/baseline.json`. It records runtime versions and repository commit SHAs.

The check builds the CLI, compares it with the CRuby and Prism reference,
runs behavior and mutation checks, and checks Flay and Reek. It also runs the
pinned repository benchmarks. The CRuby and Prism timing baseline is in
`bench/baseline.json`. See `AGENTS.md` and `docs/adr/` for project rules and
design decisions.
