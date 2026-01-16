import { z } from "zod";

export const GetMessagesSchema = z.object({});

export const SendMessageSchema = z.object({
  message: z.string().describe("Message to send to Factorio chat"),
});

export type GetMessagesInput = z.infer<typeof GetMessagesSchema>;
export type SendMessageInput = z.infer<typeof SendMessageSchema>;
