-- AI Companion v0.7.0 - Help
local u = require("commands.init")

commands.add_command("fac_help", nil, function()
  u.json_response({
    version = "0.7.0",
    commands = 38,
    categories = {"action", "building", "chat", "companion", "context", "item", "move", "research", "resource", "world"},
    action = {"attack", "flee", "patrol", "wololo"},
    building = {"can_place", "empty", "fill", "fuel", "info", "place", "recipe", "remove", "rotate"},
    chat = {"get", "say"},
    companion = {"disappear", "health", "inventory", "position", "spawn"},
    context = {"clear", "check"},
    item = {"craft", "pick", "recipes"},
    move = {"follow", "stop", "to"},
    research = {"get", "progress", "set"},
    resource = {"list", "mine", "nearest"},
    world = {"nearest", "scan"},
    player = {"/fac <msg>", "/fac <id> <msg>", "/fac spawn", "/fac list", "/fac kill", "/fac clear", "/fac name"}
  })
end)
