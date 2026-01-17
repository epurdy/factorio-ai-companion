import { RCONClient } from "./rcon/client";
import { getRCONConfig } from "./config";
import { connectWithRetry, sleep } from "./utils/connection";

const POLL_INTERVAL = 1500;

const companionId = parseInt(process.argv[2]);
if (!companionId || isNaN(companionId)) {
  console.error("Usage: bun run src/companion-agent.ts <companion_id>");
  process.exit(1);
}

const rcon = new RCONClient(getRCONConfig());

async function getMessagesForMe(): Promise<
  Array<{ player: string; message: string; tick: number; target_companion?: number }>
> {
  const response = await rcon.sendCommand(`/fac_chat_get ${companionId}`);
  if (!response.success || !response.data) return [];

  try {
    return JSON.parse(response.data);
  } catch {
    return [];
  }
}

async function say(message: string): Promise<void> {
  await rcon.sendCommand(`/fac_chat_say ${companionId} ${message}`);
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

    await sleep(POLL_INTERVAL);
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
