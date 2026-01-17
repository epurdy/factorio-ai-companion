# Factorio AI Companion

Bridge between Factorio game and Claude Code via RCON + MCP.

## Architecture Overview

```
Factorio (Lua mod) <--RCON--> TypeScript Server <--MCP--> Claude Code
```

**Communication flow:**
1. Player writes `/fac <message>` in Factorio
2. Lua mod stores message in `storage.companion_messages[]`
3. TypeScript polls RCON with `/companion_get_messages`
4. Claude processes and responds via `/companion_send`
5. Message appears in Factorio chat with color coding

**Color coding:**
- `[${USERNAME}]` in cyan/blue - player messages
- `[Claude]` in bright green - AI responses

## Project Structure

```
factorio-ai-companion/
├── src/
│   ├── rcon/
│   │   ├── client.ts       # RCON client (ported from FLE patterns)
│   │   └── types.ts        # TypeScript types
│   ├── mcp/
│   │   ├── server.ts       # MCP server with tools (stdio mode)
│   │   └── tools.ts        # Tool schemas
│   ├── daemon.ts           # Continuous polling daemon (not used currently)
│   ├── reactive.ts         # One-shot message waiter (ACTIVE)
│   ├── monitor.ts          # Simple test script
│   └── index.ts            # MCP entry point
├── .mcp.json               # Claude Code MCP configuration
├── claude.md               # This file
└── package.json

Factorio mod location:
%APPDATA%/Factorio/mods/ai-companion/
├── info.json               # Version 0.2.0
└── control.lua             # Lua commands

Reference implementation:
../factorio-learning-environment/   # FLE source code for patterns
```

## Factorio Setup

### 1. RCON Configuration

Edit `%APPDATA%\Factorio\config\config.ini`:

```ini
[network]
local-rcon-socket=127.0.0.1:34198
local-rcon-password=factorio
```

### 2. Run as Multiplayer Server

**CRITICAL:** RCON only works in multiplayer mode.

1. Launch Factorio
2. Multiplayer → Host New Game
3. Load save or start new game
4. Server runs with RCON enabled on port 34198

**Why multiplayer?** RCON is designed for server administration. Single player mode doesn't expose the RCON socket.

### 3. Mod Installation

The mod is already installed at:
```
%APPDATA%\Factorio\mods\ai-companion\
```

Restart Factorio after any mod changes to reload Lua code.

## How to Use (Instructions for Claude)

### Starting a Chat Session

When the user wants to interact via Factorio chat:

1. **Start reactive listener:**
   ```typescript
   bun run src/reactive.ts
   ```
   This runs in background and waits for a message (blocks until found).

2. **Wait for message:**
   ```typescript
   TaskOutput(task_id, block: true, timeout: 60000)
   ```
   This blocks until user writes `/fac <message>` in Factorio.

3. **Parse output:**
   The output is JSON format:
   ```json
   {"player":"username","message":"text here","tick":12345}
   ```

4. **Respond:**
   ```bash
   bun -e "
   import { RCONClient } from './src/rcon/client';
   const client = new RCONClient({ host: '127.0.0.1', port: 34198, password: 'factorio' });
   await client.connect();
   await client.sendCommand('/companion_send Your response here');
   await client.disconnect();
   "
   ```

5. **Loop:** Restart reactive.ts for next message (goto step 1)

### Reactive Loop Pattern

```typescript
// One iteration:
[Start reactive.ts] → [User writes /fac] → [Process & respond] → [Restart reactive.ts]
```

**Why one-shot?** Because Claude can only react when TaskOutput completes. The script exits when a message is found, triggering Claude to process it.

**Latency:** ~1-3 seconds
- Poll interval: 1 second
- RCON: <100ms
- Claude processing: variable

### Available MCP Tools

Currently implemented in `.mcp.json`:
- `get_companion_messages` - Fetch unread messages (returns JSON array)
- `send_companion_message` - Send response to Factorio chat

**Note:** These tools use stdio MCP server which launches on-demand. For reactive chat, use the `reactive.ts` approach instead.

## Lua Mod Commands

### Player Commands (in-game)
- `/companion <message>` - Send message to Claude
- `/fac <message>` - Short alias

### RCON Commands (TypeScript calls these)
- `/companion_get_messages` - Returns JSON array of unread messages
  ```json
  [{"player":"user","message":"text","tick":123}]
  ```

- `/companion_send <message>` - Broadcasts Claude's response
  ```
  [Claude] message appears in green
  ```

- `/companion_cleanup` - Removes messages older than 10 minutes

## Adding Game State Queries (FLE Integration)

When adding observation tools (inventory, entities, research):

### 1. Reference FLE Implementation

Check `../factorio-learning-environment/fle/env/tools/agent/` for existing patterns.

**Top priority tools to port:**
1. `inspect_inventory` - Player/entity inventory contents
2. `get_entities` - Nearby entities with positions and types
3. `get_resource_patch` - Resource locations and amounts
4. `get_research_progress` - Current research status
5. `get_production_stats` - Factory production statistics

### 2. FLE Lua Patterns

```lua
-- Finding entities in area
local area = {{x-radius, y-radius}, {x+radius, y+radius}}
local entities = surface.find_entities_filtered{
  area = area,
  force = player.force,
  name = entity_names  -- optional filter
}

-- Reading inventories
local contents = entity.get_inventory(defines.inventory.chest).get_contents()
-- Returns: {["iron-plate"] = 50, ["copper-plate"] = 30}

-- Research status
local tech = force.technologies[name]
local progress = force.research_progress  -- 0.0 to 1.0

-- Entity serialization (FLE has utils for this)
local serialized = global.utils.serialize_entity(entity)
```

### 3. Implementation Steps

1. **Add Lua command** to `control.lua`:
   ```lua
   commands.add_command("companion_get_inventory", "Get player inventory", function(command)
     local success, result = pcall(function()
       local player = game.players[1]  -- Or get from command
       local inventory = player.get_main_inventory()
       local contents = inventory.get_contents()

       local json_success, json_result = pcall(helpers.table_to_json, contents)
       if json_success then
         rcon.print(json_result)
       else
         rcon.print('{"error": "Serialization failed"}')
       end
     end)

     if not success then
       rcon.print('{"error": "' .. tostring(result) .. '"}')
     end
   end)
   ```

2. **Add TypeScript wrapper** in `src/mcp/server.ts` or call directly via RCON

3. **Test** via RCON:
   ```typescript
   const response = await client.sendCommand('/companion_get_inventory');
   const data = JSON.parse(response.data);
   ```

### 4. Factorio 2.x API Changes

Important differences from Factorio 1.x (which FLE targets):
- `global` → `storage` (mod data storage)
- `game.table_to_json()` → `helpers.table_to_json()` (JSON serialization)
- Always use `pcall()` for error handling

## Environment Variables

```bash
FACTORIO_HOST=127.0.0.1
FACTORIO_RCON_PORT=34198
FACTORIO_RCON_PASSWORD=factorio
```

Defined in `.mcp.json` and used by `src/rcon/client.ts`.

## Troubleshooting

### "Connection refused" error
- Factorio not running, or
- Not running in multiplayer mode, or
- RCON not configured in config.ini

### "Unknown command" in Factorio
- Mod not loaded (restart Factorio)
- Typo in command name

### Messages not appearing
- Check mod version matches (0.2.0)
- Verify RCON connection: `bun -e "import {RCONClient} from './src/rcon/client'; const c = new RCONClient({host:'127.0.0.1',port:34198,password:'factorio'}); await c.connect(); console.log('OK');"`

### Reactive loop not triggering
- Ensure TaskOutput is set to `block: true`
- Check timeout (default 60s, increase if needed)
- Verify reactive.ts exits with code 0 when message found

## Version History

- **0.2.0** - Complete documentation, FLE reference integration, reactive loop guide
- **0.1.7** - Chat color differentiation ([user] cyan, [Claude] green)
- **0.1.6** - Added `/fac` alias
- **0.1.5** - Fixed JSON serialization (helpers.table_to_json)
- **0.1.4** - Fixed command registration
- **0.1.3** - Factorio 2.x compatibility (global → storage)
- **0.1.2** - Failed init fix attempt
- **0.1.1** - Failed global initialization
- **0.1.0** - Initial implementation

## Next Steps

1. Port FLE observation tools (inventory, entities, research)
2. Add MCP tools for each observation command
3. Implement context-aware responses (Claude queries game state when needed)
4. Phase 2: Control commands (move, place, craft)

## References

- [Factorio Lua API 2.0](https://lua-api.factorio.com/latest/)
- [FLE Source](../factorio-learning-environment/)
- [MCP Protocol](https://modelcontextprotocol.io/)
- [RCON Protocol](https://developer.valvesoftware.com/wiki/Source_RCON_Protocol)
