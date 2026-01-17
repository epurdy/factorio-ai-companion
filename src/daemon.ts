import { RCONClient } from './rcon/client';
import { getRCONConfig } from './config';
import { connectWithRetry, sleep } from './utils/connection';

const POLL_INTERVAL = 2000;

const client = new RCONClient(getRCONConfig());

let connected = false;

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
    try {
      await connectWithRetry(client, 5);
      connected = true;
    } catch (error) {
      console.log('Factorio not available. Waiting 10s...');
      console.log('Start Factorio: Multiplayer > Host New Game');
      await sleep(10000);
    }
  }

  console.log('Starting message polling...\n');

  while (true) {
    if (!connected) {
      console.log('Reconnecting...');
      try {
        await connectWithRetry(client, 5);
        connected = true;
      } catch (error) {
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
