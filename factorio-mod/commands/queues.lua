-- AI Companion v0.8.0 - DRY tick-based queue system
-- Inspired by FLE's harvest_resource implementation
local u = require("commands.init")

local M = {}

-- Initialize all queue storages
function M.init()
  storage.harvest_queues = storage.harvest_queues or {}
  storage.craft_queues = storage.craft_queues or {}
  storage.build_queues = storage.build_queues or {}
  storage.combat_queues = storage.combat_queues or {}
  storage.path_queues = storage.path_queues or {}  -- For future pathfinding
end

-- ============ HARVEST QUEUE ============

function M.start_harvest(companion_id, position, target_count)
  local c = u.get_companion(companion_id)
  if not c or not c.entity or not c.entity.valid then return nil end

  local surface = c.entity.surface
  local entities = surface.find_entities_filtered{
    position = position,
    radius = 3,
    type = "resource"
  }

  if #entities == 0 then return {error = "No resource"} end

  -- Sort by distance
  table.sort(entities, function(a, b)
    return u.distance(a.position, c.entity.position) < u.distance(b.position, c.entity.position)
  end)

  -- Create queue
  storage.harvest_queues[companion_id] = {
    entities = entities,
    position = position,
    target = target_count,
    harvested = 0,
    current = nil,
    start_tick = game.tick
  }

  -- Start mining first entity
  M.start_mining_next(companion_id)

  return {started = true, entities = #entities, target = target_count}
end

function M.start_mining_next(companion_id)
  local q = storage.harvest_queues[companion_id]
  if not q or #q.entities == 0 then return false end

  local c = u.get_companion(companion_id)
  if not c or not c.entity or not c.entity.valid then
    storage.harvest_queues[companion_id] = nil
    return false
  end

  local entity = table.remove(q.entities, 1)
  if not entity or not entity.valid then
    -- Try next entity
    return M.start_mining_next(companion_id)
  end

  -- Set mining state for realistic animation
  c.entity.update_selected_entity(entity.position)
  c.entity.mining_state = {mining = true, position = entity.position}

  q.current = {
    entity = entity,
    start_tick = game.tick,
    mining_time = (entity.prototype.mineable_properties.mining_time or 1) * 60
  }

  return true
end

function M.tick_harvest_queues()
  if not storage.harvest_queues then return end

  for cid, q in pairs(storage.harvest_queues) do
    local c = u.get_companion(cid)
    if not c or not c.entity or not c.entity.valid then
      storage.harvest_queues[cid] = nil
      goto continue
    end

    -- Check if we're done
    if q.harvested >= q.target then
      c.entity.mining_state = {mining = false}
      storage.harvest_queues[cid] = nil
      goto continue
    end

    -- Check distance
    if u.distance(c.entity.position, q.position) > 5 then
      -- Too far, stop mining
      c.entity.mining_state = {mining = false}
      storage.harvest_queues[cid] = nil
      goto continue
    end

    -- Process current mining
    if not q.current then
      -- No current entity, try to get next
      if not M.start_mining_next(cid) then
        c.entity.mining_state = {mining = false}
        storage.harvest_queues[cid] = nil
      end
      goto continue
    end

    local current = q.current
    local entity = current.entity

    if not entity or not entity.valid then
      q.current = nil
      M.start_mining_next(cid)
      goto continue
    end

    -- Check if mining time has passed (minimum 30 ticks for realism)
    local ticks_mining = game.tick - current.start_tick
    local required_ticks = math.max(30, current.mining_time)

    if ticks_mining >= required_ticks then
      -- Mine the entity for real
      local inv_before = c.entity.get_main_inventory().get_contents()
      local mined = c.entity.mine_entity(entity, true)

      if mined then
        local inv_after = c.entity.get_main_inventory().get_contents()
        local items_added = 0

        for name, after_count in pairs(inv_after) do
          local before_count = inv_before[name] and inv_before[name].count or 0
          items_added = items_added + (after_count.count - before_count)
        end

        q.harvested = q.harvested + math.max(1, items_added)
      end

      q.current = nil

      -- Check if done or continue
      if q.harvested >= q.target then
        c.entity.mining_state = {mining = false}
        storage.harvest_queues[cid] = nil
      else
        M.start_mining_next(cid)
      end
    end

    ::continue::
  end
end

function M.get_harvest_status(companion_id)
  local q = storage.harvest_queues[companion_id]
  if not q then return {active = false} end
  return {
    active = true,
    harvested = q.harvested,
    target = q.target,
    remaining = #q.entities,
    mining = q.current ~= nil
  }
end

function M.stop_harvest(companion_id)
  local q = storage.harvest_queues[companion_id]
  if q then
    local c = u.get_companion(companion_id)
    if c and c.entity and c.entity.valid then
      c.entity.mining_state = {mining = false}
    end
    local harvested = q.harvested
    storage.harvest_queues[companion_id] = nil
    return {stopped = true, harvested = harvested}
  end
  return {stopped = false}
end

-- ============ CRAFT QUEUE ============

function M.start_craft(companion_id, recipe, count)
  local c = u.get_companion(companion_id)
  if not c or not c.entity or not c.entity.valid then return {error = "Companion not found"} end

  local recipe_proto = prototypes.recipe[recipe]
  if not recipe_proto then return {error = "Unknown recipe: " .. recipe} end

  -- Check if can craft (has ingredients)
  local can_craft = c.entity.get_craftable_count(recipe)
  if can_craft < 1 then return {error = "Missing ingredients for " .. recipe} end

  local actual_count = math.min(count, can_craft)
  local ticks_per_craft = math.max(30, (recipe_proto.energy or 0.5) * 60)

  storage.craft_queues[companion_id] = {
    recipe = recipe,
    target = actual_count,
    crafted = 0,
    ticks_per_item = ticks_per_craft,
    current_start_tick = game.tick
  }

  return {started = true, recipe = recipe, target = actual_count, ticks_per_item = ticks_per_craft}
end

function M.tick_craft_queues()
  if not storage.craft_queues then return end

  for cid, q in pairs(storage.craft_queues) do
    local c = u.get_companion(cid)
    if not c or not c.entity or not c.entity.valid then
      storage.craft_queues[cid] = nil
      goto continue
    end

    local elapsed = game.tick - q.current_start_tick
    if elapsed >= q.ticks_per_item then
      local crafted = c.entity.begin_crafting{recipe = q.recipe, count = 1}
      if crafted > 0 then
        q.crafted = q.crafted + 1
        q.current_start_tick = game.tick
      else
        -- Can't craft anymore (missing ingredients)
        storage.craft_queues[cid] = nil
        goto continue
      end

      if q.crafted >= q.target then
        storage.craft_queues[cid] = nil
      end
    end
    ::continue::
  end
end

function M.get_craft_status(companion_id)
  local q = storage.craft_queues[companion_id]
  if not q then return {active = false} end
  return {
    active = true,
    recipe = q.recipe,
    crafted = q.crafted,
    target = q.target,
    progress = math.floor((game.tick - q.current_start_tick) / q.ticks_per_item * 100)
  }
end

function M.stop_craft(companion_id)
  local q = storage.craft_queues[companion_id]
  if q then
    local crafted = q.crafted
    storage.craft_queues[companion_id] = nil
    return {stopped = true, crafted = crafted}
  end
  return {stopped = false}
end

-- ============ BUILD QUEUE ============

function M.start_build(companion_id, entity, position, direction)
  local c = u.get_companion(companion_id)
  if not c or not c.entity or not c.entity.valid then return {error = "Companion not found"} end

  local dir = direction or defines.direction.north
  local dist = u.distance(c.entity.position, position)

  if dist > (c.entity.build_distance or 10) then
    return {error = "Too far to build (distance: " .. math.floor(dist) .. ")"}
  end

  local inv = c.entity.get_main_inventory()
  if inv.get_item_count(entity) < 1 then
    return {error = "No " .. entity .. " in inventory"}
  end

  if not c.entity.surface.can_place_entity{name = entity, position = position, direction = dir, force = c.entity.force} then
    return {error = "Cannot place " .. entity .. " at this position"}
  end

  storage.build_queues[companion_id] = {
    entity = entity,
    position = position,
    direction = dir,
    start_tick = game.tick,
    build_time = 60  -- 1 second
  }

  return {started = true, entity = entity, position = position, build_time = 60}
end

function M.tick_build_queues()
  if not storage.build_queues then return end

  for cid, q in pairs(storage.build_queues) do
    local c = u.get_companion(cid)
    if not c or not c.entity or not c.entity.valid then
      storage.build_queues[cid] = nil
      goto continue
    end

    local elapsed = game.tick - q.start_tick
    if elapsed >= q.build_time then
      local placed = c.entity.surface.create_entity{
        name = q.entity,
        position = q.position,
        direction = q.direction,
        force = c.entity.force
      }

      if placed then
        c.entity.remove_item{name = q.entity, count = 1}
      end

      storage.build_queues[cid] = nil
    end
    ::continue::
  end
end

function M.get_build_status(companion_id)
  local q = storage.build_queues[companion_id]
  if not q then return {active = false} end
  local elapsed = game.tick - q.start_tick
  return {
    active = true,
    entity = q.entity,
    position = q.position,
    progress = math.floor(elapsed / q.build_time * 100)
  }
end

function M.stop_build(companion_id)
  local q = storage.build_queues[companion_id]
  if q then
    storage.build_queues[companion_id] = nil
    return {stopped = true}
  end
  return {stopped = false}
end

-- ============ COMBAT QUEUE ============

function M.start_combat(companion_id, target_position)
  local c = u.get_companion(companion_id)
  if not c or not c.entity or not c.entity.valid then return {error = "Companion not found"} end

  local enemies = c.entity.surface.find_entities_filtered{
    position = target_position,
    radius = 10,
    force = "enemy",
    type = {"unit", "unit-spawner"}
  }

  if #enemies == 0 then return {error = "No enemies at position"} end

  table.sort(enemies, function(a, b)
    return u.distance(a.position, c.entity.position) < u.distance(b.position, c.entity.position)
  end)

  storage.combat_queues[companion_id] = {
    targets = enemies,
    current_target = enemies[1],
    attack_cooldown = 0,
    kills = 0
  }

  return {started = true, targets = #enemies}
end

function M.tick_combat_queues()
  if not storage.combat_queues then return end

  for cid, q in pairs(storage.combat_queues) do
    local c = u.get_companion(cid)
    if not c or not c.entity or not c.entity.valid then
      storage.combat_queues[cid] = nil
      goto continue
    end

    if q.attack_cooldown > 0 then
      q.attack_cooldown = q.attack_cooldown - 5
      goto continue
    end

    -- Check if current target is still valid
    if not q.current_target or not q.current_target.valid then
      q.kills = q.kills + 1
      -- Find next valid target
      local found = false
      for i, t in ipairs(q.targets) do
        if t.valid then
          q.current_target = t
          table.remove(q.targets, i)
          found = true
          break
        end
      end
      if not found then
        c.entity.shooting_state = {state = defines.shooting.not_shooting}
        storage.combat_queues[cid] = nil
        goto continue
      end
    end

    local dist = u.distance(c.entity.position, q.current_target.position)

    if dist <= 6 then
      -- In range, attack
      c.entity.shooting_state = {
        state = defines.shooting.shooting_enemies,
        position = q.current_target.position
      }
      q.attack_cooldown = 15  -- 0.25s between shots
    else
      -- Move closer
      c.entity.shooting_state = {state = defines.shooting.not_shooting}
      local dir = u.get_direction(c.entity.position, q.current_target.position)
      if dir then
        c.entity.walking_state = {walking = true, direction = dir}
      end
    end

    ::continue::
  end
end

function M.get_combat_status(companion_id)
  local q = storage.combat_queues[companion_id]
  if not q then return {active = false} end
  return {
    active = true,
    targets_remaining = #q.targets + (q.current_target and q.current_target.valid and 1 or 0),
    kills = q.kills,
    current_target = q.current_target and q.current_target.valid and q.current_target.name or nil
  }
end

function M.stop_combat(companion_id)
  local q = storage.combat_queues[companion_id]
  if q then
    local c = u.get_companion(companion_id)
    if c and c.entity and c.entity.valid then
      c.entity.shooting_state = {state = defines.shooting.not_shooting}
      c.entity.walking_state = {walking = false}
    end
    local kills = q.kills
    storage.combat_queues[companion_id] = nil
    return {stopped = true, kills = kills}
  end
  return {stopped = false}
end

return M
