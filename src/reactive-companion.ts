// Reactive Companion Listener - independent agent for a specific companion
// Usage: bun run src/reactive-companion.ts <companion_id>
// - Ensures companion entity exists (spawns if needed)
// - Announces itself in-game
// - Polls for messages and exits with JSON when one arrives

import { RCONClient } from "./rcon/client";

const POLL_INTERVAL = 1000;
const MAX_RETRIES = 5;

const companionId = parseInt(process.argv[2]);
if (!companionId || isNaN(companionId)) {
  console.error("Usage: bun run src/reactive-companion.ts <companion_id>");
  process.exit(1);
}

const rcon = new RCONClient({
  host: process.env.FACTORIO_HOST || "127.0.0.1",
  port: parseInt(process.env.FACTORIO_RCON_PORT || "34198"),
  password: process.env.FACTORIO_RCON_PASSWORD || "factorio",
});

async function connectWithRetry(): Promise<void> {
  for (let i = 0; i < MAX_RETRIES; i++) {
    try {
      await rcon.connect();
      console.error(`[#${companionId}] RCON connected`);
      return;
    } catch (e) {
      console.error(`[#${companionId}] Retry ${i + 1}/${MAX_RETRIES}...`);
      await new Promise((r) => setTimeout(r, 2000));
    }
  }
  throw new Error("Failed to connect to RCON");
}

async function ensureCompanionExists(): Promise<boolean> {
  // Spawn with specific ID (will be ignored if already exists)
  const spawnResp = await rcon.sendCommand(`/fac_companion_spawn id=${companionId}`);
  if (spawnResp.success && spawnResp.data) {
    try {
      const result = JSON.parse(spawnResp.data);
      if (result.status === "already_exists") {
        console.error(`[#${companionId}] Companion already exists`);
      } else if (result.spawned) {
        console.error(`[#${companionId}] Spawned new companion`);
      }
      return true;
    } catch {
      return false;
    }
  }
  return false;
}

async function say(message: string): Promise<void> {
  await rcon.sendCommand(`/fac_chat_say ${companionId} ${message}`);
}

async function checkMessages(): Promise<
  { player: string; message: string; tick: number } | null
> {
  // Get only messages targeted at this companion
  const response = await rcon.sendCommand(`/fac_chat_get ${companionId}`);
  if (!response.success || !response.data) return null;

  try {
    const msgs = JSON.parse(response.data);
    return msgs.length > 0 ? msgs[0] : null;
  } catch {
    return null;
  }
}

async function main(): Promise<void> {
  await connectWithRetry();

  // Ensure companion entity exists
  await ensureCompanionExists();

  // Announce presence
  await say("Listo! Esperando instrucciones...");
  console.error(`[#${companionId}] Waiting for messages...`);

  while (true) {
    const msg = await checkMessages();
    if (msg) {
      // Output JSON and exit - parent process will handle the response
      console.log(JSON.stringify({ companionId, ...msg }));
      await rcon.disconnect();
      process.exit(0);
    }
    await new Promise((r) => setTimeout(r, POLL_INTERVAL));
  }
}

main().catch((e) => {
  console.error(`[#${companionId}] Fatal error:`, e);
  process.exit(1);
});
