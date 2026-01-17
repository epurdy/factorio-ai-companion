#!/usr/bin/env bun
/**
 * Validate MCP tools match Lua commands 1:1
 * Run: bun run scripts/validate-tools.ts
 */

import { readdir, readFile } from "fs/promises";
import { join } from "path";
import { TOOLS, SKILLS } from "../src/mcp/tools";

const LUA_COMMANDS_DIR = "factorio-mod/commands";

async function extractLuaCommands(): Promise<Set<string>> {
  const commands = new Set<string>();
  const files = await readdir(LUA_COMMANDS_DIR);

  for (const file of files) {
    if (!file.endsWith(".lua")) continue;
    const content = await readFile(join(LUA_COMMANDS_DIR, file), "utf-8");

    // Match: commands.add_command("fac_xxx", ...)
    const matches = content.matchAll(/commands\.add_command\s*\(\s*"(fac_[^"]+)"/g);
    for (const match of matches) {
      commands.add(match[1]);
    }
  }

  return commands;
}

function mcpToLua(mcpName: string): string {
  // MCP tool "chat_say" -> Lua command "fac_chat_say"
  return `fac_${mcpName}`;
}

function luaToMcp(luaName: string): string {
  // Lua command "fac_chat_say" -> MCP tool "chat_say"
  return luaName.replace(/^fac_/, "");
}

async function main() {
  console.log("🔍 Validating MCP tools vs Lua commands...\n");

  const luaCommands = await extractLuaCommands();
  const mcpTools = new Set(Object.keys(TOOLS));
  const skills = new Set(Object.keys(SKILLS));

  // Special tools handled in TS (not 1:1 with Lua)
  const specialTools = new Set(["companion_status", "companion_stop"]);

  let errors = 0;

  // Check: Each MCP tool has a Lua command
  console.log("📋 MCP Tools -> Lua Commands:");
  for (const mcpTool of mcpTools) {
    const luaCmd = mcpToLua(mcpTool);
    const exists = luaCommands.has(luaCmd);
    const icon = exists ? "✅" : "❌";
    if (!exists) {
      console.log(`  ${icon} ${mcpTool} -> ${luaCmd} (MISSING IN LUA)`);
      errors++;
    }
  }

  // Check: Each Lua command has an MCP tool
  console.log("\n📋 Lua Commands -> MCP Tools:");
  for (const luaCmd of luaCommands) {
    const mcpTool = luaToMcp(luaCmd);
    const inTools = mcpTools.has(mcpTool);
    const inSkills = skills.has(mcpTool);
    const isSpecial = specialTools.has(mcpTool);

    if (!inTools && !inSkills && !isSpecial) {
      console.log(`  ❌ ${luaCmd} -> ${mcpTool} (NOT EXPOSED IN MCP)`);
      errors++;
    }
  }

  // Summary
  console.log("\n📊 Summary:");
  console.log(`  Lua commands: ${luaCommands.size}`);
  console.log(`  MCP tools: ${mcpTools.size}`);
  console.log(`  Skills: ${skills.size}`);
  console.log(`  Special tools: ${specialTools.size}`);

  if (errors === 0) {
    console.log("\n✅ All tools are 1:1 mapped!");
  } else {
    console.log(`\n❌ Found ${errors} mismatches!`);
    process.exit(1);
  }
}

main().catch(console.error);
