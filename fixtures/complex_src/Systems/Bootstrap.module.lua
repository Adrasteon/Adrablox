local Config = require(script.Parent.Config)

local Bootstrap = {}

function Bootstrap.start()
	return Config.Enabled
end

return Bootstrap
