# Developer entrypoints for Saleor.
#
# Prerequisites (see AGENTS.md "Running tests" and CONTRIBUTING.md):
#   - Python 3.12 and uv (https://docs.astral.sh/uv/) — `uv sync --group dev` installs everything
#   - A reachable PostgreSQL server; tests do NOT support SQLite
#   - DATABASE_URL pointing at it, e.g.
#       export DATABASE_URL=postgres://saleor:saleor@127.0.0.1:5432/saleor
#
# Inside a git worktree, prefer running these via the worktree's container
# stack instead (.worktree-container/compose.sh) — see AGENTS.md.

.DEFAULT_GOAL := help
.PHONY: help test test-file lint format

help:  ## Show available targets
	@echo "test      run the full test suite (PostgreSQL required via DATABASE_URL)"
	@echo "test-file run a single test file, e.g. make test-file F=saleor/order/tests/test_order.py"
	@echo "lint      run ruff checks (lint + format check)"
	@echo "format    apply ruff formatting and safe fixes"

test:  ## Run the full test suite
	uv run pytest --reuse-db

test-file:  ## Run one test file: make test-file F=saleor/path/to/test_x.py
	uv run pytest -n0 --reuse-db $(F)

lint:  ## Run ruff check + format check (same scope as CI's ruff hooks)
	uv run ruff check --exclude .semgrep --exclude vendored .
	uv run ruff format --check --exclude .semgrep --exclude vendored .

format:  ## Apply ruff format + safe autofixes
	uv run ruff format --exclude .semgrep --exclude vendored .
	uv run ruff check --fix --exclude .semgrep --exclude vendored .
