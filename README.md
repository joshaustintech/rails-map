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

- macOS or Linux on a supported CPU
- Spinel `a753180b964c9f077e26e8b756f261b9d2339c91` to build the CLI
- Ruby 3.4.9, Prism 1.9.0, Flay 2.14.4, and Reek 6.5.0 for development checks

The CLI is a native executable. It does not need Ruby, Prism, or Rails at run time.

## Build and install

Install Git, Make, a C compiler, curl, tar, and Ruby build libraries. On macOS,
install Xcode Command Line Tools (`xcode-select --install`) and Homebrew Ruby
build libraries (`brew install openssl@3 readline libyaml`). On Linux, use the
package command for your distro. Set a UTF-8 locale before you build Spinel on
Linux: `export LC_ALL=C.UTF-8`.

Install these packages for your distro. Run one command.

Debian or Ubuntu:

```sh
sudo apt-get update
sudo apt-get install -y build-essential diffutils git curl tar libssl-dev zlib1g-dev libyaml-dev libreadline-dev libffi-dev libgdbm-dev libncurses-dev
```

Arch Linux:

```sh
sudo pacman -S --needed base-devel diffutils git curl tar openssl zlib libyaml readline libffi gdbm ncurses
```

Fedora:

```sh
sudo dnf install -y gcc make diffutils git curl tar openssl-devel zlib-devel libyaml-devel readline-devel libffi-devel gdbm-devel ncurses-devel
```

openSUSE Leap or Tumbleweed:

```sh
sudo zypper install -y gcc make diffutils git curl tar libopenssl-devel zlib-devel libyaml-devel readline-devel libffi-devel gdbm-devel ncurses-devel
```

Choose one Ruby manager. On macOS, install rbenv with Homebrew. On Linux,
install rbenv and its ruby-build plugin from GitHub. Then enable rbenv in your shell. Use zsh on macOS and Bash on Linux:

```sh
# macOS zsh
brew install rbenv ruby-build
echo 'eval "$(rbenv init - zsh)"' >> "$HOME/.zshrc"
source "$HOME/.zshrc"

# Linux Bash
git clone https://github.com/rbenv/rbenv.git "$HOME/.rbenv"
mkdir -p "$HOME/.rbenv/plugins"
git clone https://github.com/rbenv/ruby-build.git "$HOME/.rbenv/plugins/ruby-build"
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> "$HOME/.bashrc"
echo 'eval "$(rbenv init - bash)"' >> "$HOME/.bashrc"
source "$HOME/.bashrc"

# macOS and Linux, after installing rbenv
rbenv install 3.4.9
rbenv shell 3.4.9
```

Or install Mise. On macOS, use Homebrew. On Linux, use the official installer.
Activate it in your shell, then install Ruby 3.4.9:

```sh
# macOS
brew install mise

# Linux
curl https://mise.run | sh

# macOS and Linux
# Linux Bash
echo 'eval "$(mise activate bash)"' >> "$HOME/.bashrc"
source "$HOME/.bashrc"

# macOS zsh
echo 'eval "$(mise activate zsh)"' >> "$HOME/.zshrc"
source "$HOME/.zshrc"

# macOS and Linux
mise use -g ruby@3.4.9
```

Install Prism first. Spinel needs it to generate compiler tables. Then build the
pinned Spinel compiler from source. This command works on macOS and Linux. It
installs Spinel into `$HOME/.local/bin`:

```sh
gem install prism -v 1.9.0 --no-document
```

```sh
mkdir -p "$HOME/src"
git clone --no-tags https://github.com/matz/spinel.git "$HOME/src/spinel"
git -C "$HOME/src/spinel" checkout a753180b964c9f077e26e8b756f261b9d2339c91
git -C "$HOME/src/spinel" config core.abbrev 8
make -C "$HOME/src/spinel" deps
make -C "$HOME/src/spinel"
mkdir -p "$HOME/.local/bin"
cp "$HOME/src/spinel/bin/spinel" "$HOME/.local/bin/spinel"
```

Add `$HOME/.local/bin` to `PATH`. Install the pinned development gems, then
build rails-map with Spinel optimization level 3:

```sh
gem install flay -v 2.14.4 --no-document
gem install reek -v 6.5.0 --no-document
bin/build
```

The build writes `build/rails-map`. Install it with:

```sh
mkdir -p "$HOME/.local/bin"
cp build/rails-map "$HOME/.local/bin/rails-map"
```

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
