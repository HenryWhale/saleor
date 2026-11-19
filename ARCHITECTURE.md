# Saleor Architecture Map

A one-page map of the codebase for humans and coding agents: what lives where,
the request/task flows worth knowing, and where cross-cutting configuration is
defined. It describes **where things are**, not the rules — norms live in
[AGENTS.md](AGENTS.md), decisions in [docs/adr/](docs/adr/), workflow in
[CONTRIBUTING.md](CONTRIBUTING.md).

Reading order for a new contributor: README → this file → AGENTS.md → the ADRs
for the area you touch.

## Deployment model (why the code looks like this)

Saleor runs as many identical pods (web + Celery workers) behind a load
balancer against a shared PostgreSQL and Redis/Valkey. Consequences that shape
the code: no in-process state as source of truth, atomic DB operations over
check-then-act, `select_for_update` with a consistent lock order, background
work scheduled after commit, tasks idempotent. Details and patterns:
AGENTS.md *Deployment model* and *Concurrency and Thread Safety*.

## Module map (`saleor/`)

| Area | Apps / modules | Responsibility |
|---|---|---|
| API layer | `graphql/` | GraphQL schema for storefront and dashboard. Mutations do input validation and orchestration **only**; resolvers reuse dataloaders. `graphql/views.py` renders the API view and the playground (`templates/graphql/playground.html`). |
| Cross-cutting core | `core/` | Base models, permission primitives, token generators (`core/tokens.py`), tracing (`core/tracing.py`), event dispatch (`core/utils/events.py`), HTML/EditorJS cleaners (`core/cleaners/`, `core/editorjs/`), plugins manager. |
| Commerce domain | `order/`, `checkout/`, `product/`, `discount/`, `giftcard/`, `invoice/`, `shipping/`, `tax/`, `thumbnail/` | Business logic for the sell side. Each app owns its models, `utils/`, Celery `tasks.py`, and `lock_objects.py` where row locking is needed (e.g. `order/lock_objects.py`). |
| Payments | `payment/` | Payment/transaction domain. `payment/lock_objects.py` holds the row-lock querysets; app integration points live in `plugins/`. |
| Identity & tenancy | `account/`, `auth/`, `permission/`, `channel/`, `site/` | Users, auth tokens, permission enums, channels, and multi-site resolution (`Site.objects.get_current()` — never `settings.SITE_ID`). |
| Content & config | `page/`, `menu/`, `attribute/`, `translations/`, `seo/`, `csv/` | Editable storefront content, attribute system, translations, SEO. |
| Platform glue | `app/`, `webhook/`, `plugins/` | Third-party apps, webhook payloads & delivery, built-in plugins (payment providers, etc.). |
| Infra | `settings.py`, `celeryconf.py`, `urls.py`, `asgi/`, `schedulers/` | Django settings, Celery config and queues, URL routing, ASGI entry. Tests live beside each app under `tests/` with fixtures in `tests/fixtures/`. |

Layering rule (enforced by review): non-GraphQL code must never import from
`graphql/`. When a domain module needs a helper, the helper moves into the
domain and GraphQL imports it — never the reverse.

## Flows worth knowing before editing

- **GraphQL mutation** — input validation → domain call inside
  `traced_atomic_transaction()` → `call_event(...)`/`on_commit(...)` for
  side effects. Lock order: lock the aggregate root before its lines (see
  `order/lock_objects.py` and `order/calculations.py:process_order_prices`).
- **Price recalculation** — `order/calculations.py` recomputes totals, then
  locks the order row and only saves if `updated_at` is unchanged, so a
  concurrent mutation wins instead of being overwritten.
- **Celery task** — declared per app in `<app>/tasks.py`, routed by queue
  (`celeryconf.py`). Data migrations self-chain on the
  `DATA_MIGRATIONS_TASKS_QUEUE_NAME` queue; see AGENTS.md *Data Migrations*.
- **Webhook event** — always dispatched via
  `saleor.core.utils.events.call_event`, which batches and defers until
  commit.

## Where configuration lives

| Concern | Location |
|---|---|
| Django settings, DB/Redis URLs, env vars | `saleor/settings.py` (reads `DATABASE_URL` etc. via `dj_database_url`) |
| EditorJS / rich-text cleaner defaults & env overrides | `saleor/core/cleaners/editorjs.py` (`EditorJsCleanerSettings`, env: `EDITOR_JS_ALLOWED_ATTRIBUTES`, `EDITOR_JS_ALLOWED_ATTRIBUTE_VALUES`, `EDITOR_JS_LINK_REL`), instantiated as `EDITOR_JS_CLEANER_PREFS` in `settings.py` |
| File upload validation | `saleor/graphql/core/validators/file.py` |
| pytest configuration | `pyproject.toml` `[tool.pytest]` (xdist, `--ds=saleor.tests.settings`, socket restrictions) |
| Lint / type checks | `.pre-commit-config.yaml` (ruff, mypy, semgrep; excludes `.semgrep/`, `vendored/`) |
| Dev entrypoints | `Makefile` (`make test`, `make test-file F=…`, `make lint`) |

## Decisions, not details

Architecture- and domain-level decisions are recorded as ADRs in
`docs/adr/` — check the ones tagged for your area before changing a
long-standing behavior. The glossary (`CONTEXT.md`) is created lazily by the
domain-modeling skill; see `docs/agents/domain.md`.
