# FLE Integration Plan - AI Companion v0.8.0

## Overview

Integrar las mejores prácticas de Factorio Learning Environment (FLE) en nuestro sistema de companions para:
1. Gestión de contexto sin compactación constante
2. Reducción de ruido en respuestas de agentes
3. Migración de comandos tick-based realistas
4. Sistema de combate/defensa (que FLE no tiene)

---

## 1. GESTIÓN DE CONTEXTO

### Problema Actual
Los subagentes llenan su contexto rápidamente y Claude compacta automáticamente, perdiendo información importante.

### Solución FLE
FLE usa `RecursiveReportFormatter` con:
- Chunks de 16 mensajes → resumen LLM
- Cache SHA256 de resúmenes
- Inyección en system message (no en historial)
- Límite duro de 200KB

### Implementación Propuesta

#### A. Resumen Periódico en Subagentes
Cada companion mantiene un "estado mental" resumido:

```
## MI ESTADO ACTUAL (Companion #N)
- Posición: (x, y)
- Inventario: iron-ore: 50, coal: 20
- Última tarea: Minando cobre
- Errores recientes: Ninguno
- Siguiendo a: lveillard
```

Este estado se actualiza cada 5-10 interacciones y se pone al inicio del prompt.

#### B. No Acumular Historial Completo
En vez de guardar toda la conversación:
- Guardar solo últimos 3 mensajes completos
- Resto → resumen comprimido
- El subagente recibe: `[System + Estado] + [Resumen histórico] + [Últimos 3 mensajes]`

#### C. Implementación en TypeScript
Crear `src/context/companion-memory.ts`:
```typescript
interface CompanionMemory {
  id: number;
  currentState: {
    position: {x: number, y: number};
    inventory: Record<string, number>;
    currentTask: string;
    following: string | null;
    health: number;
  };
  recentErrors: string[];
  historicalSummary: string;
  lastMessages: Message[];  // Max 3
}
```

---

## 2. REDUCCIÓN DE RUIDO

### Problema Actual
Los subagentes:
- Inventan mecanismos de polling (`sleep && cat`)
- Escriben respuestas largas innecesarias
- No siguen el formato exacto

### Solución FLE
- Límite de 50 líneas de código por policy
- Formato estricto: PLANNING → POLICY
- Campos de observación selectivos

### Implementación Propuesta

#### A. Prompt Más Restrictivo
Actualizar template con:
```
## FORMATO DE RESPUESTA (OBLIGATORIO)

1. PENSAMIENTO (1-2 líneas): Qué entendí y qué voy a hacer
2. ACCIÓN: Ejecutar comandos RCON
3. RESPUESTA (máx 20 palabras): Lo que digo al jugador

## PROHIBIDO
- Respuestas de más de 50 palabras
- Explicaciones largas
- Inventar comandos
- Usar sleep, cat, o leer archivos directamente
```

#### B. Observaciones Selectivas
En vez de pasar todo el output de comandos, filtrar:
```typescript
function formatObservation(raw: any): string {
  // Solo campos relevantes
  return JSON.stringify({
    position: raw.position,
    nearbyEntities: raw.entities?.slice(0, 10),  // Max 10
    inventory: summarizeInventory(raw.inventory),
    errors: raw.error
  });
}
```

#### C. Validación de Respuestas
Antes de enviar al chat, validar:
- Longitud < 100 caracteres
- No contiene código
- Es respuesta directa

---

## 3. COMANDOS TICK-BASED REALISTAS

### Lo que tiene FLE
| Acción | Ticks | Implementación |
|--------|-------|----------------|
| Mining | 30 ticks (~0.5s) | `harvest_queues` + `on_nth_tick(15)` |
| Walking | Variable | `walking_queues` + `on_nth_tick(5)` |
| Crafting | recipe.energy * 60 | Acumulación de ticks |
| Building | 60 ticks (1s) | Validación + placement |

### Lo que tenemos
- ✅ Walking queue (ya implementado)
- ✅ Mining queue (recién implementado, no probado)
- ❌ Crafting realista
- ❌ Building realista

### Implementación Propuesta

#### A. Actualizar `queues.lua` con más colas

```lua
-- queues.lua expandido
local M = {}

function M.init()
  storage.harvest_queues = storage.harvest_queues or {}
  storage.craft_queues = storage.craft_queues or {}
  storage.build_queues = storage.build_queues or {}
  storage.combat_queues = storage.combat_queues or {}
end

-- Crafting queue
function M.start_craft(companion_id, recipe, count)
  local c = u.get_companion(companion_id)
  local recipe_proto = game.recipe_prototypes[recipe]
  if not recipe_proto then return {error = "Unknown recipe"} end

  local ticks_per_craft = (recipe_proto.energy or 0.5) * 60

  storage.craft_queues[companion_id] = {
    recipe = recipe,
    target = count,
    crafted = 0,
    ticks_per_item = ticks_per_craft,
    current_start_tick = game.tick
  }

  return {started = true, recipe = recipe, target = count}
end

function M.tick_craft_queues()
  for cid, q in pairs(storage.craft_queues) do
    local c = u.get_companion(cid)
    if not c then storage.craft_queues[cid] = nil; goto continue end

    local elapsed = game.tick - q.current_start_tick
    if elapsed >= q.ticks_per_item then
      -- Intentar craftear 1
      local crafted = c.entity.begin_crafting{recipe = q.recipe, count = 1}
      if crafted > 0 then
        q.crafted = q.crafted + 1
        q.current_start_tick = game.tick
      end

      if q.crafted >= q.target then
        storage.craft_queues[cid] = nil
      end
    end
    ::continue::
  end
end
```

#### B. Building Queue

```lua
function M.start_build(companion_id, entity, position, direction)
  local c = u.get_companion(companion_id)
  if u.distance(c.entity.position, position) > c.entity.build_distance then
    return {error = "Too far"}
  end

  -- Verificar que tiene el item
  local inv = c.entity.get_main_inventory()
  if inv.get_item_count(entity) < 1 then
    return {error = "No tienes " .. entity}
  end

  -- Verificar que se puede colocar
  if not c.entity.surface.can_place_entity{name = entity, position = position, direction = direction} then
    return {error = "No se puede colocar ahí"}
  end

  storage.build_queues[companion_id] = {
    entity = entity,
    position = position,
    direction = direction or defines.direction.north,
    start_tick = game.tick,
    build_time = 60  -- 1 segundo
  }

  return {started = true, entity = entity, position = position}
end

function M.tick_build_queues()
  for cid, q in pairs(storage.build_queues) do
    local c = u.get_companion(cid)
    if not c then storage.build_queues[cid] = nil; goto continue end

    local elapsed = game.tick - q.start_tick
    if elapsed >= q.build_time then
      -- Colocar edificio
      local placed = c.entity.surface.create_entity{
        name = q.entity,
        position = q.position,
        direction = q.direction,
        force = c.entity.force
      }

      if placed then
        c.entity.remove_item{name = q.entity, count = 1}
      end

      storage.build_queues[cid] = nil
    end
    ::continue::
  end
end
```

---

## 4. SISTEMA DE COMBATE/DEFENSA

### Lo que NO tiene FLE
FLE desactiva enemigos completamente. Nosotros queremos:
- Detectar enemigos cercanos
- Atacar biters/spitters
- Defenderse automáticamente
- Huir si es necesario

### Implementación Propuesta

#### A. Detección de Enemigos
Actualizar `world.lua` scan para incluir enemigos explícitamente:

```lua
commands.add_command("fac_world_enemies", nil, function(cmd)
  local args = u.parse_args("^(%S+)%s*(%d*)$", cmd.parameter)
  local id, c = u.find_companion(args[1])
  local radius = tonumber(args[2]) or 30

  local enemies = c.entity.surface.find_entities_filtered{
    position = c.entity.position,
    radius = radius,
    force = "enemy",
    type = {"unit", "unit-spawner", "turret"}
  }

  local result = {}
  for _, e in ipairs(enemies) do
    result[#result + 1] = {
      name = e.name,
      type = e.type,
      position = {x = math.floor(e.position.x), y = math.floor(e.position.y)},
      health = e.health,
      distance = math.floor(u.distance(c.entity.position, e.position))
    }
  end

  table.sort(result, function(a, b) return a.distance < b.distance end)
  u.json_response({id = id, enemies = result, count = #result, threat_level = #result > 0 and "danger" or "safe"})
end)
```

#### B. Combat Queue

```lua
function M.start_combat(companion_id, target_position)
  local c = u.get_companion(companion_id)

  -- Encontrar enemigo más cercano a target_position
  local enemies = c.entity.surface.find_entities_filtered{
    position = target_position,
    radius = 5,
    force = "enemy"
  }

  if #enemies == 0 then return {error = "No enemies"} end

  storage.combat_queues[companion_id] = {
    targets = enemies,
    current_target = enemies[1],
    attack_cooldown = 0
  }

  return {started = true, targets = #enemies}
end

function M.tick_combat_queues()
  for cid, q in pairs(storage.combat_queues) do
    local c = u.get_companion(cid)
    if not c then storage.combat_queues[cid] = nil; goto continue end

    -- Cooldown entre ataques
    if q.attack_cooldown > 0 then
      q.attack_cooldown = q.attack_cooldown - 5
      goto continue
    end

    -- Verificar target válido
    if not q.current_target or not q.current_target.valid then
      table.remove(q.targets, 1)
      if #q.targets == 0 then
        storage.combat_queues[cid] = nil
        goto continue
      end
      q.current_target = q.targets[1]
    end

    -- Atacar
    local dist = u.distance(c.entity.position, q.current_target.position)
    if dist <= 6 then  -- Rango de ataque
      -- Usar shooting_state
      c.entity.shooting_state = {
        state = defines.shooting.shooting_enemies,
        position = q.current_target.position
      }
      q.attack_cooldown = 30  -- 0.5s entre ataques
    else
      -- Moverse hacia el enemigo
      c.entity.walking_state = {
        walking = true,
        direction = u.get_direction(c.entity.position, q.current_target.position)
      }
    end

    ::continue::
  end
end
```

#### C. Auto-Defensa
En `control.lua`, añadir detección pasiva:

```lua
script.on_nth_tick(60, function(ev)  -- Cada segundo
  for cid, c in pairs(storage.companions) do
    if not c.entity or not c.entity.valid then goto skip end

    -- Buscar enemigos cercanos
    local nearby = c.entity.surface.find_entities_filtered{
      position = c.entity.position,
      radius = 15,
      force = "enemy",
      type = "unit"
    }

    if #nearby > 0 and not storage.combat_queues[cid] then
      -- Auto-defenderse si no está ya en combate
      if c.auto_defend then
        queues.start_combat(cid, nearby[1].position)
      end
    end

    ::skip::
  end
end)
```

---

## 5. ARCHIVOS A CREAR/MODIFICAR

### Nuevos Archivos
- `src/context/companion-memory.ts` - Gestión de memoria de companions
- `factorio-mod/commands/combat.lua` - Comandos de combate

### Archivos a Modificar
- `factorio-mod/commands/queues.lua` - Añadir craft, build, combat queues
- `factorio-mod/commands/world.lua` - Añadir fac_world_enemies
- `factorio-mod/control.lua` - Añadir tick handlers para nuevas colas
- `CLAUDE.md` - Actualizar template con formato restrictivo
- `factorio-mod/info.json` - Bump a v0.8.0

---

## 6. ORDEN DE IMPLEMENTACIÓN

### Fase 1: Comandos Tick-Based (Prioridad Alta)
1. Expandir `queues.lua` con craft_queues, build_queues
2. Añadir comandos `fac_item_craft_start`, `fac_item_craft_status`
3. Añadir comandos `fac_building_place_start`, `fac_building_place_status`
4. Testear mining existente

### Fase 2: Sistema de Combate (Prioridad Alta)
1. Crear `combat.lua` con combat_queues
2. Añadir `fac_world_enemies`
3. Añadir `fac_action_attack_start`, `fac_action_defend`
4. Implementar auto-defensa pasiva

### Fase 3: Reducción de Ruido (Prioridad Media)
1. Actualizar template en CLAUDE.md con formato restrictivo
2. Añadir validación de longitud de respuestas
3. Filtrar observaciones en reactive-companion.ts

### Fase 4: Gestión de Contexto (Prioridad Media)
1. Crear `companion-memory.ts`
2. Implementar resumen periódico
3. Integrar con subagentes

---

## 7. COMANDOS NUEVOS PROPUESTOS

| Comando | Descripción |
|---------|-------------|
| `fac_world_enemies N [radius]` | Lista enemigos cercanos |
| `fac_action_attack_start N x y` | Iniciar combate en posición |
| `fac_action_attack_status N` | Estado del combate |
| `fac_action_attack_stop N` | Detener combate |
| `fac_action_defend N on/off` | Activar/desactivar auto-defensa |
| `fac_item_craft_start N recipe count` | Crafteo realista |
| `fac_item_craft_status N` | Estado del crafteo |
| `fac_building_place_start N entity x y [dir]` | Construcción realista |
| `fac_building_place_status N` | Estado de construcción |

---

## 8. MÉTRICAS DE ÉXITO

- [ ] Mining realista funciona (se ve animación, tarda tiempo)
- [ ] Companions detectan y atacan biters
- [ ] Companions se defienden automáticamente
- [ ] Subagentes responden en <5 segundos
- [ ] Subagentes no usan `sleep && cat`
- [ ] Contexto no se compacta en primeros 20 mensajes
- [ ] Respuestas de chat <100 caracteres
