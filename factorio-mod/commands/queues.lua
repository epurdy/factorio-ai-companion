-- AI Companion v0.9.0 - Tick-based queue system
local u = require("commands.init")

local M = {}

-- Constants
local TICK_INTERVAL = 5
local MIN_ACTION_TICKS = 30
local BUILD_TICKS = 60
local ATTACK_COOLDOWN = 15
local ATTACK_RANGE = 6
local MINING_RANGE = 5

-- Validate companion exists and is valid
local function valid_companion(id)
  local c = u.get_companion(id)
  return c and c.entity and c.entity.valid and c
end

-- Generic queue processor - eliminates repetition across all tick functions
local function process_queue(queue_name, processor)
  local queues = storage[queue_name]
  if not queues then return end

  local to_remove = {}
  for cid, q in pairs(queues) do
    local c = valid_companion(cid)
    if not c then
      to_remove[#to_remove + 1] = cid
    else
      local should_remove = processor(cid, q, c)
      if should_remove then to_remove[#to_remove + 1] = cid end
    end
  end

  for _, cid in ipairs(to_remove) do queues[cid] = nil end
end

function M.init()
  storage.harvest_queues = storage.harvest_queues or {}
  storage.craft_queues = storage.craft_queues or {}
  storage.build_queues = storage.build_queues or {}
  storage.combat_queues = storage.combat_queues or {}
end

-- ============ HARVEST ============

function M.start_harvest(cid, position, target_count, resource_name)
  local c = valid_companion(cid)
  if not c then return {error = "Invalid companion"} end

  -- Filter by resource name if specified, otherwise get all resources
  local filter = {position = position, radius = 3, type = "resource"}
  if resource_name then filter.name = resource_name end

  local entities = c.entity.surface.find_entities_filtered(filter)
  if #entities == 0 then return {error = "No resource"} end

  table.sort(entities, function(a, b)
    return u.distance(a.position, c.entity.position) < u.distance(b.position, c.entity.position)
  end)

  storage.harvest_queues[cid] = {
    entities = entities,
    position = position,
    target = target_count,
    harvested = 0,
    current = nil,
    resource_name = resource_name
  }

  M.start_mining_next(cid)
  -- Set inv_snapshot immediately after starting mining
  storage.harvest_queues[cid].inv_snapshot = c.entity.get_main_inventory().get_contents()
  return {started = true, entities = #entities, target = target_count, resource = resource_name}
end

function M.start_mining_next(cid)
  local q = storage.harvest_queues[cid]
  if not q then return false end

  local c = valid_companion(cid)
  if not c then
    storage.harvest_queues[cid] = nil
    return false
  end

  while #q.entities > 0 do
    local entity = table.remove(q.entities, 1)
    if entity and entity.valid then
      c.entity.update_selected_entity(entity.position)
      c.entity.mining_state = {mining = true, position = entity.position}
      q.current = {
        entity = entity,
        start_tick = game.tick,
        mining_time = (entity.prototype.mineable_properties.mining_time or 1) * 60
      }
      return true
    end
  end
  return false
end

function M.tick_harvest_queues()
  process_queue("harvest_queues", function(cid, q, c)
    -- Target reached
    if q.harvested >= q.target then
      c.entity.mining_state = {mining = false}
      return true
    end

    -- Too far from mining area
    if u.distance(c.entity.position, q.position) > MINING_RANGE then
      c.entity.mining_state = {mining = false}
      return true
    end

    -- Start mining first resource
    if not q.current then
      if not M.start_mining_next(cid) then
        c.entity.mining_state = {mining = false}
        return true
      end
      q.inv_snapshot = c.entity.get_main_inventory().get_contents()
      return false
    end

    local current = q.current

    -- HYBRID: Let Factorio mine natively, monitor mining_state
    -- When mining stops (entity depleted or finished), count inventory and move to next
    if not c.entity.mining_state or not c.entity.mining_state.mining then
      -- Mining stopped - count what we got
      local inv_after = c.entity.get_main_inventory().get_contents()
      local added = 0
      for name, data in pairs(inv_after) do
        local before = q.inv_snapshot[name] and q.inv_snapshot[name].count or 0
        added = added + (data.count - before)
      end
      q.harvested = q.harvested + added

      -- Check if target reached
      if q.harvested >= q.target then
        c.entity.mining_state = {mining = false}
        return true
      end

      -- Move to next resource
      q.current = nil
      if not M.start_mining_next(cid) then
        c.entity.mining_state = {mining = false}
        return true
      end
      q.inv_snapshot = c.entity.get_main_inventory().get_contents()
    end

    return false
  end)
end

function M.get_harvest_status(cid)
  local q = storage.harvest_queues[cid]
  if not q then return {active = false} end
  return {
    active = true,
    harvested = q.harvested,
    target = q.target,
    remaining = #q.entities,
    mining = q.current ~= nil
  }
end

function M.stop_harvest(cid)
  local q = storage.harvest_queues[cid]
  if not q then return {stopped = false} end

  local c = valid_companion(cid)
  if c then c.entity.mining_state = {mining = false} end

  local harvested = q.harvested
  storage.harvest_queues[cid] = nil
  return {stopped = true, harvested = harvested}
end

-- ============ CRAFT ============

function M.start_craft(cid, recipe, count)
  local c = valid_companion(cid)
  if not c then return {error = "Invalid companion"} end

  local proto = prototypes.recipe[recipe]
  if not proto then return {error = "Unknown recipe: " .. recipe} end

  local craftable = c.entity.get_craftable_count(recipe)
  if craftable < 1 then return {error = "Missing ingredients"} end

  local actual = math.min(count, craftable)
  local ticks = math.max(MIN_ACTION_TICKS, (proto.energy or 0.5) * 60)

  storage.craft_queues[cid] = {
    recipe = recipe,
    target = actual,
    crafted = 0,
    ticks_per = ticks,
    tick_start = game.tick
  }

  return {started = true, recipe = recipe, target = actual, ticks_per = ticks}
end

function M.tick_craft_queues()
  process_queue("craft_queues", function(cid, q, c)
    local elapsed = game.tick - q.tick_start
    if elapsed < q.ticks_per then return false end

    local crafted = c.entity.begin_crafting{recipe = q.recipe, count = 1}
    if crafted < 1 then return true end

    q.crafted = q.crafted + 1
    q.tick_start = game.tick
    return q.crafted >= q.target
  end)
end

function M.get_craft_status(cid)
  local q = storage.craft_queues[cid]
  if not q then return {active = false} end
  return {
    active = true,
    recipe = q.recipe,
    crafted = q.crafted,
    target = q.target,
    progress = math.floor((game.tick - q.tick_start) / q.ticks_per * 100)
  }
end

function M.stop_craft(cid)
  local q = storage.craft_queues[cid]
  if not q then return {stopped = false} end
  local crafted = q.crafted
  storage.craft_queues[cid] = nil
  return {stopped = true, crafted = crafted}
end

-- ============ BUILD ============

function M.start_build(cid, entity_name, position, direction)
  local c = valid_companion(cid)
  if not c then return {error = "Invalid companion"} end

  local dir = direction or defines.direction.north
  local dist = u.distance(c.entity.position, position)
  local reach = c.entity.build_distance or 10

  if dist > reach then
    return {error = "Too far (dist: " .. math.floor(dist) .. ", reach: " .. reach .. ")"}
  end

  local inv = c.entity.get_main_inventory()
  if inv.get_item_count(entity_name) < 1 then
    return {error = "No " .. entity_name .. " in inventory"}
  end

  local surface = c.entity.surface
  if not surface.can_place_entity{name = entity_name, position = position, direction = dir, force = c.entity.force} then
    return {error = "Cannot place here"}
  end

  storage.build_queues[cid] = {
    entity = entity_name,
    position = position,
    direction = dir,
    tick_start = game.tick
  }

  return {started = true, entity = entity_name, position = position}
end

function M.tick_build_queues()
  process_queue("build_queues", function(cid, q, c)
    if game.tick - q.tick_start < BUILD_TICKS then return false end

    local placed = c.entity.surface.create_entity{
      name = q.entity,
      position = q.position,
      direction = q.direction,
      force = c.entity.force
    }
    if placed then c.entity.remove_item{name = q.entity, count = 1} end
    return true
  end)
end

function M.get_build_status(cid)
  local q = storage.build_queues[cid]
  if not q then return {active = false} end
  return {
    active = true,
    entity = q.entity,
    position = q.position,
    progress = math.floor((game.tick - q.tick_start) / BUILD_TICKS * 100)
  }
end

function M.stop_build(cid)
  if not storage.build_queues[cid] then return {stopped = false} end
  storage.build_queues[cid] = nil
  return {stopped = true}
end

-- ============ COMBAT ============

function M.start_combat(cid, target_pos)
  local c = valid_companion(cid)
  if not c then return {error = "Invalid companion"} end

  local enemies = c.entity.surface.find_entities_filtered{
    position = target_pos,
    radius = 10,
    force = "enemy",
    type = {"unit", "unit-spawner"}
  }
  if #enemies == 0 then return {error = "No enemies"} end

  table.sort(enemies, function(a, b)
    return u.distance(a.position, c.entity.position) < u.distance(b.position, c.entity.position)
  end)

  storage.combat_queues[cid] = {
    targets = enemies,
    current = enemies[1],
    cooldown = 0,
    kills = 0
  }

  return {started = true, targets = #enemies}
end

function M.tick_combat_queues()
  process_queue("combat_queues", function(cid, q, c)
    if q.cooldown > 0 then
      q.cooldown = q.cooldown - TICK_INTERVAL
      return false
    end

    if not q.current or not q.current.valid then
      -- Find next valid target (build new list to avoid mutation during iteration)
      local valid_targets = {}
      for _, t in ipairs(q.targets) do
        if t.valid then valid_targets[#valid_targets + 1] = t end
      end
      q.targets = valid_targets

      if #q.targets == 0 then
        c.entity.shooting_state = {state = defines.shooting.not_shooting}
        return true
      end
      q.current = table.remove(q.targets, 1)
    end

    local dist = u.distance(c.entity.position, q.current.position)

    if dist <= ATTACK_RANGE then
      c.entity.shooting_state = {
        state = defines.shooting.shooting_enemies,
        position = q.current.position
      }
      q.cooldown = ATTACK_COOLDOWN
    else
      c.entity.shooting_state = {state = defines.shooting.not_shooting}
      local dir = u.get_direction(c.entity.position, q.current.position)
      if dir then c.entity.walking_state = {walking = true, direction = dir} end
    end
    return false
  end)
end

function M.get_combat_status(cid)
  local q = storage.combat_queues[cid]
  if not q then return {active = false} end

  local remaining = #q.targets
  if q.current and q.current.valid then remaining = remaining + 1 end

  return {
    active = true,
    targets_remaining = remaining,
    current_target = q.current and q.current.valid and q.current.name or nil
  }
end

function M.stop_combat(cid)
  local q = storage.combat_queues[cid]
  if not q then return {stopped = false} end

  local c = valid_companion(cid)
  if c then
    c.entity.shooting_state = {state = defines.shooting.not_shooting}
    c.entity.walking_state = {walking = false}
  end

  storage.combat_queues[cid] = nil
  return {stopped = true}
end

return M
