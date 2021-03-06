require "util"
require "config"
require "autotargeter"

script.on_init(function() On_Init() end)
script.on_configuration_changed(function() On_Init() end)
script.on_load(function() On_Load() end)

remote.add_interface("orbital_ion_cannon",
	{
		on_ion_cannon_targeted = function() return getIonCannonTargetedEventID() end,

		on_ion_cannon_fired = function() return getIonCannonFiredEventID() end,

		target_ion_cannon = function(force, position, surface, player) return targetIonCannon(force, position, surface, player) end -- Player is optional
	}
)

function generateEvents()
	getIonCannonTargetedEventID()
	getIonCannonFiredEventID()
end

function getIonCannonTargetedEventID()
	if not when_ion_cannon_targeted then
		when_ion_cannon_targeted = script.generate_event_name()
	end
	return when_ion_cannon_targeted
end

function getIonCannonFiredEventID()
	if not when_ion_cannon_fired then
		when_ion_cannon_fired = script.generate_event_name()
	end
	return when_ion_cannon_fired
end

function On_Init()
	generateEvents()
	if not global.forces_ion_cannon_table then
		global.forces_ion_cannon_table = {}
		global.forces_ion_cannon_table["player"] = {}
	end
	global.goToFull = global.goToFull or {}
	global.klaxonTick = global.klaxonTick or 0
	global.readyTick = global.readyTick or 0
	if global.ion_cannon_table then
		global.forces_ion_cannon_table["player"] = global.ion_cannon_table 	-- Migrate ion cannon tables from version 1.0.5 and lower
		global.ion_cannon_table = nil 										-- Remove old ion cannon table
	end
	-- remote.call("freeplay", set_show_launched_without_satellite, false)
	for i, player in pairs(game.players) do
		if not global.forces_ion_cannon_table[player.force.name] then
			table.insert(global.forces_ion_cannon_table, player.force.name)
			global.forces_ion_cannon_table[player.force.name] = {}
		end
		if global.goToFull[player.index] == nil then
			global.goToFull[player.index] = true
		end
		if player.gui.top["ion-cannon-button"] then
			player.gui.top["ion-cannon-button"].destroy()
		end
		if player.gui.top["ion-cannon-stats"] then
			player.gui.top["ion-cannon-stats"].destroy()
		end
	end
	for i, force in pairs(game.forces) do
		force.reset_recipes()
		if global.forces_ion_cannon_table[force.name] and #global.forces_ion_cannon_table[force.name] > 0 then
			global.IonCannonLaunched = true
			script.on_event(defines.events.on_tick, process_tick)
			break
		end
	end
end

function On_Load()
	generateEvents()
	if global.IonCannonLaunched then
		script.on_event(defines.events.on_tick, process_tick)
	end
end

script.on_event(defines.events.on_force_created, function(event)
	if not global.forces_ion_cannon_table then
		On_Init()
	end
	global.forces_ion_cannon_table[event.force.name] = {}
end)

script.on_event(defines.events.on_forces_merging, function(event)
	global.forces_ion_cannon_table[event.source.name] = nil
	for i, player in pairs(game.players) do
		init_GUI(player)
	end
end)

function init_GUI(player)
	if not player.connected then
		return
	end
	if #global.forces_ion_cannon_table[player.force.name] == 0 then
		local frame = player.gui.left["ion-cannon-stats"]
		if (frame) then
			frame.destroy()
		end
		if player.gui.top["ion-cannon-button"] then
			player.gui.top["ion-cannon-button"].destroy()
		end
		return
	end
	if not player.gui.top["ion-cannon-button"] then
		player.gui.top.add{type="button", name="ion-cannon-button", style="ion-cannon-button-style"}
	end
end

function open_GUI(player)
	local frame = player.gui.left["ion-cannon-stats"]
	if (frame) and global.goToFull[player.index] then
		frame.destroy()
	else
		if global.goToFull[player.index] then
			global.goToFull[player.index] = false
			if (frame) then
				frame.destroy()
			end
			frame = player.gui.left.add{type="frame", name="ion-cannon-stats", direction="vertical"}
			frame.add{type="label", caption={"ion-cannon-details-full"}}
			frame.add{type="table", colspan=2, name="ion-cannon-table"}
			for i = 1, #global.forces_ion_cannon_table[player.force.name] do
				frame["ion-cannon-table"].add{type = "label", caption = {"ion-cannon-num", i}}
				if global.forces_ion_cannon_table[player.force.name][i][2] == 1 then
					frame["ion-cannon-table"].add{type = "label", caption = {"ready"}}
				else
					frame["ion-cannon-table"].add{type = "label", caption = {"cooldown", global.forces_ion_cannon_table[player.force.name][i][1]}}
				end
			end
		else
			global.goToFull[player.index] = true
			if (frame) then
				frame.destroy()
			end
			frame = player.gui.left.add{type="frame", name="ion-cannon-stats", direction="vertical"}
			frame.add{type="label", caption={"ion-cannon-details-compact"}}
			frame.add{type="table", colspan=1, name="ion-cannon-table"}
			frame["ion-cannon-table"].add{type = "label", caption = {"ion-cannons-in-orbit", #global.forces_ion_cannon_table[player.force.name]}}
			frame["ion-cannon-table"].add{type = "label", caption = {"ion-cannons-ready", countIonCannonsReady(player)}}
			if countIonCannonsReady(player) < #global.forces_ion_cannon_table[player.force.name] then
				frame["ion-cannon-table"].add{type = "label", caption = {"time-until-next-ready", timeUntilNextReady(player)}}
			end
		end
	end
end

function update_GUI(player)
	if not player.connected then
		return
	end
	init_GUI(player)
	local frame = player.gui.left["ion-cannon-stats"]
	if (frame) then
		if frame["ion-cannon-table"] and not global.goToFull[player.index] then
			frame["ion-cannon-table"].destroy()
			frame.add{type="table", colspan=2, name="ion-cannon-table"}
			for i = 1, #global.forces_ion_cannon_table[player.force.name] do
				frame["ion-cannon-table"].add{type = "label", caption = {"ion-cannon-num", i}}
				if global.forces_ion_cannon_table[player.force.name][i][2] == 1 then
					frame["ion-cannon-table"].add{type = "label", caption = {"ready"}}
				else
					frame["ion-cannon-table"].add{type = "label", caption = {"cooldown", global.forces_ion_cannon_table[player.force.name][i][1]}}
				end
			end
		end
		if frame["ion-cannon-table"] and global.goToFull[player.index] then
			frame["ion-cannon-table"].destroy()
			frame.add{type="table", colspan=1, name="ion-cannon-table"}
			frame["ion-cannon-table"].add{type = "label", caption = {"ion-cannons-in-orbit", #global.forces_ion_cannon_table[player.force.name]}}
			frame["ion-cannon-table"].add{type = "label", caption = {"ion-cannons-ready", countIonCannonsReady(player)}}
			if countIonCannonsReady(player) < #global.forces_ion_cannon_table[player.force.name] then
				frame["ion-cannon-table"].add{type = "label", caption = {"time-until-next-ready", timeUntilNextReady(player)}}
			end
		end
	end
end

function countIonCannonsReady(player)
	local ionCannonsReady = 0
	for i, cooldown in pairs(global.forces_ion_cannon_table[player.force.name]) do
		if cooldown[2] == 1 then
			ionCannonsReady = ionCannonsReady + 1
		end
	end
	return ionCannonsReady
end

function timeUntilNextReady(player)
	local shortestCooldown = ionCannonCooldownSeconds
	for i, cooldown in pairs(global.forces_ion_cannon_table[player.force.name]) do
		if cooldown[1] < shortestCooldown and cooldown[2] == 0 then
			shortestCooldown = cooldown[1]
		end
	end
	return shortestCooldown
end

script.on_event(defines.events.on_gui_click, function(event)
	local player = game.players[event.element.player_index]
	local name = event.element.name
	if name == "ion-cannon-button" then
		open_GUI(player)
		return
	end
end)

script.on_event("ion-cannon-hotkey", function(event)
	local player = game.players[event.player_index]
	if global.IonCannonLaunched then
		open_GUI(player)
	end
end)

script.on_event(defines.events.on_player_created, function(event)
	init_GUI(game.players[event.player_index])
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
	local player = game.players[event.player_index]
	if playVoices and #global.forces_ion_cannon_table[player.force.name] > 0 and isHolding({name="ion-cannon-targeter", count=1}, player) and not isAllIonCannonOnCooldown(player) then
		playSoundForPlayer("select-target", player)
	end
end)

function process_tick()
	local current_tick = game.tick
	if current_tick % 60 == 47 then
		ReduceIonCannonCooldowns()
		for i, force in pairs(game.forces) do
			if global.forces_ion_cannon_table[force.name] and isIonCannonReady(force) then
				if playVoices and global.readyTick < current_tick then
					global.readyTick = current_tick + readyTicks
					playSoundForForce("ion-cannon-ready", force)
				end
			end
		end
		for i, player in pairs(game.players) do
			update_GUI(player)
		end
	end
end

function ReduceIonCannonCooldowns()
	for i, force in pairs(game.forces) do
		if global.forces_ion_cannon_table[force.name] then
			for i, cooldown in pairs(global.forces_ion_cannon_table[force.name]) do
				if cooldown[1] > 0 then
					global.forces_ion_cannon_table[force.name][i][1] = global.forces_ion_cannon_table[force.name][i][1] - 1
				end
			end
		end
	end
end

function isAllIonCannonOnCooldown(player)
	for i, cooldown in pairs(global.forces_ion_cannon_table[player.force.name]) do
		if cooldown[2] == 1 then
			return false
		end
	end
	return true
end

function isIonCannonReady(force)
	local found = false
	for i, cooldown in pairs(global.forces_ion_cannon_table[force.name]) do
		if cooldown[1] == 0 and cooldown[2] == 0 then
			cooldown[2] = 1
			found = true
		end
	end
	return found
end

function anyFriendlyCanReach(entity, force)
	for i, player in pairs(force.players) do
		if player.connected and player.can_reach_entity(entity) then
			return true
		end
	end
	return false
end

function playSoundForPlayer(sound, player)
	player.surface.create_entity({name = sound, position = player.position})
end

function playSoundForForce(sound, force)
	for i, player in pairs(force.players) do
		if player.connected then
			player.surface.create_entity({name = sound, position = player.position})
		end
	end
end

function playSoundForAllPlayers(sound)
	for i, player in pairs(game.players) do
		if player.connected then
			player.surface.create_entity({name = sound, position = player.position})
		end
	end
end

function isHolding(stack, player)
	local holding = player.cursor_stack
	if holding and holding.valid_for_read and (holding.name == stack.name) and (holding.count >= stack.count) then
		return true
	end
	return false
end

function targetIonCannon(force, position, surface, player)
	local cannonNum = 0
	for i, cooldown in pairs(global.forces_ion_cannon_table[force.name]) do
		if cooldown[2] == 1 then
			cannonNum = i
			break
		end
	end
	if cannonNum == 0 then
		if player then
			player.print({"unable-to-fire"})
		end
		return false
	else
		if player then
			player.print({"targeting-ion-cannon" , cannonNum})
		end
		local TargetPosition = position
		TargetPosition.y = TargetPosition.y + 1
		local IonTarget = surface.create_entity({name = "ion-cannon-target", position = TargetPosition, force = game.forces.neutral})
		IonTarget.backer_name = "Ion Cannon #" .. cannonNum .. " Target Location"
		if proximityCheck and anyFriendlyCanReach(IonTarget, force) then
			if player then
				player.print({"proximity-alert"})
			end
			IonTarget.destroy()
			return false
		else
			local current_tick = game.tick
			local CrosshairsPosition = position
			CrosshairsPosition.y = CrosshairsPosition.y - 20
			surface.create_entity({name = "crosshairs", target = IonTarget, force = force, position = CrosshairsPosition, speed = 0})
			if printMessages then
				force.print({"target-acquired"})
			end
			if playKlaxon and global.klaxonTick < current_tick then
				global.klaxonTick = current_tick + 60
				playSoundForAllPlayers("klaxon")
			end
			global.forces_ion_cannon_table[force.name][cannonNum][1] = ionCannonCooldownSeconds
			global.forces_ion_cannon_table[force.name][cannonNum][2] = 0
			if printMessages then
				force.print({"time-to-ready-again" , cannonNum , ionCannonCooldownSeconds})
			end
			return true
		end
	end
end

script.on_event(defines.events.on_rocket_launched, function(event)
	local force = event.rocket.force
	if event.rocket.get_item_count("orbital-ion-cannon") > 0 then
		table.insert(global.forces_ion_cannon_table[force.name], {ionCannonCooldownSeconds, 0})
		global.IonCannonLaunched = true
		script.on_event(defines.events.on_tick, process_tick)
		if #global.forces_ion_cannon_table[force.name] == 1 then
			force.recipes["ion-cannon-targeter"].enabled = true
			for i, player in pairs(force.players) do
				init_GUI(player)
			end
			force.print({"congratulations-first"})
			force.print({"first-help"})
			force.print({"second-help"})
			force.print({"third-help"})
			if playVoices then
				playSoundForForce("ion-cannon-charging", force)
			end
		else
			if #global.forces_ion_cannon_table[force.name] > 1 then
				force.print({"congratulations-additional"})
			end
			force.print({"ion-cannons-in-orbit" , #global.forces_ion_cannon_table[force.name]})
			force.print({"time-to-ready" , #global.forces_ion_cannon_table[force.name] , ionCannonCooldownSeconds})
			if playVoices then
				playSoundForForce("ion-cannon-charging", force)
			end
		end
	end
end)

script.on_event(defines.events.on_built_entity, function(event)
	local player = game.players[event.player_index]
	if event.created_entity.name == "ion-cannon-targeter" then
		player.insert({name="ion-cannon-targeter", count=1})
		return event.created_entity.destroy()
	end
	if event.created_entity.name == "entity-ghost" then
		if event.created_entity.ghost_name == "ion-cannon-targeter" then
			return event.created_entity.destroy()
		end
	end
end)

script.on_event(defines.events.on_trigger_created_entity, function(event)
	local created_entity = event.entity
	if created_entity.name == "ion-cannon-explosion" then
		game.raise_event(when_ion_cannon_fired, {surface = created_entity.surface, position = created_entity.position, radius = ionCannonRadius})		-- Passes event.surface, event.position, and event.radius
	end
end)

script.on_event(defines.events.on_put_item, function(event)
	local current_tick = event.tick
	if global.tick and global.tick > current_tick then
		return
	end
	global.tick = current_tick + lockoutTicks
	local player = game.players[event.player_index]
	if isHolding({name="ion-cannon-targeter", count=1}, player) then
		local fired = targetIonCannon(player.force, event.position, player.surface, player)
		if fired then
			local TargetPosition = event.position
			TargetPosition.y = TargetPosition.y + 1
			game.raise_event(when_ion_cannon_targeted, {surface = player.surface, force = player.force, player_index = event.player_index, position = TargetPosition, radius = ionCannonRadius})		-- Passes event.surface, event.force, event.player_index, event.position, and event.radius
		end
	end
end)
