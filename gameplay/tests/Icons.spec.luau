local Config = require("../src/shared/Config")
local Icons = require("../src/shared/Icons")

local tests = {}

-- The hotbar and honeycomb show images, not 3D models: every tool and item model needs one.
function tests.every_tool_model_has_an_icon(t)
	t.expectEq(type(Icons.of(Config.start.toolModel)), "string", Config.start.toolModel)
	for _, level in Config.track("tool").levels do
		t.expectEq(type(Icons.of(level.model)), "string", level.model)
	end
end

function tests.every_item_model_has_an_icon(t)
	for _, item in Config.items do
		t.expectEq(type(Icons.of(item.model)), "string", `{item.id} ({item.model})`)
	end
end

function tests.icons_are_asset_ids(t)
	t.expectEq(Icons.of("Cup"):match("^rbxassetid://%d+$") ~= nil, true)
	t.expectEq(Icons.of("NoSuchModel"), nil)
end

return tests
