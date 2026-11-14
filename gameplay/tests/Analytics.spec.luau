local Analytics = require("../../common/Analytics")
local Config = require("../src/shared/Config")

-- The rules live in Analytics too: pure modules can't require each other.
local Rules = Analytics

local tests = {}

local ONBOARDING = Analytics.ONBOARDING

local function facts(...: string): { [string]: boolean }
	local set = {}
	for _, name in { ... } do
		set[name] = true
	end
	return set
end

function tests.advance_never_skips(t)
	-- FirstPour is true but FirstScoop isn't: stop before FirstScoop.
	local f = facts("Joined", "LobbyLoaded", "PartyStarted", "RunLoaded", "IntroDone", "AtWell", "FirstPour")
	t.expectEq(Rules.advance(ONBOARDING, 0, f), 6, "up to AtWell")
	f.FirstScoop = true
	t.expectEq(Rules.advance(ONBOARDING, 6, f), 8, "FirstScoop then FirstPour follow at once")
end

function tests.advance_waits_at_a_false_step(t)
	t.expectEq(Rules.advance(ONBOARDING, 0, facts("LobbyLoaded")), 0, "Joined not true: nothing")
	t.expectEq(Rules.advance(ONBOARDING, 3, facts()), 3, "never goes back")
	t.expectEq(Rules.advance(ONBOARDING, #ONBOARDING, facts()), #ONBOARDING, "done stays done")
end

function tests.onboarding_follows_the_guide(t)
	local want = { "Joined", "LobbyLoaded", "PartyStarted", "RunLoaded", "IntroDone", "AtWell", "FirstScoop", "FirstPour", "CanAfford", "FirstUpgrade" }
	t.expectEq(#ONBOARDING, #want)
	for i, name in want do
		t.expectEq(ONBOARDING[i], name, `step {i}`)
	end
	t.expectEq(ONBOARDING[Analytics.LOBBY_STEPS], "PartyStarted", "the lobby sends up to PartyStarted")
end

function tests.funnels_built_from_config_in_order(t)
	local funnels = Analytics.funnels(Config)
	local byId = {}
	for _, funnel in funnels do
		byId[funnel.id] = funnel
	end
	local progression = byId.Progression_v1
	t.expectEq(progression.recurring, false)
	t.expectEq(progression.steps[1], "Area2")
	t.expectEq(progression.steps[#progression.steps - 1], `Area{Config.areas[#Config.areas].id}`)
	t.expectEq(progression.steps[#progression.steps], "OceanFull")
	local tool = byId.Tool_v1
	t.expectEq(#tool.steps, #(Config.track("tool") :: any).levels)
	t.expectEq(tool.steps[1], "Level1")
	local milestones = byId.Milestones_v1
	t.expectEq(#milestones.steps, #Config.milestones)
	t.expectEq(milestones.steps[1], "M5")
	t.expectEq(milestones.steps[#milestones.steps], "M100")
	local honeycomb = byId.Honeycomb_v1
	t.expectEq(honeycomb.recurring, true)
	t.expectEq(table.concat(honeycomb.steps, ","), "Opened,Viewed,Bought")
	t.expectEq(#funnels <= 10, true, "Roblox allows 10 funnels")
end

-- Roblox reads a recurring funnel's filters from its first step only, so that is where its fields go.
function tests.funnel_fields_listed(t)
	t.expectEq(table.concat(Analytics.FUNNEL_FIELDS.Honeycomb_v1, ","), "Source,Stage")
	t.expectEq(Analytics.validFields(Config, Analytics.FUNNEL_FIELDS.Honeycomb_v1, { Source = "Goal", Stage = "Guide:5" }), true)
	t.expectEq(Analytics.validFields(Config, Analytics.FUNNEL_FIELDS.Honeycomb_v1, { Source = "Mouse", Stage = "F0" }), false)
end

function tests.every_field_value_is_listed(t)
	local values = Analytics.fieldValues(Config)
	for name, fields in Analytics.EVENTS do
		t.expectEq(#fields <= 3, true, `{name}: Roblox reads at most 3 fields`)
		for _, field in fields do
			t.expectEq(values[field] ~= nil, true, `{name}.{field} has a value list`)
		end
	end
	local combos = 1
	for _, field in Analytics.EVENTS.SessionEnd do
		combos *= #values[field]
	end
	t.expectEq(combos < 8000, true, `SessionEnd's combinations ({combos}) stay under Roblox's daily 8,000`)
	t.expectEq(Analytics.valid(Config, "SessionEnd", { Where = "Area1", Doing = "Idle", Stage = "F10" }), true)
	t.expectEq(Analytics.valid(Config, "SessionEnd", { Where = "Bob's house", Doing = "Idle", Stage = "F10" }), false, "free text refused")
	t.expectEq(Analytics.valid(Config, "SessionEnd", { Where = "Area1", Doing = "Idle" }), false, "a missing field refused")
	t.expectEq(Analytics.valid(Config, "NoSuchEvent", {}), false, "an unlisted event refused")
end

function tests.economy_names_fit_roblox_limits(t)
	local types = 0
	for _ in Analytics.MONEY do
		types += 1
	end
	t.expectEq(types <= 20, true, "Roblox allows 20 transaction types")
	local skus = Analytics.skus(Config)
	t.expectEq(#skus <= 100, true, `Roblox allows 100 item SKUs, got {#skus}`)
	t.expectEq(table.find(skus, "tool") ~= nil, true)
	t.expectEq(table.find(skus, "gate:2") ~= nil, true)
end

function tests.bucket_edges(t)
	local fps = Analytics.BANDS.fps
	t.expectEq(Rules.bucket(fps, 0), fps.labels[1])
	t.expectEq(Rules.bucket(fps, fps.edges[1] - 0.01), fps.labels[1])
	t.expectEq(Rules.bucket(fps, fps.edges[1]), fps.labels[2], "an edge belongs to the band above")
	t.expectEq(Rules.bucket(fps, 1e9), fps.labels[#fps.labels])
	t.expectEq(Rules.bucket(Analytics.BANDS.teamSize, 1), "1")
	t.expectEq(Rules.bucket(Analytics.BANDS.teamSize, 7), "4+")
	t.expectEq(Rules.bucket(fps, 0 / 0), fps.labels[1], "NaN lands in the first band, never a new value")
end

function tests.stage_bands_cover_0_to_1(t)
	local stages = Analytics.fieldValues(Config).Stage
	for i = 0, 100 do
		local stage = Rules.stage("playing", 0, i / 100)
		t.expectEq(table.find(stages, stage) ~= nil, true, `fill {i}%: {stage}`)
	end
	t.expectEq(Rules.stage("playing", 0, 0.049), "F0")
	t.expectEq(Rules.stage("playing", 0, 0.05), "F5")
	t.expectEq(Rules.stage("playing", 0, 1), "F100")
	t.expectEq(Rules.stage("intro", 3, 0), "Intro", "the intro wins")
	t.expectEq(Rules.stage("playing", 3, 0), "Guide:3", "the guide's step while it shows")
	t.expectEq(Rules.stage("playing", 99, 0.2), "F20", "a step out of range is ignored")
	t.expectEq(Rules.stage("loading", 0, 0), "Loading")
end

function tests.doing_prefers_the_specific(t)
	local base = { phase = "playing", idle = 0, honeycomb = false, driving = false, hosing = false, lastAct = nil, lastActAge = math.huge, carried = 0 }
	local function with(changes)
		local f = table.clone(base)
		for k, v in changes do
			f[k] = v
		end
		return Rules.doing(f)
	end
	t.expectEq(with({}), "Roaming")
	t.expectEq(with({ phase = "loading" }), "Loading")
	t.expectEq(with({ phase = "intro", idle = 999 }), "Intro", "the intro is never idle")
	t.expectEq(with({ phase = "ending" }), "Ending")
	t.expectEq(with({ idle = Analytics.IDLE_AFTER, carried = 5 }), "Idle")
	t.expectEq(with({ honeycomb = true, carried = 5 }), "Honeycomb")
	t.expectEq(with({ driving = true, carried = 5 }), "Driving")
	t.expectEq(with({ hosing = true }), "Hosing")
	t.expectEq(with({ lastAct = "scoop", lastActAge = 1, carried = 5 }), "Scooping")
	t.expectEq(with({ lastAct = "pour", lastActAge = 1 }), "Pouring")
	t.expectEq(with({ lastAct = "scoop", lastActAge = 30, carried = 5 }), "Carrying", "an old scoop: walking with water")
	local doing = Analytics.fieldValues(Config).Doing
	for _, value in { "Roaming", "Loading", "Intro", "Ending", "Idle", "Honeycomb", "Driving", "Hosing", "Scooping", "Pouring", "Carrying" } do
		t.expectEq(table.find(doing, value) ~= nil, true, `{value} is listed`)
	end
end

function tests.budget_spends_at_most_share(t)
	local limit = math.floor((120 + 20 * 2) * Analytics.BUDGET.share)
	t.expectEq(Rules.allowed(0, 0, 2, false), true)
	t.expectEq(Rules.allowed(limit, 0, 2, true), false, "nothing past the share")
	t.expectEq(Rules.allowed(0, limit - 1, 2, true), true)
	t.expectEq(Rules.allowed(0, limit, 2, true), false)
end

function tests.budget_protects_reserved(t)
	local limit = math.floor((120 + 20 * 1) * Analytics.BUDGET.share)
	local reserve = math.ceil(limit * Analytics.BUDGET.protectedShare)
	t.expectEq(Rules.allowed(limit - reserve - 1, 0, 1, false), true)
	t.expectEq(Rules.allowed(limit - reserve, 0, 1, false), false, "normal events stop at the reserve")
	t.expectEq(Rules.allowed(limit - reserve, 0, 1, true), true, "protected ones still go")
end

function tests.client_reports_are_listed(t)
	for name, rule in Analytics.CLIENT do
		t.expectEq(type(rule.gap) == "number" and rule.gap >= 0, true, `{name} has a gap`)
		t.expectEq(type(rule.kind) == "string", true, `{name} has a kind`)
	end
	t.expectEq(Analytics.CLIENT.fps ~= nil, true)
	t.expectEq(Analytics.CLIENT.guide ~= nil, true)
	t.expectEq(Analytics.CLIENT.hcOpen ~= nil, true)
end

function tests.check_report_args(t)
	t.expectEq(Rules.checkReport(Config, "fps", 59.5), 59.5)
	t.expectEq(Rules.checkReport(Config, "fps", 5000), 1000, "clamped")
	t.expectEq(Rules.checkReport(Config, "fps", 0 / 0), nil, "NaN refused")
	t.expectEq(Rules.checkReport(Config, "fps", "60"), nil)
	t.expectEq(Rules.checkReport(Config, "guide", 3), 3)
	t.expectEq(Rules.checkReport(Config, "guide", 3.5), nil)
	t.expectEq(Rules.checkReport(Config, "guide", Analytics.GUIDE_STEPS + 1), nil)
	t.expectEq(Rules.checkReport(Config, "hcOpen", "Key"), "Key")
	t.expectEq(Rules.checkReport(Config, "hcOpen", "Somewhere"), nil)
	t.expectEq(Rules.checkReport(Config, "short", "tool"), "tool")
	t.expectEq(Rules.checkReport(Config, "short", "gate:3"), "gate:3")
	t.expectEq(Rules.checkReport(Config, "short", "nope"), nil)
	t.expectEq(Rules.checkReport(Config, "hcView", nil), true)
	t.expectEq(#(Rules.checkReport(Config, "error", string.rep("x", 999)) :: string), Analytics.TEXT_MAX)
	t.expectEq(Rules.checkReport(Config, "nope", 1), nil, "unknown names refused")
end

return tests
