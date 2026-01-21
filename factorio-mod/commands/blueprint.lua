-- AI Companion - Blueprint commands
local u = require("commands.init")

-- Import a blueprint string and place it at coordinates
-- Usage: /fac_blueprint_import <companionId> <x> <y> <direction> <blueprintString>
commands.add_command("fac_blueprint_import", nil, function(cmd)
  u.safe_command(function()
    -- Parse: companionId x y direction blueprintString
    -- Blueprint string can contain spaces in base64, so we parse carefully
    local args = u.parse_args("^(%S+)%s+([%d.-]+)%s+([%d.-]+)%s+(%d+)%s+(.+)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end

    local x, y = tonumber(args[2]), tonumber(args[3])
    local dir = tonumber(args[4]) or 0
    local bp_string = args[5]

    if not x or not y then u.error_response("Invalid coordinates"); return end
    if not bp_string or bp_string == "" then u.error_response("No blueprint string"); return end

    -- Check distance
    local dist = u.distance(c.entity.position, {x=x, y=y})
    if dist > 100 then
      u.json_response({id = id, error = "Too far", distance = dist}); return
    end

    -- Create a temporary blueprint item
    local inv = c.entity.get_inventory(defines.inventory.character_main)
    local slot = inv.find_empty_stack()
    if not slot then u.json_response({id = id, error = "Inventory full"}); return end

    slot.set_stack({name = "blueprint"})

    -- Import the blueprint string
    local result = slot.import_stack(bp_string)
    if result == 1 then
      slot.clear()
      u.json_response({id = id, error = "Failed to import blueprint string"}); return
    end

    -- Check if blueprint has contents
    if not slot.is_blueprint_setup() then
      slot.clear()
      u.json_response({id = id, error = "Blueprint is empty after import"}); return
    end

    -- Get blueprint info before building
    local bp_entities = slot.get_blueprint_entities() or {}
    local bp_tiles = slot.get_blueprint_tiles() or {}

    -- Build the blueprint
    local direction_map = {
      [0] = defines.direction.north,
      [1] = defines.direction.northeast,
      [2] = defines.direction.east,
      [3] = defines.direction.southeast,
      [4] = defines.direction.south,
      [5] = defines.direction.southwest,
      [6] = defines.direction.west,
      [7] = defines.direction.northwest
    }

    local ghosts = slot.build_blueprint{
      surface = c.entity.surface,
      force = c.entity.force,
      position = {x = x, y = y},
      direction = direction_map[dir] or defines.direction.north,
      raise_built = true
    }

    -- Clean up the temporary blueprint
    slot.clear()

    -- Count what was placed
    local ghost_count = ghosts and #ghosts or 0

    u.json_response({
      id = id,
      success = true,
      ghosts_placed = ghost_count,
      entities_in_blueprint = #bp_entities,
      tiles_in_blueprint = #bp_tiles,
      position = {x = x, y = y}
    })
  end)
end)

-- Export an area to a blueprint string
-- Usage: /fac_blueprint_export <companionId> <x1> <y1> <x2> <y2>
commands.add_command("fac_blueprint_export", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+([%d.-]+)%s+([%d.-]+)%s+([%d.-]+)%s+([%d.-]+)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end

    local x1, y1 = tonumber(args[2]), tonumber(args[3])
    local x2, y2 = tonumber(args[4]), tonumber(args[5])

    if not x1 or not y1 or not x2 or not y2 then
      u.error_response("Invalid coordinates"); return
    end

    -- Ensure proper order (min to max)
    local left = math.min(x1, x2)
    local top = math.min(y1, y2)
    local right = math.max(x1, x2)
    local bottom = math.max(y1, y2)

    -- Create a temporary blueprint item
    local inv = c.entity.get_inventory(defines.inventory.character_main)
    local slot = inv.find_empty_stack()
    if not slot then u.json_response({id = id, error = "Inventory full"}); return end

    slot.set_stack({name = "blueprint"})

    -- Capture the area
    local entity_map = slot.create_blueprint{
      surface = c.entity.surface,
      force = c.entity.force,
      area = {{left, top}, {right, bottom}},
      always_include_tiles = true,
      include_entities = true,
      include_modules = true,
      include_station_names = true,
      include_trains = true,
      include_fuel = false
    }

    -- Check if anything was captured
    if not slot.is_blueprint_setup() then
      slot.clear()
      u.json_response({id = id, error = "No entities found in area", area = {left=left, top=top, right=right, bottom=bottom}}); return
    end

    -- Export to string
    local bp_string = slot.export_stack()

    -- Get counts
    local bp_entities = slot.get_blueprint_entities() or {}
    local bp_tiles = slot.get_blueprint_tiles() or {}

    -- Clean up
    slot.clear()

    u.json_response({
      id = id,
      success = true,
      blueprint = bp_string,
      entity_count = #bp_entities,
      tile_count = #bp_tiles,
      area = {left = left, top = top, right = right, bottom = bottom}
    })
  end)
end)

-- Get info about a blueprint string without placing it
-- Usage: /fac_blueprint_info <companionId> <blueprintString>
commands.add_command("fac_blueprint_info", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(.+)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end

    local bp_string = args[2]
    if not bp_string or bp_string == "" then u.error_response("No blueprint string"); return end

    -- Create a temporary blueprint item
    local inv = c.entity.get_inventory(defines.inventory.character_main)
    local slot = inv.find_empty_stack()
    if not slot then u.json_response({id = id, error = "Inventory full"}); return end

    slot.set_stack({name = "blueprint"})

    -- Import the blueprint string
    local result = slot.import_stack(bp_string)
    if result == 1 then
      slot.clear()
      u.json_response({id = id, error = "Failed to import blueprint string"}); return
    end

    -- Get blueprint info
    local label = slot.label or "Unnamed"
    local bp_entities = slot.get_blueprint_entities() or {}
    local bp_tiles = slot.get_blueprint_tiles() or {}

    -- Count entity types
    local entity_counts = {}
    for _, ent in ipairs(bp_entities) do
      local name = ent.name
      entity_counts[name] = (entity_counts[name] or 0) + 1
    end

    -- Calculate bounding box
    local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge, -math.huge
    for _, ent in ipairs(bp_entities) do
      if ent.position then
        min_x = math.min(min_x, ent.position.x)
        min_y = math.min(min_y, ent.position.y)
        max_x = math.max(max_x, ent.position.x)
        max_y = math.max(max_y, ent.position.y)
      end
    end

    -- Clean up
    slot.clear()

    u.json_response({
      id = id,
      success = true,
      label = label,
      entity_count = #bp_entities,
      tile_count = #bp_tiles,
      entity_types = entity_counts,
      bounding_box = {
        min_x = min_x ~= math.huge and min_x or 0,
        min_y = min_y ~= math.huge and min_y or 0,
        max_x = max_x ~= -math.huge and max_x or 0,
        max_y = max_y ~= -math.huge and max_y or 0
      }
    })
  end)
end)
