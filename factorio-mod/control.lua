-- AI Companion Mod
-- Captures /companion commands with FLE-inspired patterns:
-- - pcall() error handling
-- - Message cleanup to prevent memory leaks
-- - Safe JSON serialization
-- - Configuration change handling

-- Initialize global state on new game
script.on_init(function()
  storage.companion_messages = {}
  storage.companion_tick_counter = 0
  game.print("[AI Companion] Mod initialized! Type /companion <message> to chat with Claude", {r=0.5, g=0.8, b=1})
end)

-- Handle mod updates
script.on_configuration_changed(function()
  storage.companion_messages = storage.companion_messages or {}
  storage.companion_tick_counter = storage.companion_tick_counter or 0
  game.print("[AI Companion] Mod updated!", {r=0.5, g=0.8, b=1})
end)

-- Chat event handler with error handling
script.on_event(defines.events.on_console_chat, function(event)
  -- Wrap in pcall for safety (FLE pattern)
  local success, error_msg = pcall(function()
    local player = game.players[event.player_index]
    if not player or not player.valid then
      return
    end

    local message = event.message

    -- Check if message starts with /companion
    local content = message:match("^/companion%s+(.+)$")
    if content then
      table.insert(storage.companion_messages, {
        player = player.name,
        message = content,
        tick = game.tick,
        read = false
      })

      -- Acknowledge in chat
      player.print("[AI Companion] Message received: " .. content, {r=0.5, g=0.8, b=1})
    end
  end)

  if not success then
    game.print("[AI Companion] Error processing message: " .. tostring(error_msg), {r=1, g=0, b=0})
  end
end)

-- RCON command to get pending messages with safe JSON serialization
commands.add_command("companion_get_messages", "Get unread companion messages", function(command)
  local success, result = pcall(function()
    local messages = {}

    for i, msg in ipairs(storage.companion_messages) do
      if not msg.read then
        table.insert(messages, {
          player = msg.player,
          message = msg.message,
          tick = msg.tick
        })
        msg.read = true
      end
    end

    -- Safe JSON conversion (FLE pattern)
    local json_success, json_result = pcall(game.table_to_json, messages)
    if json_success then
      rcon.print(json_result)
    else
      rcon.print('{"error": "JSON serialization failed"}')
    end
  end)

  if not success then
    rcon.print('{"error": "' .. tostring(result) .. '"}')
  end
end)

-- RCON command to send response to chat
commands.add_command("companion_send", "Send companion response", function(command)
  local success, error_msg = pcall(function()
    local message = command.parameter
    if message and message ~= "" then
      game.print("[AI Companion] " .. message, {r=0.5, g=1, b=0.5})
    end
  end)

  if not success then
    game.print("[AI Companion] Error sending message", {r=1, g=0, b=0})
  end
end)

-- Cleanup command to prevent memory leaks (FLE pattern)
commands.add_command("companion_cleanup", "Cleanup old messages", function(command)
  local success, result = pcall(function()
    local cutoff_ticks = 60 * 60 * 10 -- 10 minutes at 60 ticks/second
    local current_tick = game.tick
    local removed_count = 0

    -- Remove from end to avoid index shifting issues
    for i = #storage.companion_messages, 1, -1 do
      local msg = storage.companion_messages[i]
      if (current_tick - msg.tick) > cutoff_ticks then
        table.remove(storage.companion_messages, i)
        removed_count = removed_count + 1
      end
    end

    rcon.print('{"removed": ' .. removed_count .. '}')
  end)

  if not success then
    rcon.print('{"error": "' .. tostring(result) .. '"}')
  end
end)

-- Optional: Event throttling for future features (FLE pattern)
-- This runs every tick but only processes every 60 ticks (1 second)
script.on_event(defines.events.on_tick, function(event)
  if event.tick % 60 == 0 then
    -- Future: Auto-cleanup, health checks, etc.
    -- Currently unused but demonstrates FLE pattern
  end
end)
