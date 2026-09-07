// Run via scripts/test-parser.sh (the app model is prepended).
func window(_ seconds: Int, _ used: Int) -> [String: Any] { ["limit_window_seconds": seconds, "used_percent": used, "reset_at": 1789405468] }
let weekly = QuotaSnapshot.parse(["plan_type": "prolite", "rate_limit": ["primary_window": window(604800, 3), "secondary_window": NSNull()], "additional_rate_limits": [["limit_name": "Spark", "rate_limit": ["primary_window": window(18000, 0), "secondary_window": window(604800, 0)]]], "credits": ["balance": "0"], "rate_limit_reset_credits": ["available_count": 0]])
assert(weekly.menuTitle == "97% · week")
assert(weekly.groups[1].windows.map(\.label) == ["5 hours", "Weekly"])
assert(weekly.resets == 0)
let plus = QuotaSnapshot.parse(["rate_limit": ["primary_window": window(18000, 20), "secondary_window": window(604800, 50)]])
assert(plus.menuTitle == "80% · 5h  50% · week")
let reversed = QuotaSnapshot.parse(["rate_limit": ["primary_window": window(604800, 120), "secondary_window": window(18000, -5)]])
assert(reversed.groups[0].windows.map(\.remaining) == [100, 0])
assert(QuotaSnapshot.parse([:]).menuTitle == "Codex —")
assert(QuotaSnapshot.parse([:]).resets == nil)
print("Passed: weekly-only Pro, Spark, dual-window Plus, swapped windows, clamping, missing data")
