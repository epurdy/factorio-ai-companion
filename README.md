# Factorio AI Companion

Bidirectional chat bridge between Factorio and Claude Code via MCP protocol.

## Status: ✅ Phase 1 Complete - Chat Bridge Working!

Chat bidirectional funcionando entre Factorio y Claude Code.

## Quick Start Guide

### 1. Install Dependencies

```bash
bun install
```

### 2. Install Factorio Mod

**Windows:**
```bash
xcopy /E /I factorio-mod "%APPDATA%\Factorio\mods\ai-companion"
```

**Linux/Mac:** See `factorio-mod/README.md`

### 3. Start Factorio with RCON

1. Launch Factorio
2. **Main Menu → New Game**
3. ✅ **Check "Start as server"** (critical!)
4. **Settings → Network:**
   - RCON Port: `27000`
   - RCON Password: `factorio`
5. **Play!**

### 4. Test RCON Connection (Optional)

```bash
bun run src/rcon/test-connection.ts
```

Expected output:
```
✅ RCON connected on attempt 1
✅ Connection successful!
✅ RCON is working!
```

### 5. Start MCP Server

```bash
bun run src/index.ts
```

Expected output:
```
🚀 Starting Factorio MCP Server...
✅ RCON connected on attempt 1
📡 RCON connected to Factorio
✅ MCP server running on stdio

💡 Server is ready! Claude Code can now use:
   - get_companion_messages
   - send_companion_message
```

### 6. Connect Claude Code

The `.mcp.json` file in this project root configures Claude Code to use this server.

Claude Code will automatically start the MCP server when needed.

### 7. Test It!

**In Factorio chat:**
```
/companion Hello Claude! Can you help me?
```

**In Claude Code:**
```
Use the get_companion_messages tool
```

Claude will see:
```json
[
  {
    "player": "YourName",
    "message": "Hello Claude! Can you help me?",
    "tick": 12345
  }
]
```

**Claude can respond:**
```
Use send_companion_message with "Hello! I'm here to help!"
```

**In Factorio, you'll see:**
```
[AI Companion] Hello! I'm here to help!
```

## Tools Available

### `get_companion_messages`
Get unread messages from Factorio chat starting with `/companion`.

**Returns:** Array of `{player, message, tick}`

### `send_companion_message`
Send a message to Factorio chat as AI Companion.

**Input:** `{ message: string }`

## Architecture

```
Factorio (Lua mod captures /companion chat)
    ↕ RCON (TCP port 27000)
Node.js MCP Server (Bun)
    ↕ MCP Protocol (stdio)
Claude Code (You!)
```

## What's Built

- ✅ RCON client with retry logic
- ✅ Chat message parser
- ✅ Factorio Lua mod with FLE patterns
- ✅ MCP server with 2 tools
- ✅ Claude Code integration via .mcp.json

## Phase 2 (Future)

- AI-controlled character
- Game state introspection
- Automated building/crafting
- Multi-agent coordination

## Troubleshooting

**"Connection failed"**
- Make sure Factorio is running
- Check "Start as server" is enabled
- Verify RCON port is 27000
- Verify RCON password is "factorio"

**"No messages"**
- Type `/companion <message>` in Factorio chat (not just "companion")
- Check mod is enabled in Factorio → Mods menu
- Restart Factorio after installing mod

**"Command not found"**
- Make sure Bun is installed: https://bun.sh
- Run `bun --version` to verify

## Development

```bash
# Run tests
bun test

# Test RCON connection
bun run src/rcon/test-connection.ts

# Start MCP server
bun run src/index.ts
```

## Credits

Inspired by [Factorio Learning Environment](https://github.com/JackHopkins/factorio-learning-environment) patterns and best practices.
