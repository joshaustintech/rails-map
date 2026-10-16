# Triage labels

Open, actionable issues use `ready-for-agent`. Resolve safe uncertainty without waiting for human input. Record decisions that affect architecture or scope in `docs/adr/`.

| Role | Label | Meaning |
| --- | --- | --- |
| `needs-triage` | `ready-for-agent` | Agent investigates and makes a safe decision. |
| `needs-info` | `ready-for-agent` | Agent proceeds with a documented assumption where safe. |
| `ready-for-agent` | `ready-for-agent` | Agent can work the issue. |
| `ready-for-human` | `ready-for-agent` | Agent owns the next safe step; do not wait for a human label. |
| `wontfix` | `wontfix` | Work will not be done. |

Ticket `Blocked by` links record technical sequencing only. Work the unblocked frontier. Do not create a human-gated state for this CLI project.
