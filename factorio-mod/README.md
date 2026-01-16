# AI Companion - Factorio Mod

## Installation

### Windows
```bash
xcopy /E /I factorio-mod "%APPDATA%\Factorio\mods\ai-companion"
```

### Linux
```bash
cp -r factorio-mod ~/.factorio/mods/ai-companion
```

### Mac
```bash
cp -r factorio-mod ~/Library/Application\ Support/factorio/mods/ai-companion
```

## Enable the Mod

1. Launch Factorio
2. Main Menu → Mods
3. Find "AI Companion" in the list
4. ✅ Enable it
5. Restart Factorio

## Usage

### In-Game Chat Commands

**Send message to AI:**
```
/companion Hello! Can you help me?
```

### RCON Commands (for MCP server)

**Get unread messages:**
```
/companion_get_messages
```

**Send response to chat:**
```
/companion_send Your message here
```

**Cleanup old messages:**
```
/companion_cleanup
```

## Features

- ✅ Chat message capture with `/companion` prefix
- ✅ Safe error handling (pcall wrappers)
- ✅ JSON serialization for RCON
- ✅ Auto-cleanup of old messages
- ✅ Compatible with Factorio 2.x and 1.1+

## Requirements

- Factorio must be started with "Start as server" option
- RCON must be enabled (port 27000, password: factorio)
