# FLE Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate FLE patterns for realistic tick-based actions, combat system, and reduced agent noise.

**Architecture:** Expand queues.lua with craft/build/combat queues, add enemy detection, update subagent prompts for focused responses.

**Tech Stack:** Lua (Factorio mod), TypeScript (orchestration), RCON commands

---

## Task 1: Expand queues.lua with Craft Queue

**Files:**
- Modify: `factorio-mod/commands/queues.lua`

**Step 1: Add craft queue initialization**

In `M.init()`, add:
```lua
storage.craft_queues = storage.craft_queues or {}
```

**Step 2: Add start_craft function**

```lua
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
```

**Step 3: Add tick_craft_queues function**

```lua
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
```

**Step 4: Add status and stop functions**

```lua
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
```

**Step 5: Commit**

```bash
git add factorio-mod/commands/queues.lua
git commit -m "feat(queues): add craft queue system"
```

---

## Task 2: Add Craft Commands to item.lua

**Files:**
- Modify: `factorio-mod/commands/item.lua`

**Step 1: Add craft_start command**

```lua
local queues = require("commands.queues")

commands.add_command("fac_item_craft_start", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)%s+(%S+)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local recipe = args[2]
    local count = tonumber(args[3]) or 1
    local result = queues.start_craft(id, recipe, count)
    u.json_response(vim.tbl_extend("force", {id = id}, result))
  end)
  if not ok then u.error_response(err) end
end)
```

**Step 2: Add craft_status command**

```lua
commands.add_command("fac_item_craft_status", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local status = queues.get_craft_status(id)
    u.json_response({id = id, status = status})
  end)
  if not ok then u.error_response(err) end
end)
```

**Step 3: Add craft_stop command**

```lua
commands.add_command("fac_item_craft_stop", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local result = queues.stop_craft(id)
    u.json_response({id = id, stopped = result.stopped, crafted = result.crafted or 0})
  end)
  if not ok then u.error_response(err) end
end)
```

**Step 4: Add queues require at top of file**

At the top of `item.lua`, add:
```lua
local queues = require("commands.queues")
```

**Step 5: Commit**

```bash
git add factorio-mod/commands/item.lua
git commit -m "feat(item): add realistic craft commands"
```

---

## Task 3: Add Build Queue to queues.lua

**Files:**
- Modify: `factorio-mod/commands/queues.lua`

**Step 1: Add build queue initialization**

In `M.init()`, add:
```lua
storage.build_queues = storage.build_queues or {}
```

**Step 2: Add start_build function**

```lua
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
```

**Step 3: Add tick_build_queues function**

```lua
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
```

**Step 4: Add status and stop functions**

```lua
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
```

**Step 5: Commit**

```bash
git add factorio-mod/commands/queues.lua
git commit -m "feat(queues): add build queue system"
```

---

## Task 4: Add Build Commands to building.lua

**Files:**
- Modify: `factorio-mod/commands/building.lua`

**Step 1: Add queues require**

At top of file:
```lua
local queues = require("commands.queues")
```

**Step 2: Add place_start command**

```lua
commands.add_command("fac_building_place_start", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)%s+(%S+)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s*(%S*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local entity = args[2]
    local x, y = tonumber(args[3]), tonumber(args[4])
    local dir = args[5] ~= "" and defines.direction[args[5]] or defines.direction.north
    local result = queues.start_build(id, entity, {x = x, y = y}, dir)
    u.json_response(vim.tbl_extend("force", {id = id}, result))
  end)
  if not ok then u.error_response(err) end
end)
```

**Step 3: Add place_status command**

```lua
commands.add_command("fac_building_place_status", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local status = queues.get_build_status(id)
    u.json_response({id = id, status = status})
  end)
  if not ok then u.error_response(err) end
end)
```

**Step 4: Commit**

```bash
git add factorio-mod/commands/building.lua
git commit -m "feat(building): add realistic place commands"
```

---

## Task 5: Create combat.lua with Enemy Detection

**Files:**
- Create: `factorio-mod/commands/combat.lua`

**Step 1: Create combat.lua file**

```lua
-- AI Companion v0.8.0 - Combat commands
local u = require("commands.init")
local queues = require("commands.queues")

-- Detect nearby enemies
commands.add_command("fac_world_enemies", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local radius = tonumber(args[2]) or 30

    local enemies = c.entity.surface.find_entities_filtered{
      position = c.entity.position,
      radius = radius,
      force = "enemy",
      type = {"unit", "unit-spawner", "turret"}
    }

    local result = {}
    for _, e in ipairs(enemies) do
      if e.valid then
        result[#result + 1] = {
          name = e.name,
          type = e.type,
          position = {x = math.floor(e.position.x), y = math.floor(e.position.y)},
          health = e.health,
          max_health = e.prototype.max_health,
          distance = math.floor(u.distance(c.entity.position, e.position))
        }
      end
    end

    table.sort(result, function(a, b) return a.distance < b.distance end)

    local threat = "safe"
    if #result > 5 then threat = "danger"
    elseif #result > 0 then threat = "caution" end

    u.json_response({id = id, enemies = result, count = #result, threat_level = threat})
  end)
  if not ok then u.error_response(err) end
end)
```

**Step 2: Commit**

```bash
git add factorio-mod/commands/combat.lua
git commit -m "feat(combat): add enemy detection command"
```

---

## Task 6: Add Combat Queue to queues.lua

**Files:**
- Modify: `factorio-mod/commands/queues.lua`

**Step 1: Add combat queue initialization**

In `M.init()`:
```lua
storage.combat_queues = storage.combat_queues or {}
```

**Step 2: Add start_combat function**

```lua
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
```

**Step 3: Add tick_combat_queues function**

```lua
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
```

**Step 4: Add status and stop functions**

```lua
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
```

**Step 5: Commit**

```bash
git add factorio-mod/commands/queues.lua
git commit -m "feat(queues): add combat queue system"
```

---

## Task 7: Add Combat Commands

**Files:**
- Modify: `factorio-mod/commands/combat.lua`

**Step 1: Add attack commands**

```lua
commands.add_command("fac_action_attack_start", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local x, y = tonumber(args[2]), tonumber(args[3])
    local result = queues.start_combat(id, {x = x, y = y})
    u.json_response(vim.tbl_extend("force", {id = id}, result))
  end)
  if not ok then u.error_response(err) end
end)

commands.add_command("fac_action_attack_status", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local status = queues.get_combat_status(id)
    u.json_response({id = id, status = status})
  end)
  if not ok then u.error_response(err) end
end)

commands.add_command("fac_action_attack_stop", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local result = queues.stop_combat(id)
    u.json_response({id = id, stopped = result.stopped, kills = result.kills or 0})
  end)
  if not ok then u.error_response(err) end
end)
```

**Step 2: Commit**

```bash
git add factorio-mod/commands/combat.lua
git commit -m "feat(combat): add attack start/status/stop commands"
```

---

## Task 8: Update control.lua with New Tick Handlers

**Files:**
- Modify: `factorio-mod/control.lua`

**Step 1: Add combat.lua require**

After line `require("commands.help")`, add:
```lua
require("commands.combat")
```

**Step 2: Update on_nth_tick handler**

Replace the existing `script.on_nth_tick(5, ...)` with:

```lua
script.on_nth_tick(5, function(ev)
  if ev.tick % 1800 == 0 then cleanup_messages() end

  -- Process all queues
  queues.tick_harvest_queues()
  queues.tick_craft_queues()
  queues.tick_build_queues()
  queues.tick_combat_queues()

  -- Process walking queues
  if not storage.walking_queues then return end
  for cid, q in pairs(storage.walking_queues) do
    local c = u.get_companion(cid)
    if not c then storage.walking_queues[cid] = nil; goto skip end
    if q.follow_player then
      local p = game.players[q.follow_player]
      if p and p.valid then q.target = {x = p.position.x, y = p.position.y}
      else storage.walking_queues[cid] = nil; goto skip end
    end
    if not q.target then storage.walking_queues[cid] = nil; goto skip end
    local e, dist = c.entity, u.distance(c.entity.position, q.target)
    if dist < 2 then
      e.walking_state = {walking = false}
      if not q.follow_player then storage.walking_queues[cid] = nil end
    else
      local dir = u.get_direction(e.position, q.target)
      if dir then e.walking_state = {walking = true, direction = dir} end
    end
    ::skip::
  end
end)
```

**Step 3: Commit**

```bash
git add factorio-mod/control.lua
git commit -m "feat(control): add tick handlers for all queues"
```

---

## Task 9: Update CLAUDE.md with New Commands

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add new commands to the companion template**

In the "AVAILABLE COMMANDS" section, add:

```markdown
### Combat
/fac_world_enemies N [radius]     -- List nearby enemies (biters, spitters, spawners)
/fac_action_attack_start N x y    -- Start attacking enemies at position
/fac_action_attack_status N       -- Check combat status
/fac_action_attack_stop N         -- Stop attacking

### Realistic Crafting (tick-based)
/fac_item_craft_start N recipe count  -- Start crafting (takes time)
/fac_item_craft_status N              -- Check crafting progress
/fac_item_craft_stop N                -- Stop crafting

### Realistic Building (tick-based)
/fac_building_place_start N entity x y [dir]  -- Start placing (takes 1s)
/fac_building_place_status N                   -- Check placement progress
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add new commands to companion template"
```

---

## Task 10: Update info.json Version

**Files:**
- Modify: `factorio-mod/info.json`

**Step 1: Bump version to 0.8.0**

Change version from "0.7.0" to "0.8.0"

**Step 2: Commit**

```bash
git add factorio-mod/info.json
git commit -m "chore: bump version to 0.8.0"
```

---

## Task 11: Deploy and Test

**Step 1: Deploy mod**

```bash
powershell -Command "Copy-Item -Path 'C:\Users\lveil\Desktop\Projects\factorio-ai-companion\factorio-mod\*' -Destination 'C:\Users\lveil\AppData\Roaming\Factorio\mods\ai-companion\' -Recurse -Force"
```

**Step 2: Test checklist**

In Factorio (multiplayer mode):
- [ ] `/fac spawn 1` - Spawn companion
- [ ] `/fac_world_enemies 1 50` - Should return empty or list enemies
- [ ] `/fac_item_craft_start 1 iron-gear-wheel 5` - Start crafting
- [ ] `/fac_item_craft_status 1` - Check progress
- [ ] `/fac_resource_mine 1 <x> <y> 10` - Test mining animation
- [ ] `/fac_resource_mine_status 1` - Check mining progress

**Step 3: Final commit**

```bash
git add -A
git commit -m "v0.8.0: FLE integration - tick-based queues, combat system"
```

---

## Summary

| Task | Description | Est. Lines |
|------|-------------|------------|
| 1 | Craft queue in queues.lua | ~60 |
| 2 | Craft commands in item.lua | ~40 |
| 3 | Build queue in queues.lua | ~50 |
| 4 | Build commands in building.lua | ~30 |
| 5 | Create combat.lua with enemy detection | ~40 |
| 6 | Combat queue in queues.lua | ~70 |
| 7 | Combat commands | ~40 |
| 8 | Update control.lua tick handlers | ~10 |
| 9 | Update CLAUDE.md | ~20 |
| 10 | Bump version | ~1 |
| 11 | Deploy and test | - |

**Total: ~360 lines of Lua code**
