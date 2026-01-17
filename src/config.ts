export interface RCONConfig {
  host: string;
  port: number;
  password: string;
}

export function getRCONConfig(): RCONConfig {
  return {
    host: process.env.FACTORIO_HOST || "127.0.0.1",
    port: parseInt(process.env.FACTORIO_RCON_PORT || "34198"),
    password: process.env.FACTORIO_RCON_PASSWORD || "factorio"
  };
}

export function validateRCONConfig(config: RCONConfig): void {
  if (!config.host) {
    throw new Error("RCON host cannot be empty");
  }
  if (config.port <= 0 || config.port > 65535) {
    throw new Error(`Invalid RCON port: ${config.port}`);
  }
  if (!config.password) {
    throw new Error("RCON password cannot be empty");
  }
}
