-- AI Companion v0.9.0 - Factorio 2.x
local u = require("commands.init")
local queues = require("commands.queues")

local function init_storage()
  storage.companion_messages = storage.companion_messages or {}
  storage.companions = storage.companions or {}
  storage.companion_next_id = storage.companion_next_id or 1
  storage.walking_queues = storage.walking_queues or {}
  storage.context_clear_requests = storage.context_clear_requests or {}
  storage.errors = storage.errors or {}
  queues.init()
end

local function cleanup_messages()
  local new_msgs, now = {}, game.tick
  for _, m in ipairs(storage.companion_messages) do
    if not m.read or (now - m.tick) < 18000 then new_msgs[#new_msgs + 1] = m end
  end
  if #new_msgs > 100 then
    local trimmed = {}
    for i = #new_msgs - 99, #new_msgs do trimmed[#trimmed + 1] = new_msgs[i] end
    new_msgs = trimmed
  end
  storage.companion_messages = new_msgs
end

script.on_init(function()
  init_storage()
  game.print("[AI Companion] v0.9.0 ready. /fac for help", u.print_color(u.COLORS.system))
end)

script.on_configuration_changed(function()
  init_storage()
  game.print("[AI Companion] Updated to v0.9.0", u.print_color(u.COLORS.system))
end)

local subcommands = {}

subcommands.spawn = function(player, args)
  local count = math.min(tonumber(args) or 1, 10)
  table.insert(storage.companion_messages, {player = player.name, message = "spawn " .. count, tick = game.tick, read = false, spawn_request = count})
  game.print("[" .. player.name .. "] Spawn " .. count .. " companion(s)...", u.print_color(u.COLORS.player))
end

subcommands.list = function(player)
  local count = 0
  for id, c in pairs(storage.companions) do
    if c.entity and c.entity.valid then
      local p = c.entity.position
      game.print(string.format("[#%d] (%.1f, %.1f)", id, p.x, p.y), u.print_color(c.color or u.get_companion_color(id)))
      count = count + 1
    else storage.companions[id] = nil end
  end
  if count == 0 then game.print("[AI Companion] No companions. /fac spawn", u.print_color(u.COLORS.system)) end
end

subcommands.kill = function(player, args)
  local id, killed = tonumber(args), 0
  local function kill_one(cid)
    local c = storage.companions[cid]
    if c then
      if c.label and c.label.valid then c.label.destroy() end
      if c.entity and c.entity.valid then c.entity.destroy(); killed = killed + 1 end
      storage.companions[cid] = nil
    end
  end
  if id then kill_one(id) else for cid in pairs(storage.companions) do kill_one(cid) end end
  game.print("[AI Companion] Killed " .. killed, u.print_color(u.COLORS.system))
end

subcommands.clear = function()
  local count = #storage.companion_messages
  storage.companion_messages = {}
  game.print("[AI Companion] Cleared " .. count .. " msg(s)", u.print_color(u.COLORS.system))
end

subcommands.name = function(player, args)
  local id_str, name = args:match("^(%d+)%s+(.+)$")
  local id = tonumber(id_str)
  if not id or not name then player.print("/fac name <id> <name>", u.print_color(u.COLORS.system)); return end
  local c = u.get_companion(id)
  if not c then player.print("#" .. id .. " not found", u.print_color(u.COLORS.error)); return end
  c.name = name
  if c.label and c.label.valid then c.label.destroy() end
  local color = c.color or u.get_companion_color(id)
  c.label = u.render_label(c.entity, name .. "(#" .. id .. ")", color)
  game.print("#" .. id .. " -> " .. name, u.print_color(color))
end

local function handle_fac(cmd)
  local ok, err = pcall(function()
    local player = cmd.player_index and game.players[cmd.player_index]
    if cmd.player_index and (not player or not player.valid) then return end
    local param = cmd.parameter
    if not param or param == "" then
      if player then player.print("/fac <msg> | <id> <msg> | spawn | list | kill | clear | name", u.print_color(u.COLORS.system)) end
      return
    end
    local first, rest = param:match("^(%S+)%s+(.+)$")
    if first and rest and not subcommands[first] then
      local id, comp = u.find_companion(first)
      if id then
        table.insert(storage.companion_messages, {player = player.name, message = rest, tick = game.tick, read = false, target_companion = id})
        game.print("[" .. player.name .. " -> " .. u.get_companion_display(id) .. "] " .. rest, u.print_color(comp.color or u.get_companion_color(id)))
        return
      end
    end
    local sub, args = param:match("^(%S+)%s*(.*)")
    if subcommands[sub] then subcommands[sub](player, args)
    else
      table.insert(storage.companion_messages, {player = player and player.name or "server", message = param, tick = game.tick, read = false})
      game.print("[" .. (player and player.name or "server") .. "] " .. param, u.print_color(u.COLORS.player))
    end
  end)
  if not ok then u.error_response(err, "fac"); game.print("Error: " .. tostring(err), u.print_color(u.COLORS.error)) end
end

commands.add_command("fac", "AI Companion", handle_fac)

require("commands.action")
require("commands.building")
require("commands.chat")
require("commands.companion")
require("commands.context")
require("commands.item")
require("commands.move")
require("commands.research")
require("commands.resource")
require("commands.world")
require("commands.combat")
require("commands.help")

script.on_nth_tick(5, function(ev)
  if ev.tick % 1800 == 0 then cleanup_messages() end
  -- Process all tick-based queues (realistic actions)
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
