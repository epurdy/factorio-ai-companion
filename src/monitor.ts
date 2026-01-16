import { RCONClient } from './rcon/client';

const client = new RCONClient({
  host: '127.0.0.1',
  port: parseInt(process.env.FACTORIO_RCON_PORT || '34198'),
  password: process.env.FACTORIO_RCON_PASSWORD || 'factorio'
});

async function checkMessages() {
  try {
    await client.connect();

    while (true) {
      const response = await client.sendCommand('/companion_get_messages');

      if (response.success && response.data) {
        try {
          const messages = JSON.parse(response.data);

          if (Array.isArray(messages) && messages.length > 0) {
            messages.forEach((msg: any) => {
              console.log(`[${msg.player}]: ${msg.message}`);
            });
          }
        } catch (e) {
          // Ignore parse errors
        }
      }

      await new Promise(resolve => setTimeout(resolve, 3000));
    }
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

checkMessages();
