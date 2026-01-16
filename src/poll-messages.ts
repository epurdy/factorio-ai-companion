import { RCONClient } from './rcon/client';

const client = new RCONClient({
  host: '127.0.0.1',
  port: parseInt(process.env.FACTORIO_RCON_PORT || '34198'),
  password: process.env.FACTORIO_RCON_PASSWORD || 'factorio'
});

let isRunning = true;

process.on('SIGINT', () => {
  console.log('\n\n👋 Stopping message polling...');
  isRunning = false;
  process.exit(0);
});

async function pollMessages() {
  try {
    await client.connect();
    console.log('📡 Connected to Factorio. Monitoring for messages...\n');

    while (isRunning) {
      try {
        const response = await client.sendCommand('/companion_get_messages');

        if (response.success && response.data) {
          const messages = JSON.parse(response.data);

          if (Array.isArray(messages) && messages.length > 0) {
            console.log('\n🔔 New messages from Factorio:');
            messages.forEach((msg: any) => {
              console.log(`  [${msg.player}]: ${msg.message}`);
            });
            console.log('');
          }
        }
      } catch (err) {
        // Ignore parse errors for empty responses
      }

      // Poll every 2 seconds
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.disconnect();
  }
}

pollMessages();
