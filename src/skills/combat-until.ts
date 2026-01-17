#!/usr/bin/env bun
import { RCONClient } from "../rcon/client";
import { getRCONConfig } from "../config";
import { sleep } from "../utils/connection";

const POLL_INTERVAL = 500;
const ATTACK_RANGE = 6;
const SCAN_RADIUS = 50;

const companionId = parseInt(process.argv[2]);
const targetType = process.argv[3] || "all"; // all, spawner, worm, biter, spitter
const maxKills = parseInt(process.argv[4]) || 10;

if (!companionId) {
  console.error("Usage: bun run src/skills/combat-until.ts <companionId> [targetType] [maxKills]");
  process.exit(1);
}

const client = new RCONClient(getRCONConfig());

async function say(msg: string): Promise<void> {
  await client.sendCommand(`/fac_chat_say ${companionId} "${msg}"`);
}

async function exec(cmd: string): Promise<any> {
  const response = await client.sendCommand(cmd);
  if (!response.success || !response.data) return null;
  try {
    return JSON.parse(response.data);
  } catch {
    return response.data;
  }
}

async function stopAll(): Promise<void> {
  await exec(`/fac_companion_stop_all ${companionId}`);
}

async function getPosition(): Promise<{x: number, y: number} | null> {
  const data = await exec(`/fac_companion_position ${companionId}`);
  return data?.position || null;
}

async function getHealth(): Promise<{health: number, max: number, pct: number} | null> {
  const data = await exec(`/fac_companion_health ${companionId}`);
  return data?.self || null;
}

interface Enemy {
  name: string;
  type: string;
  position: {x: number, y: number};
  health: number;
  distance: number;
}

async function scanEnemies(): Promise<Enemy[]> {
  const data = await exec(`/fac_world_enemies ${companionId} ${SCAN_RADIUS}`);
  if (!data?.enemies) return [];

  let enemies = data.enemies as Enemy[];

  if (targetType !== "all") {
    enemies = enemies.filter((e: Enemy) => {
      if (targetType === "spawner") return e.type === "unit-spawner";
      if (targetType === "worm") return e.type === "turret";
      if (targetType === "biter") return e.name.includes("biter");
      if (targetType === "spitter") return e.name.includes("spitter");
      return true;
    });
  }

  return enemies.sort((a, b) => a.distance - b.distance);
}

async function walkTo(x: number, y: number): Promise<boolean> {
  await exec(`/fac_move_to ${companionId} ${x} ${y}`);

  const startTime = Date.now();
  const timeout = 30000;

  while (Date.now() - startTime < timeout) {
    const pos = await getPosition();
    if (!pos) break;

    const dist = Math.sqrt(Math.pow(pos.x - x, 2) + Math.pow(pos.y - y, 2));
    if (dist < ATTACK_RANGE) return true;

    await sleep(POLL_INTERVAL);
  }
  return false;
}

async function attack(x: number, y: number): Promise<{kills: number}> {
  const result = await exec(`/fac_action_attack_start ${companionId} ${x} ${y}`);
  if (!result?.started) return {kills: 0};

  let totalKills = 0;
  const startTime = Date.now();
  const timeout = 60000;

  while (Date.now() - startTime < timeout) {
    const status = await exec(`/fac_action_attack_status ${companionId}`);

    if (!status?.status?.active) {
      totalKills = status?.status?.kills || 0;
      break;
    }

    const health = await getHealth();
    if (health && health.pct < 30) {
      await say("Health low, retreating!");
      await exec(`/fac_action_attack_stop ${companionId}`);
      return {kills: totalKills};
    }

    await sleep(POLL_INTERVAL);
  }

  return {kills: totalKills};
}

async function main(): Promise<void> {
  try {
    await client.connect();
    console.log(`[Companion #${companionId}] Starting combat: ${targetType}, max ${maxKills} kills`);

    await stopAll();
    await say(`Combat mode: hunting ${targetType}!`);

    let totalKills = 0;
    let attempts = 0;
    const maxAttempts = 30;

    while (totalKills < maxKills && attempts < maxAttempts) {
      attempts++;

      const enemies = await scanEnemies();
      if (enemies.length === 0) {
        await say(`No more ${targetType} enemies in range.`);
        break;
      }

      const target = enemies[0];
      console.log(`[#${companionId}] Target: ${target.name} at (${target.position.x}, ${target.position.y}), dist: ${target.distance}`);

      if (target.distance > ATTACK_RANGE) {
        await say(`Moving to ${target.name} (${Math.floor(target.distance)} tiles)...`);
        const arrived = await walkTo(target.position.x, target.position.y);
        if (!arrived) {
          console.log(`[#${companionId}] Failed to reach target`);
          continue;
        }
      }

      await say(`Attacking ${target.name}!`);
      const result = await attack(target.position.x, target.position.y);
      totalKills += result.kills;

      console.log(`[#${companionId}] Kills this round: ${result.kills}, total: ${totalKills}`);

      if (result.kills > 0) {
        await say(`Killed ${result.kills}! Total: ${totalKills}/${maxKills}`);
      }

      await sleep(500);
    }

    await say(`Combat done! ${totalKills} kills.`);
    console.log(`[#${companionId}] Combat complete. Total kills: ${totalKills}`);

  } catch (error) {
    console.error(`[#${companionId}] Error:`, error);
    try {
      await say(`Error: ${error}`);
    } catch {}
  } finally {
    await client.disconnect();
  }
}

main();
