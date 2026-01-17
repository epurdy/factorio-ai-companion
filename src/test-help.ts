// Test the /companion_help command
import { RCONClient } from "./rcon/client";

const rcon = new RCONClient({
  host: process.env.FACTORIO_HOST || "127.0.0.1",
  port: parseInt(process.env.FACTORIO_RCON_PORT || "34198"),
  password: process.env.FACTORIO_RCON_PASSWORD || "factorio",
});

async function main() {
  try {
    await rcon.connect();
    console.log("Connected to RCON");

    const response = await rcon.sendCommand("/fac_help");

    console.log("Raw response:", response);

    if (response.success && response.data) {
      try {
        const help = JSON.parse(response.data);
        console.log("\n=== Companion Commands (v" + help.version + ") ===\n");

        help.commands.forEach((cmd: any, i: number) => {
          console.log(`${i + 1}. ${cmd.name} ${cmd.params}`);
          console.log(`   ${cmd.description}`);
          console.log(`   Examples: ${cmd.examples.join(", ")}`);
          console.log();
        });

        console.log("Notes:");
        help.notes.forEach((note: string) => console.log(`- ${note}`));
      } catch (e) {
        console.error("JSON parse error. Response data:", response.data);
      }
    } else {
      console.error("Failed to get help:", response);
    }

    await rcon.disconnect();
  } catch (e) {
    console.error("Error:", e);
    process.exit(1);
  }
}

main();
