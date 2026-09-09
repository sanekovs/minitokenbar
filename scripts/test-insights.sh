#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_file="$(mktemp /tmp/quota-insights-test.XXXXXX.swift)"
trap 'rm -f "$test_file"' EXIT
cat "$project_dir/Sources/CodexQuota/Insights.swift" > "$test_file"
cat >> "$test_file" <<'SWIFT'
assert(ProfileActivity.parse([:]) == nil)
assert(ProfileActivity.parse(["stats": [:], "metadata": ["stats_error": "unavailable"]]) == nil)
let profile = ProfileActivity.parse(["stats": ["lifetime_tokens": 1500000000, "current_streak_days": 0]])!
assert(profile.streak == 0 && profile.chats == nil)
assert(compactCount(profile.tokens) == "1.5B")
assert(compactCount(nil) == "—")
let analytics = ActivityAnalytics.parse(["data": [
    ["date": "2026-09-08", "totals": ["turns": 4, "credits": 2.5], "models": [["model": "example", "turns": 4]]],
    ["date": "2026-09-09", "totals": ["turns": 3, "credits": 0], "models": [["model": "example", "turns": 3]]]
]])!
assert(analytics.turns == 7 && analytics.credits == 2.5)
assert(analytics.models.count == 1 && analytics.models[0].turns == 7)
assert(ActivityAnalytics.parse([:]) == nil)
assert(ActivityAnalytics.parse(["data": [["date": "2026-09-08"]]]) == nil)
assert(ActivityAnalytics.parse(["data": []])!.turns == 0)
let now = ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")!
let series = recentActivity(analytics.days, count: 7, now: now)
assert(series.count == 7 && series.first!.date == "2026-09-03")
assert(!series[0].reported && series[6].reported && series[6].value == 3)
print("Passed: unavailable vs zero, profile errors, credit units, model aggregation, UTC dates and gaps")
SWIFT
swift "$test_file"
