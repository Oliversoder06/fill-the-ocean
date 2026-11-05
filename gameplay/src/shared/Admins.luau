--!strict
-- User ids that may use the admin window (F2, client/Admin). The server re-checks every request.

local Admins: { [number]: boolean } = {
	[62763090] = true,
}

return Admins
