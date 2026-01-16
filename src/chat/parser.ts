import { CommandMatch } from "./types";

export function parseCompanionCommand(text: string): CommandMatch {
  const companionRegex = /^\/companion\s+(.+)$/;
  const match = text.match(companionRegex);

  if (match) {
    return {
      isCompanionCommand: true,
      message: match[1],
    };
  }

  return { isCompanionCommand: false };
}
