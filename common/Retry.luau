-- Retries a call that can throw (DataStore, MemoryStore, Teleport). Every failure is warned, the
-- final result is returned to the caller: never swallowed.

local Retry = {}

-- Errors that retrying can't fix (permissions, Studio API access off): give up at once.
local PERMANENT = { "403", "StudioAccessToApisNotAllowed", "not allowed", "Unauthorized" }

local function permanent(err: any): boolean
	local text = tostring(err)
	for _, needle in PERMANENT do
		if text:find(needle, 1, true) then
			return true
		end
	end
	return false
end

-- Runs fn up to `attempts` times, waiting baseDelay * 2^(n-1) plus jitter between tries.
-- Returns true and fn's result, or false and the last error.
function Retry.run(label: string, fn: () -> any, attempts: number?, baseDelay: number?): (boolean, any)
	local tries = attempts or 4
	local delay = baseDelay or 1
	local lastError
	for attempt = 1, tries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		warn(`[Retry] {label} failed (attempt {attempt}/{tries}): {result}`)
		if permanent(result) then
			break
		end
		if attempt < tries then
			task.wait(delay * 2 ^ (attempt - 1) + math.random() * delay)
		end
	end
	return false, lastError
end

return Retry
