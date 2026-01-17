-- AI Companion v0.3.6 - Factorio 2.x
-- Chat bridge with orchestrator + colored companion threads

-- Factorio 2.x uses {color = {r,g,b}} for game.print
local function print_color(color)
  return {color = color}
end

local COLORS = {
  player = {r=0.4, g=0.8, b=1},      -- cyan: player messages
  orchestrator = {r=0.3, g=1, b=0.3}, -- green: Claude orchestrator
  system = {r=1, g=0.5, b=0},         -- yellow: system messages
  error = {r=1, g=0, b=0}             -- red: errors
}

-- Distinct colors for companions (cycle through)
local COMPANION_COLORS = {
  {r=1, g=0.6, b=0.2},    -- orange
  {r=0.8, g=0.4, b=1},    -- purple
  {r=1, g=1, b=0.3},      -- yellow
  {r=0.4, g=1, b=0.8},    -- teal
  {r=1, g=0.4, b=0.6},    -- pink
  {r=0.6, g=0.8, b=1},    -- light blue
  {r=1, g=0.8, b=0.4},    -- gold
  {r=0.7, g=1, b=0.5},    -- lime
}

local function get_companion_color(id)
  local index = ((id - 1) % #COMPANION_COLORS) + 1
  return COMPANION_COLORS[index]
end

-- Render label above companion
local function render_companion_label(entity, id, color)
  if not rendering then return nil end
  return rendering.draw_text{
    text = "#" .. id,
    surface = entity.surface,
    target = entity,
    target_offset = {0, -2.5},
    color = color,
    scale = 1.5,
    alignment = "center",
    use_rich_text = false
  }
end

local function init_storage()
  storage.companion_messages = storage.companion_messages or {}
  storage.companions = storage.companions or {}
  storage.companion_next_id = storage.companion_next_id or 1
  storage.walking_queues = storage.walking_queues or {}
  storage.errors = storage.errors or {}
end

local function log_error(context, err)
  table.insert(storage.errors, {
    context = context,
    error = tostring(err),
    tick = game.tick
  })
  if #storage.errors > 50 then table.remove(storage.errors, 1) end
end

script.on_init(function()
  init_storage()
  game.print("[AI Companion] v0.3.6 initialized. Type /fac for help", print_color(COLORS.system))
end)

script.on_configuration_changed(function()
  init_storage()
  game.print("[AI Companion] Updated to v0.3.6", print_color(COLORS.system))
end)

local function json_response(data)
  local ok, result = pcall(helpers.table_to_json, data)
  rcon.print(ok and result or '{"error":"JSON failed"}')
end

local function error_response(msg, context)
  log_error(context or "rcon", msg)
  rcon.print('{"error":"' .. tostring(msg) .. '"}')
end

local function get_companion(id)
  local c = storage.companions[id]
  return (c and c.entity and c.entity.valid) and c or nil
end

-- Find companion by name or ID, returns id and companion
local function find_companion(identifier)
  local id = tonumber(identifier)
  if id then
    local c = get_companion(id)
    if c then return id, c end
  end
  for cid, c in pairs(storage.companions) do
    if c.name and c.name:lower() == identifier:lower() then
      if c.entity and c.entity.valid then
        return cid, c
      end
    end
  end
  return nil, nil
end

local function get_companion_display(id)
  local c = storage.companions[id]
  if c and c.name then return c.name .. "(#" .. id .. ")" end
  return "#" .. id
end

local function parse_args(pattern, args)
  if not args then return {} end
  return {args:match(pattern)}
end

local function get_direction(from, to)
  local dx, dy = to.x - from.x, to.y - from.y
  if math.abs(dx) < 0.5 and math.abs(dy) < 0.5 then return nil end
  local angle = math.atan2(dy, dx)
  local deg = angle * 180 / math.pi
  if deg < 0 then deg = deg + 360 end
  if deg >= 337.5 or deg < 22.5 then return defines.direction.east end
  if deg >= 22.5 and deg < 67.5 then return defines.direction.southeast end
  if deg >= 67.5 and deg < 112.5 then return defines.direction.south end
  if deg >= 112.5 and deg < 157.5 then return defines.direction.southwest end
  if deg >= 157.5 and deg < 202.5 then return defines.direction.west end
  if deg >= 202.5 and deg < 247.5 then return defines.direction.northwest end
  if deg >= 247.5 and deg < 292.5 then return defines.direction.north end
  if deg >= 292.5 and deg < 337.5 then return defines.direction.northeast end
  return defines.direction.east
end

local subcommands = {}

subcommands.spawn = function(player, args)
  local count = math.min(tonumber(args) or 1, 10)
  local spawned = {}
  for i = 1, count do
    local id = storage.companion_next_id
    storage.companion_next_id = storage.companion_next_id + 1
    local entity = player.surface.create_entity{
      name = "character",
      position = {x = player.position.x + (i * 2), y = player.position.y},
      force = player.force
    }
    if entity then
      local color = get_companion_color(id)
      entity.color = color
      local label = render_companion_label(entity, id, color)
      storage.companions[id] = {entity = entity, color = color, label = label, spawned_by = player.name, spawned_tick = game.tick}
      table.insert(spawned, id)
      game.print("[#" .. id .. " spawned]", print_color(color))
    end
  end
  if #spawned == 0 then game.print("[AI Companion] Failed to spawn", print_color(COLORS.error)) end
end

subcommands.list = function(player, args)
  local count = 0
  for id, c in pairs(storage.companions) do
    if c.entity and c.entity.valid then
      local pos = c.entity.position
      game.print(string.format("[#%d] at (%.1f, %.1f)", id, pos.x, pos.y), print_color(c.color or get_companion_color(id)))
      count = count + 1
    else storage.companions[id] = nil end
  end
  if count == 0 then game.print("[AI Companion] No companions. Use /fac spawn", print_color(COLORS.system)) end
end

subcommands.kill = function(player, args)
  local id = tonumber(args)
  local killed = 0
  local function kill_one(cid)
    local c = storage.companions[cid]
    if c then
      if c.label and rendering then rendering.destroy(c.label) end
      if c.entity and c.entity.valid then c.entity.destroy(); killed = killed + 1 end
      storage.companions[cid] = nil
    end
  end
  if id then kill_one(id) else for cid, _ in pairs(storage.companions) do kill_one(cid) end end
  game.print("[AI Companion] Killed " .. killed, print_color(COLORS.system))
end

subcommands.clear = function(player, args)
  local count = #storage.companion_messages
  storage.companion_messages = {}
  game.print("[AI Companion] Cleared " .. count .. " msg(s)", print_color(COLORS.system))
end

subcommands.name = function(player, args)
  local id_str, new_name = args:match("^(%d+)%s+(.+)$")
  local id = tonumber(id_str)
  if not id or not new_name then player.print("[AI Companion] Usage: /fac name <id> <name>", print_color(COLORS.system)); return end
  local c = get_companion(id)
  if not c then player.print("[AI Companion] #" .. id .. " not found", print_color(COLORS.error)); return end
  c.name = new_name
  if c.label and rendering then rendering.destroy(c.label) end
  local color = c.color or get_companion_color(id)
  c.label = rendering.draw_text{text = new_name .. "(#" .. id .. ")", surface = c.entity.surface, target = c.entity, target_offset = {0, -2.5}, color = color, scale = 1.5, alignment = "center", use_rich_text = false}
  game.print("[AI Companion] #" .. id .. " named '" .. new_name .. "'", print_color(color))
end

local function handle_fac_command(command)
  local ok, err = pcall(function()
    local player = command.player_index and game.players[command.player_index]
    if command.player_index and (not player or not player.valid) then return end
    local param = command.parameter
    if not param or param == "" then
      if player then player.print("/fac <msg> | <id> <msg> | spawn [n] | list | kill [id] | clear | name <id> <name>", print_color(COLORS.system)) end
      return
    end
    local first_word, rest_msg = param:match("^(%S+)%s+(.+)$")
    if first_word and rest_msg and not subcommands[first_word] then
      local id, companion = find_companion(first_word)
      if id and companion then
        table.insert(storage.companion_messages, {player = player.name, message = rest_msg, tick = game.tick, read = false, target_companion = id})
        local color = companion.color or get_companion_color(id)
        game.print("[" .. player.name .. " -> " .. get_companion_display(id) .. "] " .. rest_msg, print_color(color))
        return
      end
    end
    local cmd, rest = param:match("^(%S+)%s*(.*)")
    if subcommands[cmd] then subcommands[cmd](player, rest)
    else
      table.insert(storage.companion_messages, {player = player and player.name or "server", message = param, tick = game.tick, read = false})
      game.print("[" .. (player and player.name or "server") .. "] " .. param, print_color(COLORS.player))
    end
  end)
  if not ok then log_error("fac_command", err); game.print("[AI Companion] Error: " .. tostring(err), print_color(COLORS.error)) end
end

commands.add_command("fac", "Chat with Claude AI", handle_fac_command)

-- RCON commands (see full control.lua for complete implementation)
commands.add_command("companion_get_messages", nil, function(command)
  local ok, err = pcall(function()
    local filter = command.parameter
    local filter_id = tonumber(filter)
    local orchestrator_only = filter == "orchestrator"
    local msgs = {}
    for _, m in ipairs(storage.companion_messages) do
      if not m.read then
        local include = (not filter or filter == "") or (orchestrator_only and not m.target_companion) or (filter_id and m.target_companion == filter_id)
        if include then
          local out = {player = m.player, message = m.message, tick = m.tick}
          if m.target_companion then out.target_companion = m.target_companion end
          table.insert(msgs, out); m.read = true
        end
      end
    end
    json_response(msgs)
  end)
  if not ok then error_response(err) end
end)

commands.add_command("companion_send", nil, function(command)
  if command.parameter and command.parameter ~= "" then
    game.print("[Claude] " .. command.parameter, print_color(COLORS.orchestrator))
  end
end)

commands.add_command("companion_say", nil, function(command)
  local ok, err = pcall(function()
    local args = parse_args("^(%S+)%s+(.+)$", command.parameter)
    local id, companion = find_companion(args[1])
    if not id then error_response("Companion not found"); return end
    local color = companion.color or get_companion_color(id)
    game.print("[" .. get_companion_display(id) .. "] " .. args[2], print_color(color))
    json_response({id = id, name = companion.name, said = args[2]})
  end)
  if not ok then error_response(err) end
end)

-- Walking queue update
script.on_nth_tick(5, function(event)
  if not storage.walking_queues then return end
  for cid, q in pairs(storage.walking_queues) do
    local c = get_companion(cid)
    if not c then storage.walking_queues[cid] = nil; goto skip end
    if q.follow_player then
      local player = game.players[q.follow_player]
      if player and player.valid then q.target = {x = player.position.x, y = player.position.y}
      else storage.walking_queues[cid] = nil; goto skip end
    end
    if not q.target then storage.walking_queues[cid] = nil; goto skip end
    local e = c.entity
    local dist = math.sqrt((e.position.x - q.target.x)^2 + (e.position.y - q.target.y)^2)
    if dist < 2 then e.walking_state = {walking = false}; if not q.follow_player then storage.walking_queues[cid] = nil end
    else local dir = get_direction(e.position, q.target); if dir then e.walking_state = {walking = true, direction = dir} end end
    ::skip::
  end
end)
