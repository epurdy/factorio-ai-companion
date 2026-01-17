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
│  TS Orchestrator │◄────────────►│  Factorio Mod    │
│  (Claude Code)   │              │  (ai-companion)  │
└─────────────────┘              └──────────────────┘
        │
        ▼
  Claude API (subagents per companion)
```

## QUICK START - WHEN SESSION BEGINS (READ FIRST)

**As the orchestrator (Claude Code), you MUST enter reactive mode immediately when the user wants to interact with Factorio.**

### Step-by-step:

1. **Launch reactive listener in background:**
   ```bash
   bun run src/reactive.ts
   ```
   Use `run_in_background: true`. Save the task_id.

2. **Block and wait for user message:**
   ```typescript
   TaskOutput(task_id, block: true, timeout: 120000)
   ```
   This waits until user writes `/fac <message>` in Factorio.

3. **Parse the JSON output and respond:**
   ```json
   {"player":"lveillard","message":"hola","tick":12345}
   ```
   Respond via RCON with `/fac_chat_say 0 <response>`.

4. **Loop:** Go back to step 1. Restart reactive.ts for the next message.

### When User Requests Companions:

If user writes `/fac spawn 2` or asks for companions:
1. Spawn entities via RCON: `/fac_companion_spawn id=1`, `/fac_companion_spawn id=2`
2. Launch a Task subagent for EACH companion with the FULL PROMPT TEMPLATE below
3. Continue your own reactive loop as orchestrator (id=0)

## REACTIVE CHAT LOOP (CRITICAL)

**This is how Claude communicates with Factorio. Follow this pattern exactly.**

### The Loop

```
[1. Start reactive.ts] → [2. Wait for message] → [3. Process & Respond] → [4. Loop]
```

### Step 1: Start reactive listener (background)

```bash
bun run src/reactive.ts
```
Run with `run_in_background: true`. This script polls RCON until a message arrives, then outputs JSON and exits.

### Step 2: Wait for message (blocking)

```typescript
TaskOutput(task_id, block: true, timeout: 60000)
```
This blocks until user writes `/fac <message>` in Factorio.

### Step 3: Parse output and respond

Output format:
```json
{"player":"username","message":"text here","tick":12345}
```

Respond via RCON:
```bash
bun -e "
import { RCONClient } from './src/rcon/client';
const client = new RCONClient({ host: '127.0.0.1', port: 34198, password: 'factorio' });
await client.connect();
await client.sendCommand('/fac_chat_say 0 Your response here');
await client.disconnect();
"
```

### Step 4: Loop

Go back to Step 1. Restart reactive.ts for the next message.

### Why One-Shot?

Claude can only react when TaskOutput completes. The script exits when a message is found, triggering Claude to process it. This is the reactive pattern.

### Handling Disconnections

If you see 3-4 consecutive ECONNREFUSED errors, Factorio has restarted or disconnected. When this happens:
1. Kill all background bash tasks (reactive.ts, reactive-companion.ts)
2. Kill all companion subagent Tasks
3. Wait for user to confirm Factorio is back up
4. Restart the reactive loop fresh

### Example Session

```typescript
// 1. Start listener
Bash: bun run src/reactive.ts (background, id: abc123)

// 2. Wait
TaskOutput(abc123, block: true, timeout: 60000)
// User writes: /fac hola que tal

// 3. Output received:
{"player":"lveillard","message":"hola que tal","tick":12345}

// 4. Respond
Bash: bun -e "...client.sendCommand('/fac_chat_say 0 Hola! Todo bien.')..."

// 5. Loop - restart from step 1
```

## PARALLEL COMPANIONS (CRITICAL)

**Each companion is an INDEPENDENT subagent.** Do NOT respond on behalf of companions - spawn a subagent for each.

### Architecture

```
Orchestrator (this Claude)
├── reactive.ts → messages without target_companion → responds as id=0
│
└── For each companion:
    └── Task tool (subagent) → reactive-companion.ts <id> → responds as id=N
```

### Spawning Companion Subagents

When user requests spawn (e.g., `/fac spawn 2`):

1. **Spawn entities via RCON:**
   ```bash
   /fac_companion_spawn id=1
   /fac_companion_spawn id=2
   ```

2. **Launch a Task subagent for EACH companion with this FULL PROMPT:**

```
You are Companion #N in Factorio. ID=N. Respond in the player's language.

REACTIVE LOOP (mandatory):
1. Bash(run_in_background=true): bun run src/reactive-companion.ts N
2. TaskOutput(task_id, block=true, timeout=120000)
3. Parse JSON: {"companionId":N,"player":"...","message":"...","tick":...}
4. Respond via RCON, execute actions
5. GOTO 1

FORBIDDEN: sleep, cat, Read on output files, manual polling. ONLY use reactive-companion.ts + TaskOutput.

COMMANDS (replace N with your ID):
-- Chat
/fac_chat_say N "msg"
-- Move
/fac_move_to N x y | /fac_move_follow N player | /fac_move_stop N
-- Mine (tick-based)
/fac_resource_nearest N type | /fac_resource_mine_start N x y [count] | /fac_resource_mine_status N | /fac_resource_mine_stop N
-- Craft (tick-based)
/fac_item_craft_start N item [count] | /fac_item_craft_status N | /fac_item_craft_stop N | /fac_item_recipes N filter
-- Build
/fac_building_place N entity x y | /fac_building_remove N x y | /fac_building_info N x y
-- Combat
/fac_world_enemies N [radius] | /fac_action_attack_start N x y | /fac_action_attack_stop N | /fac_action_defend N on|off
-- Status
/fac_companion_position N | /fac_companion_inventory N | /fac_companion_health N | /fac_world_scan N [radius]

RULES: Use your ID in all commands. Respond with /fac_chat_say before actions. Report errors. Exit on 3+ ECONNREFUSED.
```

3. **Each subagent runs independently:**
   - Listens with `bun run src/reactive-companion.ts <id>`
   - Waits with TaskOutput blocking
   - Responds using `/fac_chat_say <id> message`
   - Loops back to listen

### Example: User writes `/fac 1 sigueme`

```
User → /fac 1 sigueme
         ↓
Factorio stores {target_companion: 1, message: "sigueme"}
         ↓
Companion #1's reactive-companion.ts receives it
         ↓
Companion #1's subagent processes: "sigueme" → follow command
         ↓
Subagent responds: /fac_chat_say 1 "Entendido, te sigo!"
Subagent executes: /fac_move_follow 1 lveillard
         ↓
Subagent loops back to listen
```

### Key Rules

1. **Orchestrator (id=0)**: Handles `/fac <message>` (no target)
2. **Companions (id=N)**: Each has its own subagent handling `/fac N <message>`
3. **NEVER respond for a companion** - the subagent does that
4. **Each subagent has its own context** - independent conversations

## Project Structure

```
factorio-ai-companion/          # THIS REPO
├── src/
│   ├── rcon/client.ts          # RCON client
│   ├── mcp/server.ts           # MCP server (stdio)
│   ├── reactive.ts             # One-shot message waiter
│   ├── daemon.ts               # Continuous polling
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
