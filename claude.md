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

## Mod Structure (v0.7.0)

```
ai-companion/
├── control.lua          # Main entry, /fac player command, walking queue
├── data.lua             # Sound definitions (wololo)
├── info.json            # Mod metadata (v0.7.0, 38 commands)
└── commands/
    ├── init.lua         # Shared utilities (colors, helpers, distance)
    ├── action.lua       # attack, flee, patrol, wololo
    ├── building.lua     # can_place, empty, fill, fuel, info, place, recipe, remove, rotate
    ├── chat.lua         # get, say
    ├── companion.lua    # disappear, health, inventory, position, spawn
    ├── context.lua      # clear, check
    ├── item.lua         # craft, pick, recipes
    ├── move.lua         # follow, stop, to
    ├── research.lua     # get, progress, set
    ├── resource.lua     # list, mine, nearest
    ├── world.lua        # nearest, scan
    └── help.lua         # help command
```

## RCON Commands (38 total)

All commands: `fac_<category>_<action>`

| Category   | Commands | Count |
|------------|----------|-------|
| action     | attack, flee, patrol, wololo | 4 |
| building   | can_place, empty, fill, fuel, info, place, recipe, remove, rotate | 9 |
| chat       | get, say | 2 |
| companion  | disappear, health, inventory, position, spawn | 5 |
| context    | clear, check | 2 |
| item       | craft, pick, recipes | 3 |
| move       | follow, stop, to | 3 |
| research   | get, progress, set | 3 |
| resource   | list, mine, nearest | 3 |
| world      | nearest, scan | 2 |
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

- **0.7.0** - Modular code split (12 command files), DRY utilities, context management
- **0.6.0** - Added context_clear, context_check, companion_disappear
- **0.3.6** - Parallel companions, naming, 8-direction movement
- **0.3.0** - Code refactor, DRY helpers, scalable architecture
- **0.2.0** - Complete documentation, reactive loop

## References

- [Factorio Lua API 2.0](https://lua-api.factorio.com/latest/)
- [FLE Source](../factorio-learning-environment/)
- [MCP Protocol](https://modelcontextprotocol.io/)
