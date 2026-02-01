# Pressing Improvements

## High Priority

### CI/CD Pipeline
- [ ] Add GitHub Actions workflow for running tests on PR
- [ ] Add workflow for linting and type checking
- [ ] Add workflow for building frontend on merge to main
- [ ] Consider deployment automation

### Documentation
- [x] Add root README.md with project overview, setup instructions, and architecture diagram
- [x] Add CLAUDE.md with API endpoint documentation
- [ ] Document API endpoints formally (consider OpenAPI/Swagger spec)

### Pre-commit Hooks
- [ ] Add husky for git hooks
- [ ] Run lint-staged on commit to catch issues early
- [ ] Consider running typecheck on staged files

## Medium Priority

### Health Check Enhancement
- [ ] Extend `/health` endpoint to verify database connectivity
- [ ] Add readiness vs liveness probe distinction for container orchestration

### Docker Support
- [ ] Add Dockerfile for backend
- [ ] Add Dockerfile for frontend (production build)
- [ ] Add docker-compose.yml for local development with PostgreSQL

### Database
- [ ] Add meaningful seed data for development
- [x] Database schema documented in CLAUDE.md

### Testing
- [x] Expand E2E test coverage (auth and events tests added)
- [ ] Add test coverage reporting (Vitest coverage, SimpleCov for Ruby)
- [ ] Consider adding API integration tests

## Lower Priority

### Error Tracking
- [ ] Integrate error tracking service (Sentry or similar)
- [ ] Add structured logging for backend

### Security
- [ ] Add security headers middleware to backend
- [ ] Consider adding rate limiting
- [ ] Add CORS configuration review

### Developer Experience
- [ ] Add VS Code workspace settings and recommended extensions
- [ ] Consider adding Renovate/Dependabot for dependency updates
