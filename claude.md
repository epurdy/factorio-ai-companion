# Factorio AI Companion

AI companions for Factorio 2.x with RCON commands and TypeScript orchestration.

## IMPORTANT: FLE Reference

**DO NOT clone FLE into this repo.** It lives separately at:
```
../factorio-learning-environment/
```

When implementing new features, ALWAYS check FLE first:
- Tools: `../factorio-learning-environment/fle/env/tools/agent/`
- Entity utils: `../factorio-learning-environment/fle/env/src/`

## Architecture

```
┌─────────────────┐     RCON      ┌──────────────────┐
│  Claude Code    │◄────────────►│  Factorio Mod    │
│  (Orchestrator) │              │  (ai-companion)  │
│                 │              │                  │
│  Handles ALL    │              │  Tick-based      │
│  companions     │              │  queues          │
│  (id=0,1,2,...) │              │                  │
└─────────────────┘              └──────────────────┘
        ▲
        │
   reactive-all.ts (polls ALL messages)
```

**Key Design Principle (inspired by FLE):**
- ONE orchestrator (Claude Code) manages ALL companions
- Like FLE's namespaces: single Environment, multiple agents
- NO separate subagent Tasks per companion
- Reactive polling with message deduplication

## QUICK START - WHEN SESSION BEGINS (READ FIRST)

**As the orchestrator (Claude Code), you manage ALL companions in a single reactive loop.**

### The Reactive Loop (for ALL companions):

1. **Launch reactive-all.ts in background:**
   ```bash
   bun run src/reactive-all.ts
   ```
   Use `run_in_background: true`. Polls for messages for ALL companions (id=0, 1, 2, ...).

2. **Block and wait for messages:**
   ```typescript
   TaskOutput(task_id, block: true, timeout: 120000)
   ```

3. **Parse the JSON array output:**
   ```json
   [
     {"companionId": 0, "player": "lveillard", "message": "hola", "tick": 12345},
     {"companionId": 1, "player": "lveillard", "message": "ve a minar cobre", "tick": 12346}
   ]
   ```

4. **Process EACH message:**
   - If `companionId === 0`: Respond as orchestrator using `/fac_chat_say 0 "response"`
   - If `companionId === 1, 2, ...`: Respond as that companion using `/fac_chat_say N "response"`, then execute actions

5. **Loop:** Go back to step 1. Restart reactive-all.ts for next batch.

### When User Requests Companions:

If user writes `/fac spawn 2` or asks for companions:
1. Spawn entities via RCON: `/fac_companion_spawn id=1`, `/fac_companion_spawn id=2`
2. **No Task subagents needed** - YOU handle their messages in your main loop
3. Continue the reactive-all loop

## REACTIVE CHAT LOOP (CRITICAL)

**This is how Claude communicates with Factorio AND manages all companions.**

### The Loop (for ALL companions)

```
[1. Start reactive-all.ts] → [2. Wait for messages] → [3. Process ALL] → [4. Loop]
```

### Step 1: Start reactive-all listener (background)

```bash
bun run src/reactive-all.ts
```
Run with `run_in_background: true`. This script polls RCON for ALL messages (orchestrator + all companions), then outputs JSON array and exits.

### Step 2: Wait for messages (blocking)

```typescript
TaskOutput(task_id, block: true, timeout: 120000)
```
This blocks until ANY user writes `/fac <message>` or `/fac N <message>` in Factorio.

### Step 3: Parse output and process ALL messages

Output format (JSON array):
```json
[
  {"companionId": 0, "player": "lveillard", "message": "hola", "tick": 12345},
  {"companionId": 1, "player": "lveillard", "message": "ve a minar", "tick": 12346}
]
```

Process each message:
- **companionId === 0**: Respond as orchestrator
- **companionId === 1, 2, ...**: Respond as that companion + execute actions

Example response code:
```typescript
for (const msg of messages) {
  if (msg.companionId === 0) {
    // Respond as orchestrator
    await rcon.sendCommand(`/fac_chat_say 0 "Hola!"`);
  } else {
    // Respond as companion
    await rcon.sendCommand(`/fac_chat_say ${msg.companionId} "Entendido!"`);
    // Execute actions (mining, movement, etc.)
    await rcon.sendCommand(`/fac_move_follow ${msg.companionId} ${msg.player}`);
  }
}
```

### Step 4: Loop

Go back to Step 1. Restart reactive-all.ts for next batch of messages.

### Why One-Shot?

Claude can only react when TaskOutput completes. The script exits when messages are found, triggering Claude to process them. This is the reactive pattern.

### Handling Disconnections

If you see 3-4 consecutive ECONNREFUSED errors, Factorio has restarted or disconnected. When this happens:
1. Kill the background bash task (reactive-all.ts)
2. Wait for user to confirm Factorio is back up
3. Restart the reactive loop fresh

### Example Session

```typescript
// 1. Spawn companions
await rcon.sendCommand('/fac_companion_spawn id=1');
await rcon.sendCommand('/fac_companion_spawn id=2');

// 2. Start listener
Bash: bun run src/reactive-all.ts (background, id: abc123)

// 3. Wait
TaskOutput(abc123, block: true, timeout: 120000)

// User writes: /fac hola
// User writes: /fac 1 ve a minar cobre

// 4. Output received:
[
  {"companionId": 0, "player": "lveillard", "message": "hola", "tick": 12345},
  {"companionId": 1, "player": "lveillard", "message": "ve a minar cobre", "tick": 12346}
]

// 5. Process messages
for (const msg of messages) {
  if (msg.companionId === 0) {
    await rcon.sendCommand(`/fac_chat_say 0 "Hola! ¿Cómo estás?"`);
  } else if (msg.companionId === 1) {
    await rcon.sendCommand(`/fac_chat_say 1 "Entendido, voy a minar cobre"`);
    // Find copper ore
    const nearest = await rcon.sendCommand(`/fac_resource_nearest 1 copper-ore`);
    // Start mining
    await rcon.sendCommand(`/fac_resource_mine_start 1 ${x} ${y} 50`);
  }
}

// 6. Loop - restart from step 2
```

## MANAGING COMPANIONS (CRITICAL)

**YOU (the orchestrator) manage ALL companions in a single reactive loop. NO separate subagent Tasks.**

### Architecture (FLE-inspired)

```
Claude Code (Single Orchestrator)
├── reactive-all.ts (background bash)
│   └── Polls ALL messages for id=0, 1, 2, ...
│
└── Main Loop:
    ├── Process message for id=0 → respond as orchestrator
    ├── Process message for id=1 → respond + execute actions as Companion #1
    └── Process message for id=2 → respond + execute actions as Companion #2
```

### When User Requests Companions:

User writes `/fac spawn 2`:

1. **Spawn entities via RCON:**
   ```bash
   /fac_companion_spawn id=1
   /fac_companion_spawn id=2
   ```

2. **No Task subagents needed** - YOU handle their messages directly in your main reactive-all loop

3. **Continue the loop** - reactive-all.ts will now include their messages

### Example: User writes `/fac 1 sigueme`

```
User → /fac 1 sigueme
         ↓
Factorio stores {target_companion: 1, message: "sigueme"}
         ↓
reactive-all.ts receives it in next poll
         ↓
YOU (orchestrator) process it:
  - Respond: /fac_chat_say 1 "Entendido, te sigo!"
  - Execute: /fac_move_follow 1 lveillard
         ↓
Loop back to wait for next messages
```

### Key Rules

1. **ONE orchestrator** (Claude Code) manages ALL companions
2. **NO Task subagents** for companions - you handle everything
3. **Respond with correct companionId** using `/fac_chat_say N "message"`
4. **Use companion's ID in all commands** (move, mine, craft, etc.)
5. **Like FLE's namespaces** - single Environment, multiple agents sharing one executor

## Project Structure

```
factorio-ai-companion/          # THIS REPO
├── src/
│   ├── rcon/client.ts          # RCON client
│   ├── mcp/server.ts           # MCP server (stdio)
│   ├── reactive-all.ts         # ⭐ NEW: Polls ALL companions (id=0,1,2,...)
│   ├── reactive.ts             # DEPRECATED: One-shot for orchestrator only
│   ├── reactive-companion.ts   # DEPRECATED: One-shot for specific companion
│   ├── daemon.ts               # Continuous polling (unused)
│   └── skills/                 # TypeScript skills
├── factorio-mod/               # Source for Factorio mod
│   ├── control.lua
│   ├── data.lua
│   ├── info.json
│   └── commands/               # Modular commands (v0.7.0)
├── .mcp.json
├── claude.md                   # THIS FILE
└── package.json

%APPDATA%/Factorio/mods/ai-companion/   # INSTALLED MOD
└── (copy of factorio-mod/)
```

## Mod Structure (v0.8.0)

```
ai-companion/
├── control.lua          # Main entry, /fac player command, tick handlers
├── data.lua             # Sound definitions (wololo)
├── info.json            # Mod metadata (v0.8.0, 50 commands)
└── commands/
    ├── init.lua         # Shared utilities (colors, helpers, distance)
    ├── queues.lua       # DRY tick-based queue system (harvest, craft, build, combat)
    ├── action.lua       # attack, flee, patrol, wololo
    ├── building.lua     # can_place, empty, fill, fuel, info, place, place_start, place_status, recipe, remove, rotate
    ├── chat.lua         # get, say
    ├── combat.lua       # world_enemies, attack_start, attack_status, attack_stop, defend
    ├── companion.lua    # disappear, health, inventory, position, spawn
    ├── context.lua      # clear, check
    ├── item.lua         # craft, craft_start, craft_status, craft_stop, pick, recipes
    ├── move.lua         # follow, stop, to
    ├── research.lua     # get, progress, set
    ├── resource.lua     # list, mine, mine_start, mine_status, mine_stop, nearest
    ├── world.lua        # nearest, scan, enemies
    └── help.lua         # help command
```

## RCON Commands (50 total)

All commands: `fac_<category>_<action>`

| Category   | Commands | Count |
|------------|----------|-------|
| action     | attack, attack_start, attack_status, attack_stop, defend, flee, patrol, wololo | 8 |
| building   | can_place, empty, fill, fuel, info, place, place_start, place_status, recipe, remove, rotate | 11 |
| chat       | get, say | 2 |
| companion  | disappear, health, inventory, position, spawn | 5 |
| context    | clear, check | 2 |
| item       | craft, craft_start, craft_status, craft_stop, pick, recipes | 6 |
| move       | follow, stop, to | 3 |
| research   | get, progress, set | 3 |
| resource   | list, mine_start, mine_status, mine_stop, nearest | 5 |
| world      | enemies, nearest, scan | 3 |
| help       | help | 1 |

### Key Commands

```lua
-- Spawn companion
/fac_companion_spawn id=1

-- Move companion
/fac_move_to 1 100 50
/fac_move_follow 1 PlayerName
/fac_move_stop 1

-- Chat (id=0 for orchestrator)
/fac_chat_say 0 "Hello from Claude"
/fac_chat_say 1 "Hello from companion #1"
/fac_chat_get         -- Get all unread
/fac_chat_get 1       -- Get for companion #1

-- Context management
/fac_context_clear 1      -- Clear companion #1
/fac_context_clear all    -- Clear all
/fac_context_check        -- Check pending clears (for daemon)

-- Despawn (drops items, signals thread close)
/fac_companion_disappear 1
```

### Player Commands (in-game)

```
/fac                     -- Help
/fac <message>           -- Chat to all companions
/fac <id> <message>      -- Chat to specific companion
/fac spawn [n]           -- Request spawn
/fac list                -- List companions
/fac kill [id]           -- Kill companion(s)
/fac clear               -- Clear message queue
/fac name <id> <name>    -- Name a companion
```

## Storage Model

```lua
storage = {
  companion_messages = {},     -- Message queue (temporary, auto-cleaned)
  companions = {},             -- Active companions {entity, color, label, name}
  companion_next_id = 1,       -- ID counter
  walking_queues = {},         -- Movement targets
  context_clear_requests = {}, -- Pending clears for TS daemon
  errors = {}                  -- Error log (max 50)
}
```

**Important:** `companion_messages` is a **queue**, not context storage. Context lives in Claude Code threads.

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

### 3. Mod Installation

Copy `factorio-mod/` contents to `%APPDATA%\Factorio\mods\ai-companion\`

Restart Factorio after any mod changes.

## Workflow

**The repo is the source of truth.** After making changes:

1. Edit files in `factorio-mod/`
2. Test locally
3. Update version in `info.json`
4. Commit and push
5. Copy to AppData:
   ```bash
   # Windows
   xcopy /E /Y "factorio-mod\*" "%APPDATA%\Factorio\mods\ai-companion\"
   ```
6. Restart Factorio to load changes

## TypeScript Skills

Located in `src/skills/`:

```typescript
interface SkillContext {
  rcon: RCONClient;
  companionId: number;
}

interface SkillResult {
  success: boolean;
  message: string;
  data?: Record<string, unknown>;
}

async function exec(ctx: SkillContext, command: string): Promise<Record<string, unknown>>
```

## Development

```bash
# Install dependencies
bun install

# Build
bun run build

# Test RCON connection
bun run src/rcon/client.ts
```

## Environment Variables

```bash
FACTORIO_HOST=127.0.0.1
FACTORIO_RCON_PORT=34198
FACTORIO_RCON_PASSWORD=factorio
```

## Factorio 2.x Notes

- Use `storage` instead of `global`
- Use `helpers.table_to_json()` for JSON
- Color format: `{color = {r, g, b}}` for `game.print()`
- Mod dependency: `base >= 2.0`

## Troubleshooting

### "Connection refused" error
- Factorio not running, or
- Not running in multiplayer mode, or
- RCON not configured in config.ini

### "Unknown command" in Factorio
- Mod not loaded (restart Factorio)
- Typo in command name

### Messages not appearing
- Check mod version matches
- Verify RCON connection

## Version History

- **0.8.0** - FLE-inspired tick-based queues (mining, crafting, building, combat), 50 commands total
- **0.7.0** - Modular code split (12 command files), DRY utilities, context management
- **0.6.0** - Added context_clear, context_check, companion_disappear
- **0.3.6** - Parallel companions, naming, 8-direction movement
- **0.3.0** - Code refactor, DRY helpers, scalable architecture
- **0.2.0** - Complete documentation, reactive loop

## References

- [Factorio Lua API 2.0](https://lua-api.factorio.com/latest/)
- [FLE Source](../factorio-learning-environment/)
- [MCP Protocol](https://modelcontextprotocol.io/)
