// Simple test script to verify RCON connection
// Run with: bun run src/rcon/test-connection.ts

import { RCONClient } from "./client";

async function testConnection() {
  console.log("🧪 Testing RCON connection...\n");

  const client = new RCONClient({
    host: process.env.FACTORIO_HOST || "127.0.0.1",
    port: parseInt(process.env.FACTORIO_RCON_PORT || "27000"),
    password: process.env.FACTORIO_RCON_PASSWORD || "factorio",
  });

  try {
    console.log("📡 Connecting to Factorio RCON...");
    await client.connect();

    console.log("\n✅ Connection successful!");
    console.log("\n📤 Sending test command: /time");

    const response = await client.sendCommand("/time");

    if (response.success) {
      console.log("📥 Response:", response.data || "(no output)");
      console.log("\n✅ RCON is working!");
    } else {
      console.log("❌ Command failed:", response.error);
    }

    await client.disconnect();
    console.log("\n👋 Disconnected");

  } catch (error) {
    console.error("\n❌ Connection failed:", error);
    console.log("\n💡 Make sure:");
    console.log("   1. Factorio is running");
    console.log("   2. Started with 'Start as server' option");
    console.log("   3. RCON port is 27000 (or update .env)");
    console.log("   4. RCON password is 'factorio' (or update .env)");
    process.exit(1);
  }
}

testConnection();
