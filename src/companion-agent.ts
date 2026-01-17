// Companion Agent - runs as background process for a specific companion
// Usage: bun run src/companion-agent.ts <companion_id>

import { RCONClient } from "./rcon/client";

const POLL_INTERVAL = 1500;

const companionId = parseInt(process.argv[2]);
if (!companionId || isNaN(companionId)) {
  console.error("Usage: bun run src/companion-agent.ts <companion_id>");
  process.exit(1);
}

const rcon = new RCONClient({
  host: process.env.FACTORIO_HOST || "127.0.0.1",
  port: parseInt(process.env.FACTORIO_RCON_PORT || "34198"),
  password: process.env.FACTORIO_RCON_PASSWORD || "factorio",
});

async function getMessagesForMe(): Promise<
  Array<{ player: string; message: string; tick: number; target_companion?: number }>
> {
  const response = await rcon.sendCommand("/companion_get_messages");
  if (!response.success || !response.data) return [];

  try {
    const all = JSON.parse(response.data);
    // Filter only messages targeted at this companion
    return all.filter(
      (m: { target_companion?: number }) => m.target_companion === companionId
    );
  } catch {
    return [];
  }
}

async function say(message: string): Promise<void> {
  await rcon.sendCommand(`/companion_say ${companionId} ${message}`);
}

async function pollLoop(): Promise<void> {
  console.log(`[Companion #${companionId}] Starting poll loop...`);

  while (true) {
    const messages = await getMessagesForMe();

    for (const msg of messages) {
      console.log(`[Companion #${companionId}] Got message from ${msg.player}: ${msg.message}`);
      // Output as JSON for the parent process to handle
      console.log(JSON.stringify({ companionId, ...msg }));
    }

    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL));
  }
}

async function main(): Promise<void> {
  try {
    await rcon.connect();
    console.log(`[Companion #${companionId}] RCON connected`);
    await say(`Soy companion #${companionId}, listo para ayudar!`);
    await pollLoop();
  } catch (error) {
    console.error(`[Companion #${companionId}] Error:`, error);
    process.exit(1);
  }
}

main();
