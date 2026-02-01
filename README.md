# Tayaway

## Prerequisites

- [mise](https://mise.jdx.dev/) - manages Ruby, Node.js, and pnpm
- PostgreSQL

## Setup

```bash
mise install
pnpm install
cd backend && bundle install && cd ..
mise run db_create
mise run db_migrate
```

## Development

```bash
mise run dev
```

- Frontend: http://localhost:5173
- Backend: http://localhost:9292

## Testing

```bash
mise run test              # all tests
mise run test_frontend     # frontend unit tests
mise run test_backend      # backend specs
mise run test_e2e          # playwright e2e tests
```

## Other Commands

```bash
mise run lint              # run linters
mise run typecheck         # run type checkers
mise run build             # build for production
```
