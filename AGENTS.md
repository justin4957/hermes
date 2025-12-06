# Repository Guidelines

## Project Structure & Module Organization
- `lib/` main service code: `hermes/router.ex` (HTTP routing), `hermes/dispatcher.ex` (task orchestration), `hermes/ollama.ex` (HTTP client), `hermes/model_registry.ex` (model metadata), and telemetry/config helpers.
- `config/` environment config (`dev.exs`, `prod.exs`, `test.exs`) plus shared defaults in `config.exs`.
- `test/` ExUnit suites and Mox/Bypass helpers; `test/support` loads automatically in test env; integration harness in `test_server.exs`.
- `examples/` client snippets; `doc/` ExDoc output; `openapi.yaml` REST contract; `Dockerfile` release build reference.

## Build, Test, and Development Commands
- Install deps: `mix deps.get`
- Run app locally (requires Ollama on localhost:11434): `iex -S mix`
- Format check/fix: `mix format` (`--check-formatted` in CI)
- Lint: `mix credo --strict`
- Compile with warnings as errors: `mix compile --warnings-as-errors`
- Tests: `mix test` or `mix test --trace`
- Coverage: `mix coveralls` (HTML via `mix coveralls.html`); CI uses `mix coveralls.github`
- Typespec analysis: `mix dialyzer` (PLT cached in `priv/plts/`)
- Docs: `mix docs` then open `doc/index.html`

## Coding Style & Naming Conventions
- Elixir formatter rules via `.formatter.exs`; 2-space indent, max line length 120 in Credo.
- Module names are `Hermes.*`; private functions start with underscore only when required.
- Prefer piped, immutable flows; avoid anonymous function nesting >2 levels.
- Keep public API documented with `@doc` and `@spec`; favor pattern-matching function heads over conditionals.

## Testing Guidelines
- Use ExUnit (`*_test.exs`); isolate external calls with Mox (`Hermes.OllamaBehaviour`) and Bypass for HTTP stubs.
- Property/edge cases with `StreamData` where meaningful.
- Maintain ≥80% coverage (mix config); new features need positive/negative cases.
- Keep fixtures small; prefer factories/helpers in `test/support/`.

## Commit & Pull Request Guidelines
- Commit messages: short, imperative mood (e.g., “Add dispatcher timeout guard”); keep related changes together.
- Before PR: run `mix format`, `mix credo --strict`, `mix test`, and `mix dialyzer`; include any doc or config updates.
- PR description should summarize behavior change, test coverage, and any API/CONFIG impacts (env vars or config keys).
- Link issues and add sample request/response or screenshots when UI/API surface changes.

## Environment & Security Notes
- Configure via env vars (`PORT`, `OLLAMA_URL`, `OLLAMA_TIMEOUT`) or `config/*.exs`; env vars win.
- Never commit secrets or model data; use local `.env` or CI secrets for tokens.
- Local dev expects Ollama running; use `ollama list`/`ollama pull <model>` to match `model_registry` entries.
