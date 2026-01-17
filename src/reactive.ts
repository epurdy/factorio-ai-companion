/**
 * Reactive Message Checker
 *
 * Polls RCON until a message is found, then prints it and exits.
 * Designed to be used with TaskOutput blocking for reactive pattern.
 *
 * Usage: bun run src/reactive.ts
 *
 * Output format (JSON on last line):
 * {"player":"name","message":"text","tick":123}
 */

import { RCONClient } from './rcon/client';

const POLL_INTERVAL = 1000; // 1 second for faster response

const client = new RCONClient({
  host: process.env.FACTORIO_HOST || '127.0.0.1',
  port: parseInt(process.env.FACTORIO_RCON_PORT || '34198'),
  password: process.env.FACTORIO_RCON_PASSWORD || 'factorio'
});

async function waitForMessage(): Promise<void> {
  try {
    await client.connect();
    console.error('Connected. Waiting for message...');

    while (true) {
      const response = await client.sendCommand('/companion_get_messages');

      if (response.success && response.data) {
        const messages = JSON.parse(response.data || '[]');

        if (Array.isArray(messages) && messages.length > 0) {
          // Output each message as JSON (stdout for parsing)
          messages.forEach((msg: { player: string; message: string; tick: number }) => {
            console.log(JSON.stringify(msg));
          });

          // Exit successfully - message found
          await client.disconnect();
          process.exit(0);
        }
      }

      await new Promise(r => setTimeout(r, POLL_INTERVAL));
    }
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

waitForMessage();
