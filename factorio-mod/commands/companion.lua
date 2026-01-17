-- AI Companion v0.7.0 - Companion commands
local u = require("commands.init")

commands.add_command("fac_companion_spawn", nil, function(cmd)
  local ok, err = pcall(function()
    local param = cmd.parameter or ""
    local req_id = tonumber(param:match("id=(%d+)"))
    if req_id and storage.companions[req_id] then
      local c = storage.companions[req_id]
      if c.entity and c.entity.valid then u.json_response({status = "exists", id = req_id}); return end
    end
    local id = req_id or storage.companion_next_id
    if not req_id then storage.companion_next_id = storage.companion_next_id + 1
    elseif req_id >= storage.companion_next_id then storage.companion_next_id = req_id + 1 end
    local p = game.players[1]
    if not p or not p.valid then u.error_response("No player"); return end
    local e = p.surface.create_entity{name = "character", position = {x = p.position.x + id * 2, y = p.position.y}, force = p.force}
    if e then
      local color = u.get_companion_color(id)
      e.color = color
      storage.companions[id] = {entity = e, color = color, label = u.render_label(e, "#" .. id, color), spawned_tick = game.tick}
      game.print("[#" .. id .. " spawned]", u.print_color(color))
      u.json_response({spawned = true, id = id})
    else u.error_response("Failed to spawn") end
  end)
  if not ok then u.error_response(err) end
end)

commands.add_command("fac_companion_disappear", nil, function(cmd)
  local ok, err = pcall(function()
    local id, c = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    local pos, surf = c.entity.position, c.entity.surface
    local dropped = {}
    local inv = c.entity.get_inventory(defines.inventory.character_main)
    if inv then
      for name, count in pairs(inv.get_contents()) do
        surf.spill_item_stack(pos, {name = name, count = count}, true, nil, false)
        dropped[#dropped + 1] = {name = name, count = count}
      end
    end
    if c.label and c.label.valid then c.label.destroy() end
    c.entity.destroy()
    storage.context_clear_requests[id] = game.tick
    storage.companions[id] = nil
    storage.walking_queues[id] = nil
    game.print("[#" .. id .. " gone]", u.print_color(u.COLORS.system))
    u.json_response({id = id, disappeared = true, dropped = dropped})
  end)
  if not ok then u.error_response(err) end
end)

commands.add_command("fac_companion_position", nil, function(cmd)
  local ok, err = pcall(function()
    local id, c = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    local pos, surf = c.entity.position, c.entity.surface
    local nearby = surf.find_entities_filtered{position = pos, radius = 20, limit = 30}
    local summary = {}
    for _, e in ipairs(nearby) do if e.valid and e ~= c.entity then summary[e.name] = (summary[e.name] or 0) + 1 end end
    local players = {}
    for _, p in pairs(game.players) do
      if p.valid and p.surface == surf then
        local d = u.distance(p.position, pos)
        if d < 100 then players[#players + 1] = {name = p.name, distance = math.floor(d)} end
      end
    end
    u.json_response({id = id, position = {x = math.floor(pos.x * 10) / 10, y = math.floor(pos.y * 10) / 10}, nearby = summary, players = players})
  end)
  if not ok then u.error_response(err) end
end)

commands.add_command("fac_companion_health", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)%s*(%S*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local e = c.entity
    local r = {id = id, self = {health = e.health, max = e.prototype.max_health, pct = math.floor(e.health / e.prototype.max_health * 100)}}
    local tgt = args[2] ~= "" and args[2] or nil
    if tgt then
      local p = game.get_player(tgt)
      if p and p.valid and p.character then
        local ch = p.character
        r.target = {type = "player", name = p.name, health = ch.health, max = ch.prototype.max_health, pct = math.floor(ch.health / ch.prototype.max_health * 100)}
      else
        local tid, tc = u.find_companion(tgt)
        if tid then
          r.target = {type = "companion", id = tid, health = tc.entity.health, max = tc.entity.prototype.max_health, pct = math.floor(tc.entity.health / tc.entity.prototype.max_health * 100)}
        else r.target = {error = "Not found"} end
      end
    end
    u.json_response(r)
  end)
  if not ok then u.error_response(err) end
end)

commands.add_command("fac_companion_inventory", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)%s*([%d.-]*)%s*([%d.-]*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local x, y = tonumber(args[2]), tonumber(args[3])
    if x and y then
      local es = c.entity.surface.find_entities_filtered{position = {x=x, y=y}, radius = 2}
      local t
      for _, e in ipairs(es) do if e.valid and e ~= c.entity then t = e; break end end
      if not t then u.json_response({id = id, error = "No entity"}); return end
      local items = {}
      for _, it in ipairs({{defines.inventory.chest, "chest"}, {defines.inventory.furnace_source, "in"}, {defines.inventory.furnace_result, "out"}, {defines.inventory.fuel, "fuel"}}) do
        local inv = t.get_inventory(it[1])
        if inv then for name, count in pairs(inv.get_contents()) do items[#items + 1] = {name = name, count = count, slot = it[2]} end end
      end
      u.json_response({id = id, entity = t.name, items = items})
    else
      local inv = c.entity.get_inventory(defines.inventory.character_main)
      local items = {}
      for name, count in pairs(inv.get_contents()) do items[#items + 1] = {name = name, count = count} end
      table.sort(items, function(a, b) return a.count > b.count end)
      u.json_response({id = id, items = items, slots = #inv, used = #items})
    end
  end)
  if not ok then u.error_response(err) end
end)
