import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { RCONClient } from "../rcon/client";
import { SendMessageSchema } from "./tools";

export class FactorioMCPServer {
  private server: Server;
  private rcon: RCONClient;
  private pollingInterval?: NodeJS.Timeout;

  constructor(rconConfig: { host: string; port: number; password: string }) {
    this.server = new Server(
      {
        name: "factorio-companion",
        version: "0.2.1",
      },
      {
        capabilities: {
          tools: {},
        },
      }
    );

    this.rcon = new RCONClient(rconConfig);
    this.setupHandlers();
  }

  private setupHandlers() {
    this.server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: [
        {
          name: "get_companion_messages",
          description:
            "Get unread messages from Factorio chat. Returns array of {player, message, tick}.",
          inputSchema: {
            type: "object",
            properties: {},
          },
        },
        {
          name: "send_companion_message",
          description:
            "Send a message to Factorio chat as Claude. Appears in green text.",
          inputSchema: {
            type: "object",
            properties: {
              message: {
                type: "string",
                description: "Message to send to Factorio chat",
              },
            },
            required: ["message"],
          },
        },
      ],
    }));

    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      switch (request.params.name) {
        case "get_companion_messages": {
          const response = await this.rcon.sendCommand("/companion_get_messages");

          if (!response.success) {
            return {
              content: [{ type: "text", text: `Error: ${response.error}` }],
            };
          }

          try {
            const messages = JSON.parse(response.data || "[]");
            return {
              content: [
                {
                  type: "text",
                  text:
                    messages.length > 0
                      ? JSON.stringify(messages, null, 2)
                      : "No new messages",
                },
              ],
            };
          } catch (e) {
            return {
              content: [{ type: "text", text: `Parse error: ${e}` }],
            };
          }
        }

        case "send_companion_message": {
          const parsed = SendMessageSchema.safeParse(request.params.arguments);

          if (!parsed.success) {
            return {
              content: [{ type: "text", text: `Invalid arguments: ${parsed.error}` }],
            };
          }

          const response = await this.rcon.sendCommand(
            `/companion_send ${parsed.data.message}`
          );

          return {
            content: [
              {
                type: "text",
                text: response.success
                  ? "Message sent"
                  : `Error: ${response.error}`,
              },
            ],
          };
        }

        default:
          throw new Error(`Unknown tool: ${request.params.name}`);
      }
    });
  }

  private async checkForMessages() {
    try {
      const response = await this.rcon.sendCommand("/companion_get_messages");

      if (response.success && response.data) {
        const messages = JSON.parse(response.data || "[]");

        if (Array.isArray(messages) && messages.length > 0) {
          messages.forEach((msg: { player: string; message: string; tick: number }) => {
            this.server.notification({
              method: "notifications/message",
              params: {
                level: "info",
                logger: "factorio-companion",
                data: msg,
              },
            });
          });

          console.error(`Sent ${messages.length} notification(s)`);
        }
      }
    } catch (error) {
      // Silently ignore polling errors
    }
  }

  private startPolling() {
    console.error("Starting message polling (every 3 seconds)...");

    this.pollingInterval = setInterval(async () => {
      await this.checkForMessages();
    }, 3000);
  }

  async start() {
    console.error("Starting Factorio MCP Server...");
    await this.rcon.connect();
    console.error("RCON connected");

    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error("MCP server running on stdio");

    this.startPolling();
  }

  async stop() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
    }
    await this.rcon.disconnect();
  }
}
