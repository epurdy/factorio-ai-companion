/**
 * Factorio AI Companion Daemon
 * Continuous polling daemon for message monitoring.
 * Usage: bun run src/daemon.ts
 */

import { RCONClient } from './rcon/client';

const POLL_INTERVAL = 2000;

const client = new RCONClient({
  host: process.env.FACTORIO_HOST || '127.0.0.1',
  port: parseInt(process.env.FACTORIO_RCON_PORT || '34198'),
  password: process.env.FACTORIO_RCON_PASSWORD || 'factorio'
});

let connected = false;

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function connectWithRetry(): Promise<boolean> {
  const maxRetries = 5;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      console.log(`Connecting to RCON (attempt ${attempt}/${maxRetries})...`);
      await client.connect();
      console.log('Connected to Factorio RCON');
      return true;
    } catch (error) {
      console.error(`Connection failed: ${error}`);
      if (attempt < maxRetries) {
        const delay = 2000 * attempt;
        console.log(`Retrying in ${delay/1000}s...`);
        await sleep(delay);
      }
    }
  }
  return false;
}

async function pollMessages(): Promise<void> {
  try {
    const response = await client.sendCommand('/fac_chat_get orchestrator');

    if (response.success && response.data) {
      const messages = JSON.parse(response.data || '[]');

      if (Array.isArray(messages) && messages.length > 0) {
        console.log('\n--- NEW MESSAGES ---');
        messages.forEach((msg: { player: string; message: string; tick: number }) => {
          console.log(`[${msg.player}] ${msg.message}`);
        });
        console.log('--------------------\n');
      }
    }
  } catch (error) {
    console.error('Poll error, reconnecting...');
    connected = false;
  }
}

async function sendResponse(message: string): Promise<boolean> {
  try {
    const response = await client.sendCommand(`/fac_chat_say 0 ${message}`);
    return response.success;
  } catch (error) {
    console.error('Failed to send:', error);
    return false;
  }
}

async function main() {
  console.log('Factorio AI Companion Daemon');
  console.log(`Target: ${process.env.FACTORIO_HOST || '127.0.0.1'}:${process.env.FACTORIO_RCON_PORT || '34198'}`);
  console.log(`Poll interval: ${POLL_INTERVAL/1000}s\n`);

  while (!connected) {
    connected = await connectWithRetry();
    if (!connected) {
      console.log('Factorio not available. Waiting 10s...');
      console.log('Start Factorio: Multiplayer > Host New Game');
      await sleep(10000);
    }
  }

  console.log('Starting message polling...\n');

  while (true) {
    if (!connected) {
      console.log('Reconnecting...');
      connected = await connectWithRetry();
      if (!connected) {
        console.log('Waiting 10s before retry...');
        await sleep(10000);
        continue;
      }
    }

    await pollMessages();
    await sleep(POLL_INTERVAL);
  }
}

process.on('SIGINT', async () => {
  console.log('\nShutting down...');
  await client.disconnect();
  process.exit(0);
});

export { sendResponse, pollMessages };

main().catch(console.error);
