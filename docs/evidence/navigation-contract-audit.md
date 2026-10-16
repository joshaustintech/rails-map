# Navigation contract audit

Date: 2026-10-16

## Hand-reviewed facts

`fixtures/navigation_tasks.json` holds expected CLI facts checked against the
source in `fixtures/rails61`. It covers explicit and conventional route
confidence, controller and model source lines, direct and conventional view
candidates, associations, and unresolved dynamic route, render, and association
behavior. Both `map` and action-scoped `inspect` are exercised through the
compiled CLI. Expected rows were read from the fixture source, not generated
from the CRuby + Prism reference.

## Pinned corpus observations

The audit used the three sparse checkouts and exact commits in
`bench/repositories.lock`. Current `map` output reports:

| Repository | Actions | Routes | Views | Models | Associations | Unresolved rows |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| sample_rails_app_7th_ed | 25 | 29 | 22 | 4 | 8 | none |
| casa | 239 | 251 | 165 | 63 | 166 | 20 dynamic renders, 4 dynamic association targets, 11 dynamic routes, 4 unsupported generators, 1 unsupported option |
| discourse | 896 | 855 | 53 | 314 | 648 | 10 dynamic renders, 10 dynamic association targets, 163 dynamic routes, 23 unsupported generators, 992 unsupported options, 14 unsupported scopes |

The benchmark targets were checked against their checked-out source. These
examples show what the source proves and what the CLI returned:

| Repository | Source reviewed | Expected fact | CLI result |
| --- | --- | --- | --- |
| sample_rails_app_7th_ed | `config/routes.rb:18`, `app/controllers/relationships_controller.rb:4` | `resources :relationships` includes `create`; action has conventional template | `POST /relationships` and `app/views/relationships/create.turbo_stream.erb`, both conventional, with matching evidence lines |
| casa | `config/routes.rb:100`, `app/controllers/reports_controller.rb:5` | `resources :reports, only: [:index]`; `ReportsController#index` | `GET /reports` and `app/views/reports/index.html.erb`, both conventional, with matching evidence lines |
| discourse | `config/routes.rb:1531`, `app/controllers/topics_controller.rb:73`, `app/models/topic.rb:249` | Explicit `GET t/:id` route to `topics#show`; conventional `posts` association | `GET /t/:id` direct at line 1531; `app/views/topics/show.html.erb` conventional at line 73; `Topic.posts` → `Post` conventional at line 249 |

These examples validate selected source facts, not every row in each corpus
output. CASA's `ReportsController#index` also reports `dynamic_render` at line
8 for `render layout: "casa_app"`. `Admin::UsersController#dynamic` in the
fixture reports the separate `layout_only` action's line 16 as dynamic render
uncertainty. These are concrete uncertainty-classification gaps for issue 02.
Discourse's `TopicsController#show` returns nine route candidates; only the
`/t/:id` source row above is independently checked here.

This audit records these rows as known mismatches; its contract tests do not treat
them as correct behavior. Issue 02 owns changing scanner behavior and adding
passing negative assertions for these cases. This keeps the audit ticket from
silently blessing a false positive or mixing audit work with the fix.

## Gaps and limits

- Automated independent expected facts cover the small Rails 6.1 fixture. The
  source/output comparisons above hand-check selected pinned corpus facts, not
  full repository output. Oracle parity alone cannot validate every output row.
- The sparse corpus reports many unsupported or dynamic route forms, especially
  Discourse route options. Their runtime meaning is outside this static audit.
- The corpus and fixture do not establish complete Rails-version or plugin
  coverage. They do not prove runtime-generated routes, views, or associations.
- The sample corpus has no unresolved rows, which does not prove it has no
  dynamic behavior outside the sparse checkout.

Issue 02 owns investigating these source patterns and adding independently
reviewed expected facts before changing scanner behavior.
