# ADR 0010: Enforce the measured fivefold release target

The original 10% speedup gate no longer matched the product target. After all six pinned map and inspect cases measured at or below a 0.20 Spinel-to-CRuby + Prism median ratio, the release gate now enforces that limit per case, checks canonical JSON on every timed run, and rejects toolchain or corpus drift against the recorded baseline. The gate runs on macOS because the shipped CLI is a native macOS executable.
