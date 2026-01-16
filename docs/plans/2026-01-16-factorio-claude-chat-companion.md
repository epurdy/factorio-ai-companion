# Factorio Claude Chat Companion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a bidirectional chat bridge between Factorio game chat and Claude Code, later extending to AI-controlled character actions.

**Architecture:** Lua mod captures `/companion` commands via RCON, Node.js/TypeScript MCP server bridges to Claude Code using MCP protocol, reusing Factorio Learning Environment's proven Lua serialization and RCON infrastructure.

**Tech Stack:** Lua (Factorio mod), TypeScript (MCP server), Bun runtime, MCP SDK

**Key Learnings from FLE:**
- Script caching with checksums to avoid reloading unchanged Lua
- pcall() error handling for all risky operations
- Event throttling (check every 60 ticks, not every tick)
- Message cleanup to prevent memory leaks
- RCON retry logic and timeout handling
- Batch operations for performance
- Multi-agent character support patterns

---

## Factorio 2.x Modding Workflow (2025-2026 Standard)

### Standard Mod Structure:
```
mods/
└── your-mod-name/
    ├── info.json       ← REQUIRED: Mod metadata
    ├── control.lua     ← Runtime scripting (events, commands)
    ├── data.lua        ← Prototypes (items, recipes) - OPTIONAL
    └── thumbnail.png   ← Mod icon - OPTIONAL
```

### Key Files:

**info.json** (Required):
- Defines mod name, version, factorio_version "2.0"
- Dependencies array
- Author, title, description

**control.lua** (Runtime Scripting):
- Event handlers: `script.on_event(defines.events.on_tick, ...)`
- Custom commands: `commands.add_command("name", ...)`
- Global state: `global.my_data`
- RCON accessible via `rcon.print()`

**data.lua** (Prototypes - NOT needed for our chat mod):
- Defines items, recipes, entities, technologies
- Only needed if adding game content

### RCON Requirement:
- RCON only works when game runs "as server"
- Can still play solo - just check "Start as server" when creating game
- No performance impact for solo play

---

## FLE Learnings Applied

### Critical Patterns Borrowed:
1. **Checksum-based script caching** - Avoid reloading unchanged scripts
2. **Event throttling** - Check messages every 60 ticks (1 second), not every tick
3. **pcall() everywhere** - Wrap all risky operations for graceful failures
4. **Message expiry** - Auto-cleanup old messages to prevent memory leaks
5. **RCON retry logic** - Handle disconnections and timeouts gracefully
6. **Batch JSON responses** - Return arrays, not individual items
7. **Global state persistence** - Handle mod configuration changes

---

## Phase 1: Chat Bridge (Minimal Viable Product)

### Task 1: Project Setup & Dependencies

**Files:**
- Create: `package.json`
- Create: `tsconfig.json`
- Create: `.gitignore`
- Create: `README.md`

**Step 1: Initialize Node.js project with Bun**

```bash
cd C:\Users\lveil\Desktop\Projects\factorio-ai-companion
bun init -y
```

Expected: Creates package.json

**Step 2: Install dependencies**

```bash
bun add @modelcontextprotocol/sdk zod
bun add -d @types/node typescript
```

Expected: Dependencies installed

**Step 3: Create TypeScript config**

Create `tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "types": ["bun-types"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "fle-reference"]
}
```

**Step 4: Create .gitignore**

```
node_modules/
dist/
.env
*.log
fle-reference/
factorio-mods/
```

**Step 5: Update README.md**

```markdown
# Factorio AI Companion

Bidirectional chat bridge between Factorio and Claude Code via MCP protocol.

## Setup

1. Install Bun: https://bun.sh
2. `bun install`
3. Configure Factorio server with RCON enabled
4. `bun run src/index.ts`

## Usage

In Factorio chat: `/companion Hello!`
Claude Code will receive and can respond.
```

**Step 6: Commit initial setup**

```bash
git init
git add package.json tsconfig.json .gitignore README.md
git commit -m "feat: initial project setup with TypeScript and Bun"
```

---

### Task 2: RCON Client Implementation

**Files:**
- Create: `src/rcon/client.ts`
- Create: `src/rcon/types.ts`

**Step 1: Write types for RCON**

Create `src/rcon/types.ts`:

```typescript
export interface RCONConfig {
  host: string;
  port: number;
  password: string;
}

export interface RCONResponse {
  success: boolean;
  data: string;
  error?: string;
}
```

**Step 2: Write failing test**

Create `src/rcon/client.test.ts`:

```typescript
import { describe, test, expect } from "bun:test";
import { RCONClient } from "./client";

describe("RCONClient", () => {
  test("should connect to Factorio RCON", async () => {
    const client = new RCONClient({
      host: "127.0.0.1",
      port: 27000, // FLE default port
      password: "factorio",
    });

    await client.connect();
    expect(client.isConnected()).toBe(true);
    await client.disconnect();
  });
});
```

**Step 3: Run test to verify it fails**

```bash
bun test src/rcon/client.test.ts
```

Expected: FAIL with "Cannot find module './client'"

**Step 4: Implement RCON client with retry logic (FLE-inspired)**

Create `src/rcon/client.ts`:

```typescript
import { Socket } from "net";
import { RCONConfig, RCONResponse } from "./types";

export class RCONClient {
  private socket: Socket | null = null;
  private connected = false;
  private config: RCONConfig;
  private requestId = 1;
  private commandTimeout = 5000; // 5 second timeout per command

  constructor(config: RCONConfig) {
    this.config = config;
  }

  async connect(): Promise<void> {
    return this.connectWithRetry(3);
  }

  private async connectWithRetry(maxRetries: number): Promise<void> {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await this.connectOnce();
        console.error(`RCON connected on attempt ${attempt}`);
        return;
      } catch (error) {
        console.error(`RCON connection attempt ${attempt} failed:`, error);

        if (attempt === maxRetries) {
          throw new Error(`Failed to connect after ${maxRetries} attempts`);
        }

        // Exponential backoff: 1s, 2s, 4s
        await this.sleep(1000 * Math.pow(2, attempt - 1));
      }
    }
  }

  private async connectOnce(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.socket = new Socket();
      this.socket.setTimeout(this.commandTimeout);

      this.socket.on("connect", () => {
        this.authenticate().then(() => {
          this.connected = true;
          resolve();
        }).catch(reject);
      });

      this.socket.on("error", (err) => {
        this.connected = false;
        reject(err);
      });

      this.socket.on("timeout", () => {
        this.socket?.destroy();
        reject(new Error("Socket timeout"));
      });

      this.socket.connect(this.config.port, this.config.host);
    });
  }

  private async authenticate(): Promise<void> {
    const packet = this.createPacket(3, this.config.password);
    return new Promise((resolve, reject) => {
      if (!this.socket) return reject(new Error("Socket not initialized"));

      this.socket.write(packet);

      const timeout = setTimeout(() => {
        reject(new Error("Authentication timeout"));
      }, this.commandTimeout);

      this.socket.once("data", (data) => {
        clearTimeout(timeout);
        const response = this.parsePacket(data);
        if (response.id === -1) {
          reject(new Error("Authentication failed - invalid password"));
        } else {
          resolve();
        }
      });
    });
  }

  async sendCommand(command: string, timeoutMs?: number): Promise<RCONResponse> {
    if (!this.connected) {
      // Try to reconnect
      try {
        await this.connect();
      } catch (error) {
        return { success: false, data: "", error: "Not connected and reconnect failed" };
      }
    }

    const packet = this.createPacket(2, command);

    return new Promise((resolve) => {
      if (!this.socket) {
        return resolve({ success: false, data: "", error: "Socket not initialized" });
      }

      const timeout = setTimeout(() => {
        resolve({
          success: false,
          data: "",
          error: `Command timeout after ${timeoutMs || this.commandTimeout}ms`
        });
      }, timeoutMs || this.commandTimeout);

      this.socket.write(packet);

      this.socket.once("data", (data) => {
        clearTimeout(timeout);
        const response = this.parsePacket(data);
        resolve({ success: true, data: response.payload });
      });

      this.socket.once("error", (err) => {
        clearTimeout(timeout);
        this.connected = false;
        resolve({ success: false, data: "", error: err.message });
      });
    });
  }

  private createPacket(type: number, payload: string): Buffer {
    const id = this.requestId++;
    const payloadBuffer = Buffer.from(payload, "utf8");
    const length = payloadBuffer.length + 10;

    const packet = Buffer.alloc(length + 4);
    packet.writeInt32LE(length, 0);
    packet.writeInt32LE(id, 4);
    packet.writeInt32LE(type, 8);
    payloadBuffer.copy(packet, 12);
    packet.writeInt8(0, packet.length - 2);
    packet.writeInt8(0, packet.length - 1);

    return packet;
  }

  private parsePacket(buffer: Buffer): { id: number; type: number; payload: string } {
    const id = buffer.readInt32LE(4);
    const type = buffer.readInt32LE(8);
    const payload = buffer.toString("utf8", 12, buffer.length - 2);

    return { id, type, payload };
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  isConnected(): boolean {
    return this.connected;
  }

  async disconnect(): Promise<void> {
    if (this.socket) {
      this.socket.destroy();
      this.socket = null;
      this.connected = false;
    }
  }
}
```

**Step 5: Run test to verify it passes (with Factorio running)**

```bash
bun test src/rcon/client.test.ts
```

Expected: PASS (requires Factorio server with RCON on port 27000)

**Step 6: Commit RCON client**

```bash
git add src/rcon/
git commit -m "feat: implement RCON client for Factorio communication"
```

---

### Task 3: Chat Message Parser

**Files:**
- Create: `src/chat/parser.ts`
- Create: `src/chat/types.ts`

**Step 1: Define chat message types**

Create `src/chat/types.ts`:

```typescript
export interface ChatMessage {
  player: string;
  command: string;
  message: string;
  timestamp: Date;
}

export interface CommandMatch {
  isCompanionCommand: boolean;
  message?: string;
}
```

**Step 2: Write failing test**

Create `src/chat/parser.test.ts`:

```typescript
import { describe, test, expect } from "bun:test";
import { parseCompanionCommand } from "./parser";

describe("Chat Parser", () => {
  test("should parse /companion command", () => {
    const result = parseCompanionCommand("/companion Hello Claude!");
    expect(result.isCompanionCommand).toBe(true);
    expect(result.message).toBe("Hello Claude!");
  });

  test("should ignore non-companion messages", () => {
    const result = parseCompanionCommand("regular chat message");
    expect(result.isCompanionCommand).toBe(false);
  });
});
```

**Step 3: Run test to verify failure**

```bash
bun test src/chat/parser.test.ts
```

Expected: FAIL with "Cannot find module './parser'"

**Step 4: Implement parser**

Create `src/chat/parser.ts`:

```typescript
import { CommandMatch } from "./types";

export function parseCompanionCommand(text: string): CommandMatch {
  const companionRegex = /^\/companion\s+(.+)$/;
  const match = text.match(companionRegex);

  if (match) {
    return {
      isCompanionCommand: true,
      message: match[1],
    };
  }

  return { isCompanionCommand: false };
}
```

**Step 5: Run test to verify pass**

```bash
bun test src/chat/parser.test.ts
```

Expected: PASS

**Step 6: Commit parser**

```bash
git add src/chat/
git commit -m "feat: add chat message parser for /companion commands"
```

---

### Task 4: Factorio Lua Mod (Minimal Chat Capture)

**Files:**
- Create: `factorio-mod/info.json`
- Create: `factorio-mod/control.lua`

**Step 1: Create mod metadata**

Create `factorio-mod/info.json`:

```json
{
  "name": "ai-companion",
  "version": "0.1.0",
  "title": "AI Companion",
  "author": "lveil",
  "factorio_version": "2.0",
  "description": "Enables Claude Code to interact via chat and control a character. Compatible with Factorio 2.x and 1.1+",
  "dependencies": ["base >= 1.1"]
}
```

**Step 2: Write control.lua with FLE patterns (error handling, cleanup, throttling)**

Create `factorio-mod/control.lua`:

```lua
-- AI Companion Mod
-- Captures /companion commands with FLE-inspired patterns:
-- - pcall() error handling
-- - Message cleanup to prevent memory leaks
-- - Safe JSON serialization
-- - Configuration change handling

-- Initialize global state
local function init_globals()
  global.companion_messages = global.companion_messages or {}
  global.companion_tick_counter = global.companion_tick_counter or 0
end

script.on_init(function()
  init_globals()
end)

script.on_load(function()
  init_globals()
end)

-- Handle mod configuration changes (FLE pattern)
script.on_configuration_changed(function()
  init_globals()
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
      table.insert(global.companion_messages, {
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

    for i, msg in ipairs(global.companion_messages) do
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
    for i = #global.companion_messages, 1, -1 do
      local msg = global.companion_messages[i]
      if (current_tick - msg.tick) > cutoff_ticks then
        table.remove(global.companion_messages, i)
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
```

**Step 3: Test mod in Factorio**

Manual test:
1. Copy `factorio-mod` to Factorio mods directory
2. Start Factorio with RCON enabled
3. In game chat: `/companion test message`
4. Via RCON: `/companion_get_messages`

Expected: Returns JSON array with message

**Step 4: Commit Lua mod**

```bash
git add factorio-mod/
git commit -m "feat: add Factorio Lua mod for chat capture"
```

---

### Task 5: MCP Server Core

**Files:**
- Create: `src/mcp/server.ts`
- Create: `src/mcp/tools.ts`
- Create: `src/index.ts`

**Step 1: Define MCP tool schemas**

Create `src/mcp/tools.ts`:

```typescript
import { z } from "zod";

export const GetMessagesSchema = z.object({});

export const SendMessageSchema = z.object({
  message: z.string().describe("Message to send to Factorio chat"),
});

export type GetMessagesInput = z.infer<typeof GetMessagesSchema>;
export type SendMessageInput = z.infer<typeof SendMessageSchema>;
```

**Step 2: Implement MCP server**

Create `src/mcp/server.ts`:

```typescript
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { RCONClient } from "../rcon/client";
import { GetMessagesSchema, SendMessageSchema } from "./tools";

export class FactorioMCPServer {
  private server: Server;
  private rcon: RCONClient;

  constructor(rconConfig: { host: string; port: number; password: string }) {
    this.server = new Server(
      {
        name: "factorio-companion",
        version: "0.1.0",
      },
      {
        capabilities: {
          tools: {},
        },
      }
    );

    this.rcon = new RCONClient(rconConfig);
    this.setupHandlers();
  }

  private setupHandlers() {
    this.server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: [
        {
          name: "get_companion_messages",
          description: "Get unread messages from Factorio chat starting with /companion",
          inputSchema: {
            type: "object",
            properties: {},
          },
        },
        {
          name: "send_companion_message",
          description: "Send a message to Factorio chat as AI Companion",
          inputSchema: {
            type: "object",
            properties: {
              message: {
                type: "string",
                description: "Message to send to Factorio chat",
              },
            },
            required: ["message"],
          },
        },
      ],
    }));

    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      switch (request.params.name) {
        case "get_companion_messages": {
          const response = await this.rcon.sendCommand("/companion_get_messages");

          if (!response.success) {
            return {
              content: [
                { type: "text", text: `Error: ${response.error}` },
              ],
            };
          }

          try {
            const messages = JSON.parse(response.data);
            return {
              content: [
                {
                  type: "text",
                  text: messages.length > 0
                    ? JSON.stringify(messages, null, 2)
                    : "No new messages",
                },
              ],
            };
          } catch (e) {
            return {
              content: [
                { type: "text", text: `Parse error: ${e}` },
              ],
            };
          }
        }

        case "send_companion_message": {
          const parsed = SendMessageSchema.safeParse(request.params.arguments);

          if (!parsed.success) {
            return {
              content: [
                { type: "text", text: `Invalid arguments: ${parsed.error}` },
              ],
            };
          }

          const response = await this.rcon.sendCommand(
            `/companion_send ${parsed.data.message}`
          );

          return {
            content: [
              {
                type: "text",
                text: response.success
                  ? "Message sent successfully"
                  : `Error: ${response.error}`,
              },
            ],
          };
        }

        default:
          throw new Error(`Unknown tool: ${request.params.name}`);
      }
    });
  }

  async start() {
    await this.rcon.connect();
    console.error("RCON connected");

    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error("MCP server running on stdio");
  }
}
```

**Step 3: Create entry point**

Create `src/index.ts`:

```typescript
import { FactorioMCPServer } from "./mcp/server";

const server = new FactorioMCPServer({
  host: process.env.FACTORIO_HOST || "127.0.0.1",
  port: parseInt(process.env.FACTORIO_RCON_PORT || "27000"), // FLE default
  password: process.env.FACTORIO_RCON_PASSWORD || "factorio",
});

server.start().catch((error) => {
  console.error("Failed to start server:", error);
  process.exit(1);
});
```

**Step 4: Test MCP server locally**

```bash
bun run src/index.ts
```

Expected: "MCP server running on stdio"

**Step 5: Commit MCP server**

```bash
git add src/mcp/ src/index.ts
git commit -m "feat: implement MCP server with chat tools"
```

---

### Task 6: Claude Code Integration

**Files:**
- Create: `.mcp.json`
- Create: `.env.example`
- Modify: `README.md`

**Step 1: Create MCP configuration**

Create `.mcp.json`:

```json
{
  "mcpServers": {
    "factorio-companion": {
      "command": "bun",
      "args": ["run", "src/index.ts"],
      "env": {
        "FACTORIO_HOST": "127.0.0.1",
        "FACTORIO_RCON_PORT": "27000",
        "FACTORIO_RCON_PASSWORD": "factorio"
      }
    }
  }
}
```

**Step 2: Create environment template**

Create `.env.example`:

```
FACTORIO_HOST=127.0.0.1
FACTORIO_RCON_PORT=27000
FACTORIO_RCON_PASSWORD=factorio
```

**Step 3: Update README with setup instructions**

Modify `README.md`:

```markdown
# Factorio AI Companion

Bidirectional chat bridge between Factorio and Claude Code via MCP protocol.

## Prerequisites

- [Bun](https://bun.sh) runtime installed
- Factorio 2.x or 1.1+ (Space Age DLC not required)
- Factorio dedicated server or game running
- Claude Code CLI

## Factorio Setup

### Installing Factorio

**Option 1: Steam (Easiest)**
1. Purchase Factorio on Steam
2. Install via Steam client
3. Located at: `C:\Program Files (x86)\Steam\steamapps\common\Factorio\` (Windows)

**Option 2: Standalone**
1. Download from https://factorio.com/download
2. Extract to preferred location
3. No installation required

### Running with RCON

**IMPORTANT:** RCON only works when Factorio runs "as server" (even for solo play).

**Option A: Solo Play with RCON (Easiest - Play Normally):**
1. Launch Factorio normally
2. Main Menu → New Game
3. ✅ Check "Start as server"
4. Settings → Network:
   - RCON Port: `27000`
   - RCON Password: `factorio`
5. Play as usual!

**Option B: Command Line (Advanced):**
```bash
cd "C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64"
factorio.exe --start-server mysave.zip --rcon-port 27000 --rcon-password factorio
```

**Option C: Dedicated Server (Headless):**
```bash
factorio --start-server-load-latest --rcon-port 27000 --rcon-password factorio
```

Your game is now accessible via RCON on localhost:27000.

## Setup

### 1. Install dependencies

```bash
bun install
```

### 2. Configure Factorio RCON

**For Factorio 2.x:**

Enable RCON via command line when starting Factorio:
```bash
factorio --start-server mysave.zip --rcon-port 27000 --rcon-password factorio
```

**For Factorio 1.1 (deprecated):**

Add to Factorio `server-settings.json`:
```json
{
  "rcon": {
    "port": 27000,
    "password": "factorio"
  }
}
```

**Note:** Port 27000 is FLE's default. You can use any port, just update `.env` to match.

### 3. Install Factorio Mod (Standard Factorio Modding Process)

**The mod installs like any normal Factorio mod:**

**Windows:**
```bash
# Create mod folder and copy files
mkdir "%APPDATA%\Factorio\mods\ai-companion"
xcopy /E /I factorio-mod "%APPDATA%\Factorio\mods\ai-companion"
```

**Linux:**
```bash
mkdir -p ~/.factorio/mods/ai-companion
cp -r factorio-mod/* ~/.factorio/mods/ai-companion/
```

**Mac:**
```bash
mkdir -p ~/Library/Application\ Support/factorio/mods/ai-companion
cp -r factorio-mod/* ~/Library/Application\ Support/factorio/mods/ai-companion/
```

**Your mod structure should look like:**
```
%APPDATA%\Factorio\mods\
└── ai-companion\
    ├── info.json
    └── control.lua
```

**Enable the mod:**
1. Launch Factorio
2. Main Menu → Mods
3. Find "AI Companion" in the list
4. ✅ Enable it
5. Restart Factorio

### 4. Configure MCP Server

Copy `.mcp.json` to your Claude Code config directory or project root.

### 5. Start Factorio

Launch Factorio with RCON enabled.

## Usage

### In Factorio Chat

Type commands starting with `/companion`:

```
/companion Hello! Can you help me?
/companion What should I build next?
```

### In Claude Code

Use the MCP tools:

```
get_companion_messages - Check for new messages from players
send_companion_message - Reply to players in game
```

## Testing

```bash
# Run all tests
bun test

# Test RCON connection (requires Factorio running)
bun test src/rcon/client.test.ts
```

## Development

```bash
# Run MCP server standalone
bun run src/index.ts

# Type check
bun run tsc --noEmit
```

## Architecture

```
Factorio Game
    ↕ RCON (TCP)
Node.js MCP Server (Bun)
    ↕ MCP Protocol (stdio)
Claude Code CLI
```

## Future Features

- AI-controlled character movement
- Automated building and crafting
- Game state introspection
- Multi-player coordination
```

**Step 4: Commit documentation**

```bash
git add .mcp.json .env.example README.md
git commit -m "docs: add setup instructions and MCP configuration"
```

---

## Phase 2: Game State Integration (Future)

### Task 7: Reuse FLE Lua Serialization

**Goal:** Copy and adapt FLE's `serialize.lua` and related utilities to expose game state as JSON.

**Files:**
- Copy: `fle-reference/fle/env/mods/serialize.lua` → `factorio-mod/serialize.lua`
- Copy: `fle-reference/fle/env/mods/utils.lua` → `factorio-mod/utils.lua`
- Modify: `factorio-mod/control.lua`

**Steps:**
1. Copy FLE serialization modules
2. Add RCON command `/companion_get_state` that returns JSON
3. Add MCP tool `get_game_state`
4. Test state retrieval

---

### Task 8: Character Control API

**Goal:** Enable Claude to move and control an AI character in-game.

**Files:**
- Copy: FLE character control scripts from `fle-reference/data/scripts/`
- Modify: `factorio-mod/control.lua`
- Create: `src/mcp/character-tools.ts`

**Steps:**
1. Copy FLE character movement scripts
2. Add commands: `companion_move_to`, `companion_mine`, `companion_craft`
3. Add MCP tools: `move_character`, `mine_resource`, `craft_item`
4. Test character control

---

## Testing Strategy

### Unit Tests
- RCON client connection/commands
- Chat message parsing
- MCP tool schemas

### Integration Tests
- Full flow: Factorio → RCON → MCP → Claude Code
- Character movement via MCP tools

### Manual Tests
- Chat bridge functionality
- Response latency
- Multi-player scenarios

---

## Deployment Checklist

- [ ] Factorio mod installed
- [ ] RCON enabled and accessible
- [ ] MCP server configured in Claude Code
- [ ] Environment variables set
- [ ] Test `/companion` command in game
- [ ] Verify Claude Code receives messages
- [ ] Test sending responses back

---

## Success Criteria

**Phase 1 Complete When:**
- Type `/companion hello` in Factorio
- Claude Code receives message via `get_companion_messages` tool
- Claude responds using `send_companion_message` tool
- Response appears in Factorio chat

**Phase 2 Complete When:**
- Claude can query game state (entities, inventory, etc.)
- Claude can move AI character to coordinates
- Claude can perform crafting/building actions
- All actions complete successfully in-game

---

## References

- [Factorio Learning Environment](https://github.com/JackHopkins/factorio-learning-environment)
- [MCP Protocol Specification](https://modelcontextprotocol.io/)
- [Factorio Lua API](https://lua-api.factorio.com/)
- [factorio-rcon-py](https://github.com/mark9064/factorio-rcon-py)
