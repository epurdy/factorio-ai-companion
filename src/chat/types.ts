export interface ChatMessage {
  player: string;
  message: string;
  tick: number;
}

export interface CommandMatch {
  isCompanionCommand: boolean;
  message?: string;
}
