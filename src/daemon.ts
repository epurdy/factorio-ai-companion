/**
 * Factorio AI Companion Daemon
 *
 * Unified polling daemon that:
 * 1. Connects to Factorio via RCON
 * 2. Polls for /companion and /fac messages every 2 seconds
 * 3. Prints messages to console
 * 4. Can send responses back to Factorio
 *
 * Usage: bun run src/daemon.ts
 */

import { RCONClient } from './rcon/client';

const POLL_INTERVAL = 2000; // 2 seconds

const client = new RCONClient({
  host: process.env.FACTORIO_HOST || '127.0.0.1',
  port: parseInt(process.env.FACTORIO_RCON_PORT || '34198'),
  password: process.env.FACTORIO_RCON_PASSWORD || 'factorio'
});

let connected = false;

async function connectWithRetry(): Promise<boolean> {
  const maxRetries = 5;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      console.log(`🔌 Connecting to RCON (attempt ${attempt}/${maxRetries})...`);
      await client.connect();
      console.log('✅ Connected to Factorio RCON!');
      return true;
    } catch (error) {
      console.error(`❌ Connection failed: ${error}`);
      if (attempt < maxRetries) {
        const delay = 2000 * attempt;
        console.log(`⏳ Retrying in ${delay/1000}s...`);
        await sleep(delay);
      }
    }
  }

  return false;
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function pollMessages(): Promise<void> {
  try {
    const response = await client.sendCommand('/companion_get_messages');

    if (response.success && response.data) {
      const messages = JSON.parse(response.data || '[]');

      if (Array.isArray(messages) && messages.length > 0) {
        console.log('\n' + '='.repeat(50));
        console.log('📬 NEW MESSAGES:');
        console.log('='.repeat(50));

        messages.forEach((msg: { player: string; message: string; tick: number }) => {
          console.log(`[${msg.player}] ${msg.message}`);
        });

        console.log('='.repeat(50) + '\n');
      }
    }
  } catch (error) {
    // Connection lost - try to reconnect
    console.error('⚠️ Poll error, reconnecting...');
    connected = false;
  }
}

async function sendResponse(message: string): Promise<boolean> {
  try {
    const response = await client.sendCommand(`/companion_send ${message}`);
    return response.success;
  } catch (error) {
    console.error('❌ Failed to send:', error);
    return false;
  }
}

async function main() {
  console.log('🤖 Factorio AI Companion Daemon');
  console.log('================================');
  console.log(`📡 Target: ${process.env.FACTORIO_HOST || '127.0.0.1'}:${process.env.FACTORIO_RCON_PORT || '34198'}`);
  console.log(`⏱️  Poll interval: ${POLL_INTERVAL/1000}s`);
  console.log('');

  // Wait for Factorio to be available
  while (!connected) {
    connected = await connectWithRetry();
    if (!connected) {
      console.log('⏳ Factorio not available. Waiting 10s...');
      console.log('   Start Factorio: Multiplayer → Host New Game');
      await sleep(10000);
    }
  }

  console.log('🔄 Starting message polling...');
  console.log('💡 Messages from /companion or /fac will appear here\n');

  // Main polling loop
  while (true) {
    if (!connected) {
      console.log('🔄 Reconnecting...');
      connected = await connectWithRetry();

      if (!connected) {
        console.log('⏳ Waiting 10s before retry...');
        await sleep(10000);
        continue;
      }
    }

    await pollMessages();
    await sleep(POLL_INTERVAL);
  }
}

// Handle graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n👋 Shutting down...');
  await client.disconnect();
  process.exit(0);
});

// Export for potential programmatic use
export { sendResponse, pollMessages };

// Run
main().catch(console.error);
