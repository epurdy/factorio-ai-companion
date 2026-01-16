import { describe, test, expect } from "bun:test";
import { parseCompanionCommand } from "./parser";

describe("Chat Parser", () => {
  test("should parse /companion command", () => {
    const result = parseCompanionCommand("/companion Hello Claude!");
    expect(result.isCompanionCommand).toBe(true);
    expect(result.message).toBe("Hello Claude!");
  });

  test("should parse /companion with multiple words", () => {
    const result = parseCompanionCommand("/companion What should I build next?");
    expect(result.isCompanionCommand).toBe(true);
    expect(result.message).toBe("What should I build next?");
  });

  test("should ignore non-companion messages", () => {
    const result = parseCompanionCommand("regular chat message");
    expect(result.isCompanionCommand).toBe(false);
    expect(result.message).toBeUndefined();
  });

  test("should ignore /companion without message", () => {
    const result = parseCompanionCommand("/companion");
    expect(result.isCompanionCommand).toBe(false);
  });
});
