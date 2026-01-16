# Factorio AI Companion

Bidirectional chat bridge between Factorio and Claude Code via MCP protocol.

## Status: 🚧 In Development

Currently implementing Phase 1: Chat Bridge

## Quick Start

```bash
# Install dependencies
bun install

# Run (once implemented)
bun run src/index.ts
```

## What's Built So Far

- ✅ Project structure
- ⏳ RCON client (next)
- ⏳ Lua mod
- ⏳ MCP server

## Prerequisites

- [Bun](https://bun.sh) runtime installed
- Factorio 2.x or 1.1+
- Claude Code CLI

## How It Will Work

1. Install Lua mod in Factorio
2. Start Factorio with "Start as server" (enables RCON)
3. Run MCP server: `bun run src/index.ts`
4. In Factorio chat: `/companion Hello!`
5. Claude Code receives and responds

See `docs/plans/` for full implementation plan.
