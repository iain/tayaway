# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tayaway is a full-stack web application with a Ruby backend API and Vue.js frontend, organized as a pnpm monorepo.

## Commands

All commands run through mise. Key commands:

```bash
mise run dev              # Start frontend (5173) + backend (9292)
mise run test             # All tests (frontend + backend + e2e)
mise run test_backend     # RSpec tests only
mise run test_frontend    # Vitest tests only
mise run test_e2e         # Playwright tests only
mise run lint             # ESLint + Rubocop
mise run typecheck        # vue-tsc + Sorbet
mise run db_migrate       # Run Sequel migrations
mise run db_reset         # Drop, create, migrate database
```

Run single backend test: `cd backend && bundle exec rspec spec/path/to/spec.rb`
Run single frontend test: `cd frontend && pnpm exec vitest run src/path/to/file.spec.ts`

## Architecture

```
frontend/          Vue 3 + TypeScript + Vite + Tailwind CSS
  └── src/api/client.ts    Fetch-based HTTP client (not Axios)
  └── src/pages/           Page components
  └── src/components/      Reusable components

backend/           Ruby + Roda + Sequel + PostgreSQL
  └── app/app.rb           Main Roda app with hash_routes plugin
  └── app/routes/          Route files (auto-loaded)
  └── db/migrations/       Sequel migrations

e2e/               Playwright tests
```

Frontend dev server proxies `/api/*` requests to the backend.

## Code Style Requirements

**Backend (Ruby):**
- Every file must have `# typed: true` (Sorbet sigil) and `# frozen_string_literal: true`
- Use double quotes for strings
- Roda routes use `hash_routes` plugin pattern

**Frontend (TypeScript/Vue):**
- Vue components use `<script setup lang="ts">` syntax
- Tailwind CSS for styling
