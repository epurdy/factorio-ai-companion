/**
 * Reactive All-Companions Message Checker
 * Polls RCON for ALL messages (orchestrator + all companions)
 * Exits with JSON array when messages are found
 * Usage: bun run src/reactive-all.ts
 * Output: JSON array of {companionId, player, message, tick}
 */

import { RCONClient } from './rcon/client';

const POLL_INTERVAL = 100; // 100ms polling (can add exponential backoff later)
const MAX_RETRIES = 5;

const client = new RCONClient({
  host: process.env.FACTORIO_HOST || '127.0.0.1',
  port: parseInt(process.env.FACTORIO_RCON_PORT || '34198'),
  password: process.env.FACTORIO_RCON_PASSWORD || 'factorio'
});

async function connectWithRetry(): Promise<void> {
  for (let i = 0; i < MAX_RETRIES; i++) {
    try {
      await client.connect();
      console.error('✅ Connected to RCON');
      return;
    } catch (e) {
      console.error(`Connection attempt ${i + 1}/${MAX_RETRIES} failed...`);
      await new Promise(r => setTimeout(r, 2000));
    }
  }
  throw new Error('Failed to connect to RCON');
}

async function pollAllMessages(): Promise<void> {
  try {
    await connectWithRetry();
    console.error('Polling for messages (all companions)...');

    while (true) {
      // Get ALL unread messages (no filter)
      const response = await client.sendCommand('/fac_chat_get');

      if (response.success && response.data) {
        try {
          const messages = JSON.parse(response.data);

          if (Array.isArray(messages) && messages.length > 0) {
            // Transform messages to include companionId
            const enrichedMessages = messages.map((msg: any) => ({
              companionId: msg.target_companion || 0, // 0 = orchestrator
              player: msg.player,
              message: msg.message,
              tick: msg.tick
            }));

            // Output JSON array and exit
            console.log(JSON.stringify(enrichedMessages));
            await client.disconnect();
            process.exit(0);
          }
        } catch (parseError) {
          console.error('Failed to parse response:', parseError);
        }
      }

      await new Promise(r => setTimeout(r, POLL_INTERVAL));
    }
  } catch (error) {
    console.error('Fatal error:', error);
    process.exit(1);
  }
}

pollAllMessages();
