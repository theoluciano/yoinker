# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Yoinker is a Rails 8 web app that lets designers search for Figma component usages across teams and projects. It queries the Figma REST API to scan files and find where specific components are used.

## Tech Stack

- Ruby 3.3.6, Rails 8.0, SQLite3, Puma, Propshaft (asset pipeline)
- Views use Slim templates (`.html.slim`)
- HTTP client: HTTParty (for Figma API calls)
- CSS: Plain CSS + `@sakun/system.css` CDN for retro OS window aesthetic
- JavaScript: Vanilla JS only (no bundler, no framework)
- Background jobs/caching/cable: Solid Queue, Solid Cache, Solid Cable (all database-backed)
- Deployment: Kamal (Docker-based) with Thruster

## Commands

```bash
# Setup & run
bin/setup              # Install deps, prepare DB, clear logs
bin/dev                # Start dev server (localhost:3000)

# Testing
bin/rails test                              # Unit/integration tests
bin/rails test test:system                  # System tests (requires Chrome)
bin/rails db:test:prepare test test:system  # Full suite (as in CI)

# Linting & security
bin/rubocop            # RuboCop linter (rubocop-rails-omakase style)
bin/rubocop -a         # Auto-correct safe offenses
bin/brakeman --no-pager  # Security scan
bin/importmap audit      # JS dependency audit

# Database
bin/rails db:prepare   # Create and migrate
bin/rails db:migrate   # Run pending migrations
```

## Environment Variables

Create `.env` in project root (loaded by dotenv-rails in dev/test):

- `FIGMA_PERSONAL_TOKEN` — Figma personal access token
- `TEAM_IDS` — JSON object mapping team display names to Figma team IDs, e.g. `{"Team Name": "12345"}`

## Architecture

**Single-page, single-controller app.** One controller (`FigmaSearchController#index`), one service object, one view. No custom database models — SQLite exists only for Solid Queue/Cache/Cable.

**Key files:**

- `app/controllers/figma_search_controller.rb` — Handles search form and results display
- `app/services/figma_scanner.rb` — All Figma API logic. Includes HTTParty, targets `api.figma.com/v1`
- `app/views/figma_search/index.html.slim` — Single-page UI with search form and collapsible results
- `config/routes.rb` — Root routes to `figma_search#index`

**FigmaScanner service (`app/services/figma_scanner.rb`):**

- `FigmaScanner.fetch_projects_for_known_teams` (class method) — Reads `TEAM_IDS` env var, fetches projects for each team
- `FigmaScanner#find_component_matches` (instance method) — Fetches all files in a project, spawns Ruby threads to scan each file in parallel via Figma `/files/:key` endpoint
- `FigmaScanner#search_nodes_recursively` — Recursively walks the Figma document tree looking for `INSTANCE` nodes matching the component name (case-insensitive exact match)
- File-based caching in `tmp/` — API responses cached as `tmp/figma_cache_*.json` and `tmp/figma_project_*_files.json` with 24-hour TTL

**Data flow:** User selects a project and enters a component name → controller calls `FigmaScanner` → service fetches file list (cached 24h) → threads scan each file's document tree → results grouped by file with deep links back to Figma.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on PRs and pushes to `main`:

| Job | Command |
|---|---|
| `scan_ruby` | `bin/brakeman --no-pager` |
| `scan_js` | `bin/importmap audit` |
| `lint` | `bin/rubocop -f github` |
| `test` | `bin/rails db:test:prepare test test:system` |
