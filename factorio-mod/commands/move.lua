-- AI Companion v0.7.0 - Move commands
local u = require("commands.init")

commands.add_command("fac_move_to", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+([%d.-]+)%s+([%d.-]+)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not x or not y then u.error_response("Invalid coordinates"); return end
    storage.walking_queues[id] = {target = {x = x, y = y}}
    u.json_response({id = id, walking_to = {x = x, y = y}})
  end)
end)

commands.add_command("fac_move_follow", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(.+)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local pname = args[2]
    if not game.get_player(pname) then u.error_response("Player not found"); return end
    storage.walking_queues[id] = {follow_player = pname}
    u.json_response({id = id, following = pname})
  end)
end)

commands.add_command("fac_move_stop", nil, function(cmd)
  u.safe_command(function()
    local id, c = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    storage.walking_queues[id] = nil
    c.entity.walking_state = {walking = false}
    u.json_response({id = id, stopped = true})
  end)
end)
