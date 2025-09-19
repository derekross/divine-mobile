# Repository Guidelines

## Project Structure & Module Organization
- `mobile/`: Flutter app — code in `lib/`, tests in `test/` and `integration_test/`, assets in `assets/`.
- `backend/`: Cloudflare Workers (TypeScript) — code in `src/`, tests in `test/`, config in `wrangler.jsonc` and `.wrangler/`.
- `nostr_sdk/`: Dart package — code in `lib/`, tests in `test/`; also `docs/`, `website/`, `crawler/`.

## Build, Test, and Development Commands
- Mobile: `cd mobile && flutter pub get && flutter run` (launch app), `flutter test` (unit/widget), `flutter analyze` (lints), `dart format --set-exit-if-changed .` (format), `./build_native.sh ios|macos [debug|release]` (native builds).
- Backend: `cd backend && npm install && npm run dev` (Wrangler dev), `npm test` (Vitest), `npm run deploy` (deploy worker), `npm run cf-typegen` (Cloudflare types), `./flush-analytics-simple.sh true|false` (preview/flush analytics KV).

## Coding Style & Naming Conventions
- Dart/Flutter: 2-space indent; files `snake_case.dart`; classes/widgets `PascalCase`; members `camelCase`. See `mobile/analysis_options.yaml`.
- Limits: ~200 lines/file, ~30 lines/function; never use `Future.delayed` in `lib/`.
- TypeScript: Prettier per `backend/.prettierrc` and `backend/.editorconfig` (tabs, single quotes, semicolons, width 140). Files `kebab-case.ts`; tests in `backend/test` as `*.test.ts|*.spec.ts`.

## Testing Guidelines
- Mobile: run `cd mobile && flutter test`. Target ≥80% overall coverage (see `mobile/coverage_config.yaml`). Co-locate tests as `*_test.dart`.
- Backend: run `cd backend && npm test` (Vitest in workers pool). Place tests under `backend/test` with descriptive names.

## Commit & Pull Request Guidelines
- Commits: follow Conventional Commits (e.g., `feat:`, `fix:`, `docs:`).
- PRs: include clear description, linked issues, tests for new logic, and screenshots/recordings for UI changes.
- Pre-flight: ensure analyzers, formatters, and tests pass locally (e.g., `flutter analyze`, `dart format`, `npm test`).

## Agent-Specific Instructions
- Embedded Nostr Relay: use `ws://localhost:7447`. Do not connect to external relays directly; use `addExternalRelay()` (see `mobile/docs/NOSTR_RELAY_ARCHITECTURE.md`).
- Async: avoid arbitrary sleeps; use callbacks, `Completer`, streams, and readiness signals.
- Quality gate: after any Dart change, run `flutter analyze` and fix all findings.
- Subagent: “flutter-test-runner” can analyze and run tests; invoke with a request like: “Run flutter-test-runner to analyze the current state of the Flutter codebase”.
