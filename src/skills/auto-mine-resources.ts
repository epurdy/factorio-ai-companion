// Skill: Auto Mine Resources
// Automatically finds and mines resources, returning to base when inventory is full

import { SkillContext, SkillResult, Position, exec } from "./index";

export interface AutoMineOptions {
  resourceType: "iron" | "copper" | "coal" | "stone" | "uranium";
  targetAmount: number;
  returnPosition?: Position;
  maxRadius?: number;
}

interface ResourceInfo {
  resource: string;
  position: Position;
  distance: number;
  amount?: number;
}

export async function autoMineResources(
  ctx: SkillContext,
  options: AutoMineOptions
): Promise<SkillResult> {
  const { resourceType, targetAmount, returnPosition, maxRadius = 100 } = options;
  const id = ctx.companionId;

  let totalMined = 0;
  const errors: string[] = [];
  const visited: Set<string> = new Set();

  // Get current position for return if not specified
  let homePos = returnPosition;
  if (!homePos) {
    try {
      const posData = await exec(ctx, `/fac_companion_position ${id}`);
      homePos = posData.position as Position;
    } catch (e) {
      errors.push(`Failed to get position: ${e}`);
      return { success: false, message: "Cannot determine home position", data: { errors } };
    }
  }

  while (totalMined < targetAmount) {
    // Find nearest resource of the type
    let resource: ResourceInfo | null = null;
    try {
      const nearest = await exec(ctx, `/fac_resource_nearest ${id} ${resourceType}`);
      if (nearest.error) {
        errors.push(`No ${resourceType} found: ${nearest.error}`);
        break;
      }
      resource = {
        resource: nearest.resource as string,
        position: nearest.position as Position,
        distance: nearest.distance as number,
        amount: nearest.amount as number | undefined,
      };
    } catch (e) {
      errors.push(`Failed to find ${resourceType}: ${e}`);
      break;
    }

    const posKey = `${resource.position.x},${resource.position.y}`;
    if (visited.has(posKey)) {
      // Already tried this spot, look for another
      errors.push(`Already visited (${resource.position.x}, ${resource.position.y}), stopping`);
      break;
    }
    visited.add(posKey);

    // Move to resource if needed
    if (resource.distance > 5) {
      try {
        await exec(ctx, `/fac_move_to ${id} ${resource.position.x} ${resource.position.y}`);
        // Wait for movement (simplified - in production would poll position)
        await sleep(Math.min(resource.distance * 100, 5000));
      } catch (e) {
        errors.push(`Failed to move to resource: ${e}`);
        continue;
      }
    }

    // Mine the resource
    const toMine = Math.min(targetAmount - totalMined, 10); // Mine in batches
    try {
      const mineResult = await exec(
        ctx,
        `/fac_resource_mine ${id} ${resource.position.x} ${resource.position.y} ${toMine}`
      );
      if (mineResult.mined) {
        const amount = (mineResult.amount as number) || 1;
        totalMined += amount;
      } else {
        errors.push(`Mining failed at (${resource.position.x}, ${resource.position.y})`);
      }
    } catch (e) {
      errors.push(`Failed to mine: ${e}`);
    }

    // Check inventory capacity
    try {
      const inv = await exec(ctx, `/fac_companion_inventory ${id}`);
      const usedSlots = inv.used_slots as number;
      const totalSlots = inv.total_slots as number;

      if (usedSlots >= totalSlots - 1) {
        // Only 1 slot left, return home
        if (homePos) {
          await exec(ctx, `/fac_move_to ${id} ${homePos.x} ${homePos.y}`);
          await sleep(3000); // Wait for return
        }
        break; // Stop mining, inventory full
      }
    } catch (e) {
      // Continue even if inventory check fails
    }
  }

  const success = totalMined > 0;
  const message = success
    ? `Mined ${totalMined} ${resourceType} (target: ${targetAmount})${errors.length ? `, ${errors.length} errors` : ""}`
    : `Failed to mine ${resourceType}: ${errors.join("; ")}`;

  return {
    success,
    message,
    data: {
      resourceType,
      mined: totalMined,
      target: targetAmount,
      errors,
      visitedSpots: visited.size,
    },
  };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
