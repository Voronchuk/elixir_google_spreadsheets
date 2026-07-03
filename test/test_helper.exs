# Live tests that hit the real Google Sheets API / real auth are tagged
# `@moduletag :integration` and excluded by default. Run them with real credentials via:
#
#     mix test --include integration
#
# (requires `config/test.local.exs` with real auth; see `config/test.exs`).
ExUnit.start(exclude: [:integration])
