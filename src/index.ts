import { FactorioMCPServer } from "./mcp/server";

const server = new FactorioMCPServer({
  host: process.env.FACTORIO_HOST || "127.0.0.1",
  port: parseInt(process.env.FACTORIO_RCON_PORT || "34198"),
  password: process.env.FACTORIO_RCON_PASSWORD || "factorio",
});

server.start().catch((error) => {
  console.error("Failed to start server:", error);
  process.exit(1);
});
