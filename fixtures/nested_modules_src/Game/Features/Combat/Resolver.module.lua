local Resolver = {}

function Resolver.resolve(attackerPower, defenderPower)
	if attackerPower > defenderPower then
		return "attacker"
	end
	return "defender"
end

return Resolver
