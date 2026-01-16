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

  constructor(rconConfig: { host: string; port: number; password: string }) {
    this.server = new Server(
      {
        name: "factorio-companion",
        version: "0.1.0",
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
            "Get unread messages from Factorio chat starting with /companion. Returns array of {player, message, tick}.",
          inputSchema: {
            type: "object",
            properties: {},
          },
        },
        {
          name: "send_companion_message",
          description:
            "Send a message to Factorio chat as AI Companion. The message will appear in green text for all players.",
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
                  ? "Message sent successfully to Factorio chat"
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

  async start() {
    console.error("🚀 Starting Factorio MCP Server...");
    await this.rcon.connect();
    console.error("📡 RCON connected to Factorio");

    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error("✅ MCP server running on stdio");
    console.error("\n💡 Server is ready! Claude Code can now use:");
    console.error("   - get_companion_messages");
    console.error("   - send_companion_message\n");
  }
}
