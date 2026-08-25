# Calories Tracker API

A Rails 8 API-only service that turns a photo of a meal into structured, validated
nutrition data using a vision model.

Upload a food photo, and the service extracts the foods it can see along with grams,
calories, and macros — then **validates that output against physical reality** before
storing it. A React client will consume this API; it is versioned and documented with
OpenAPI from the start.

## Why this exists

This is a learning project about running LLMs in production, not just calling them.
The parts that matter:

**Two-layer validation.** A JSON schema constrains the *shape* of the model's output at
the provider. That is not enough — a model will happily return
`{kcal: 2000, protein_g: 1, carbs_g: 1, fat_g: 1}`, which is well-formed and
nutritionally impossible. A second ActiveModel layer validates *semantics*: macros are
cross-checked against stated calories using Atwater factors (4/4/9 kcal per gram), and
energy density above 900 kcal/100g is rejected outright, because pure fat is 900.

**Content-addressed reuse.** Meals are global, not scoped to a user, and keyed by the
SHA-256 of the uploaded image. Re-uploading the same photo — by anyone — returns the
stored result and costs nothing. Macros are also stored on a per-100g basis so gram
amounts can be recalculated later without another model call.

**A real error taxonomy.** Vision calls fail in distinct ways: a timeout, a rate limit,
a well-formed but implausible extraction, or a photo that simply is not food. Each gets
its own handling and retry policy, and the raw provider payload is persisted on every
outcome so failures can be debugged without re-spending tokens.

## Stack

| | |
|---|---|
| Rails 8.1 (API-only), Ruby 3.4 | PostgreSQL 17 |
| [ruby_llm](https://rubyllm.com) — provider-agnostic | Gemini by default, OpenAI swappable via env |
| ActiveStorage for photos | Solid Queue for background analysis |
| RSpec + VCR (no network in CI) | rswag — OpenAPI generated from the request specs |

## Getting started

Requires Docker.

```bash
cp .env.example .env      # then add your GEMINI_API_KEY (or OPENAI_API_KEY)
docker compose up --build
docker compose exec web bin/rails db:prepare
```

The API is on http://localhost:3000, and Swagger UI on http://localhost:3000/api-docs.

### Switching models

The provider is inferred from the model id, so it is one line in `.env`:

```
LLM_MODEL=gemini-3.6-flash   # default: vision + structured output, low cost
LLM_MODEL=gpt-4o             # OpenAI instead — no code change
```

## Running the checks

The same four checks run on every pull request, and all must pass to merge.

```bash
docker compose exec web bundle exec rspec      # specs (replays VCR cassettes, no network)
docker compose exec web bundle exec rubocop    # lint
docker compose exec web bundle exec brakeman   # static security analysis
docker compose exec web bundle exec rake rswag:specs:swaggerize   # regenerate OpenAPI
```

The last one is also a CI gate: if the committed `swagger/` output differs from what the
request specs produce, the build fails. The docs cannot drift from the behaviour.
