import { RCONClient } from './rcon/client';
import { getRCONConfig } from './config';
import { connectWithRetry, sleep } from './utils/connection';

const POLL_INTERVAL = 100;

const client = new RCONClient(getRCONConfig());

async function pollAllMessages(): Promise<void> {
  try {
    await connectWithRetry(client);
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

      await sleep(POLL_INTERVAL);
    }
  } catch (error) {
    console.error('Fatal error:', error);
    process.exit(1);
  }
}

pollAllMessages();
