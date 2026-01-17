-- AI Companion v0.7.0 - Resource commands
local u = require("commands.init")

local normalize = {copper = "copper-ore", iron = "iron-ore", coal = "coal", stone = "stone", uranium = "uranium-ore", oil = "crude-oil"}

commands.add_command("fac_resource_list", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)%s*(%S*)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local filter = args[2] ~= "" and args[2] or nil
    local radius = tonumber(args[3]) or 50
    local pos = c.entity.position
    local res = c.entity.surface.find_entities_filtered{type = "resource", position = pos, radius = radius, limit = 20}
    local found = {}
    for _, r in ipairs(res) do
      if not filter or r.name == filter then
        found[#found + 1] = {name = r.name, position = {x = math.floor(r.position.x), y = math.floor(r.position.y)}, amount = r.amount, distance = math.floor(u.distance(pos, r.position))}
      end
    end
    table.sort(found, function(a, b) return a.distance < b.distance end)
    u.json_response({id = id, resources = found, count = #found})
  end)
  if not ok then u.error_response(err) end
end)

commands.add_command("fac_resource_mine", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)%s+([%d.-]+)%s+([%d.-]+)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local x, y, count = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 1
    if not x or not y then u.error_response("Invalid coordinates"); return end
    local tpos = {x = x, y = y}
    local res = c.entity.surface.find_entities_filtered{type = "resource", position = tpos, radius = 2, limit = 1}
    if #res == 0 then u.json_response({id = id, error = "No resource"}); return end
    local r = res[1]
    if u.distance(c.entity.position, tpos) > 5 then u.json_response({id = id, error = "Too far"}); return end
    local to_mine = math.min(count, r.amount)
    if c.entity.mine_entity(r, false) then
      u.json_response({id = id, mined = true, resource = r.name})
    else
      local item = r.prototype.mineable_properties.products[1].name
      r.amount = r.amount - to_mine
      c.entity.insert{name = item, count = to_mine}
      if r.amount <= 0 then r.destroy() end
      u.json_response({id = id, mined = true, resource = r.name, amount = to_mine, item = item})
    end
  end)
  if not ok then u.error_response(err) end
end)

commands.add_command("fac_resource_nearest", nil, function(cmd)
  local ok, err = pcall(function()
    local args = u.parse_args("^(%S+)%s+(%S+)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local name = normalize[args[2]] or args[2]
    local pos = c.entity.position
    local area = {{pos.x - 200, pos.y - 200}, {pos.x + 200, pos.y + 200}}
    local es = c.entity.surface.find_entities_filtered{area = area, name = name, limit = 100}
    if #es == 0 then u.json_response({id = id, error = "Not found"}); return end
    local closest, min = nil, math.huge
    for _, e in ipairs(es) do local d = u.distance(e.position, pos); if d < min then min, closest = d, e end end
    u.json_response({id = id, resource = closest.name, position = {x = math.floor(closest.position.x), y = math.floor(closest.position.y)}, distance = math.floor(min), amount = closest.amount})
  end)
  if not ok then u.error_response(err) end
end)
