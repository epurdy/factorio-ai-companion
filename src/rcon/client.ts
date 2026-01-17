import { Socket } from "net";
import { RCONConfig, RCONResponse } from "./types";

export class RCONClient {
  private socket: Socket | null = null;
  private connected = false;
  private config: RCONConfig;
  private requestId = 1;
  private commandTimeout = 5000; // 5 second timeout per command

  constructor(config: RCONConfig) {
    this.config = config;
  }

  async connect(): Promise<void> {
    return this.connectWithRetry(3);
  }

  private async connectWithRetry(maxRetries: number): Promise<void> {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await this.connectOnce();
        console.error(`✅ RCON connected on attempt ${attempt}`);
        return;
      } catch (error: any) {
        const errorMsg = error?.message || String(error);
        console.error(`❌ RCON connection attempt ${attempt} failed:`, errorMsg);

        if (attempt === maxRetries) {
          const isConnectionRefused = errorMsg.includes("ECONNREFUSED") || errorMsg.includes("connect");
          if (isConnectionRefused) {
            throw new Error(
              `❌ Cannot connect to Factorio RCON (${this.config.host}:${this.config.port})\n\n` +
              `SOLUTION: Start Factorio in Multiplayer mode\n` +
              `1. Launch Factorio\n` +
              `2. Go to: Multiplayer → Host New Game\n` +
              `3. RCON will be automatically enabled\n\n` +
              `RCON config should be in %APPDATA%\\Factorio\\config\\config.ini:\n` +
              `  local-rcon-socket=127.0.0.1:34198\n` +
              `  local-rcon-password=factorio\n\n` +
              `If missing, add those lines and restart Factorio.\n\n` +
              `Original error: ${errorMsg}`
            );
          }
          throw new Error(`Failed to connect after ${maxRetries} attempts: ${errorMsg}`);
        }

        // Exponential backoff: 1s, 2s, 4s
        await this.sleep(1000 * Math.pow(2, attempt - 1));
      }
    }
  }

  private async connectOnce(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.socket = new Socket();
      this.socket.setTimeout(this.commandTimeout);

      this.socket.on("connect", () => {
        this.authenticate()
          .then(() => {
            this.connected = true;
            resolve();
          })
          .catch(reject);
      });

      this.socket.on("error", (err) => {
        this.connected = false;
        reject(err);
      });

      this.socket.on("timeout", () => {
        this.socket?.destroy();
        reject(new Error("Socket timeout"));
      });

      this.socket.connect(this.config.port, this.config.host);
    });
  }

  private async authenticate(): Promise<void> {
    const packet = this.createPacket(3, this.config.password);
    return new Promise((resolve, reject) => {
      if (!this.socket) return reject(new Error("Socket not initialized"));

      this.socket.write(packet);

      const timeout = setTimeout(() => {
        reject(new Error("Authentication timeout"));
      }, this.commandTimeout);

      this.socket.once("data", (data) => {
        clearTimeout(timeout);
        const response = this.parsePacket(data);
        if (response.id === -1) {
          reject(new Error("Authentication failed - invalid password"));
        } else {
          resolve();
        }
      });
    });
  }

  async sendCommand(command: string, timeoutMs?: number): Promise<RCONResponse> {
    if (!this.connected) {
      // Try to reconnect
      try {
        await this.connect();
      } catch (error) {
        return { success: false, data: "", error: "Not connected and reconnect failed" };
      }
    }

    const packet = this.createPacket(2, command);

    return new Promise((resolve) => {
      if (!this.socket) {
        return resolve({ success: false, data: "", error: "Socket not initialized" });
      }

      let resolved = false;
      const cleanup = () => {
        if (this.socket) {
          this.socket.removeListener("data", onData);
          this.socket.removeListener("error", onError);
        }
        clearTimeout(timeout);
      };

      const finish = (result: RCONResponse) => {
        if (!resolved) {
          resolved = true;
          cleanup();
          resolve(result);
        }
      };

      const timeout = setTimeout(() => {
        finish({
          success: false,
          data: "",
          error: `Command timeout after ${timeoutMs || this.commandTimeout}ms`,
        });
      }, timeoutMs || this.commandTimeout);

      const onData = (data: Buffer) => {
        const response = this.parsePacket(data);
        finish({ success: true, data: response.payload });
      };

      const onError = (err: Error) => {
        this.connected = false;
        finish({ success: false, data: "", error: err.message });
      };

      this.socket.once("data", onData);
      this.socket.once("error", onError);
      this.socket.write(packet);
    });
  }

  private createPacket(type: number, payload: string): Buffer {
    const id = this.requestId++;
    const payloadBuffer = Buffer.from(payload, "utf8");
    const length = payloadBuffer.length + 10;

    const packet = Buffer.alloc(length + 4);
    packet.writeInt32LE(length, 0);
    packet.writeInt32LE(id, 4);
    packet.writeInt32LE(type, 8);
    payloadBuffer.copy(packet, 12);
    packet.writeInt8(0, packet.length - 2);
    packet.writeInt8(0, packet.length - 1);

    return packet;
  }

  private parsePacket(buffer: Buffer): { id: number; type: number; payload: string } {
    const id = buffer.readInt32LE(4);
    const type = buffer.readInt32LE(8);
    const payload = buffer.toString("utf8", 12, buffer.length - 2);

    return { id, type, payload };
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  isConnected(): boolean {
    return this.connected;
  }

  async disconnect(): Promise<void> {
    if (this.socket) {
      this.socket.destroy();
      this.socket = null;
      this.connected = false;
    }
  }
}
