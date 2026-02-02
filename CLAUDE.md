# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tayaway is a full-stack event planning web application with a Ruby backend API and Vue.js frontend, organized as a pnpm monorepo. Users authenticate via magic link email, then can create and manage events with flexible date ranges.

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
  └── src/pages/           Page components (Home, Login, Profile, Events)
  └── src/components/      Reusable components (events/, calendar/)
  └── src/composables/     Vue composables (useAuth, useEvents, useCalendar)
  └── src/router/          Vue Router configuration

backend/           Ruby + Roda + Sequel + PostgreSQL
  └── app/app.rb           Main Roda app with hash_routes plugin
  └── app/routes/          Route files (auth.rb, events.rb)
  └── app/models/          Sequel models (User, Session, MagicLinkToken, Event, DateRange)
  └── db/migrations/       Sequel migrations

e2e/               Playwright tests
```

Frontend dev server proxies `/api/*` requests to the backend.

## API Endpoints

**Authentication (`/api/auth`)**
- `POST /magic-link` - Request magic link email
- `POST /verify` - Verify token and get session
- `GET /me` - Get current user (requires auth)
- `POST /logout` - End session (requires auth)

**Events (`/api/events`)** - All require authentication
- `GET /` - List user's events
- `POST /` - Create event with name, description, date_ranges
- `GET /:id` - Get event details
- `PUT /:id` - Update event
- `DELETE /:id` - Delete event

**Health**
- `GET /health` - Health check
- `GET /api/health` - API health check

## Database Schema

- **users** - id (UUID), email (CITEXT), name, timestamps
- **magic_link_tokens** - id, user_id, token, email, expires_at (15 min), used_at
- **sessions** - id, user_id, token, expires_at (30 days)
- **events** - id, user_id, name, description, timestamps
- **date_ranges** - id, event_id, start_date, end_date, timestamps

## Code Style Requirements

**Backend (Ruby):**
- Every file must have `# typed: true` (Sorbet sigil) and `# frozen_string_literal: true`
- Use double quotes for strings
- Roda routes use `hash_routes` plugin pattern

**Frontend (TypeScript/Vue):**
- Vue components use `<script setup lang="ts">` syntax
- Tailwind CSS for styling
- Use composables for shared state/logic
- Always support both light and dark mode using Tailwind's `dark:` prefix
