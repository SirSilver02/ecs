local registered_components = {}
local registered_systems = {}
local registered_prefabs = {}

--ENTITY

local Entity = {}
Entity.__index = Entity

function Entity:add_component(name, ...)
    assert(registered_components[name], ("\"%s\" not a valid component."):format(name))
    if self.components[name] then return end

    local component = setmetatable({}, registered_components[name])

    if component.init then
        component:init(...)
    end

    self.components[name] = component

    --add entity to systems that its not already a part of where the entity has all of the necessary components to join that system
    for system_name, system in pairs(self.ecs.systems) do
        if not system.entities[self] then
            local add_to_system = true

            for required_component in pairs(system.components) do
                if not self.components[required_component] then
                    add_to_system = false
                    break
                end
            end

            if add_to_system then
                system.entities[self] = self
            end
        end
    end

    return component
end

function Entity:remove_component(name)
    if not self.components[name] then return end

    self.components[name] = nil

    --remove entity from systems that require the removed component if the entity exists in that system
    for system_name, system in pairs(self.ecs.systems) do
        if system.components[name] and system.entities[self] then
            system.entities[self] = nil
        end
    end
end

--ECS

local ecs = {}

ecs.__index = ecs

function ecs.new()
    return setmetatable({
        entities = {},
        systems = {},
        ordered_systems = {},
        uninstalled_events = {}
    }, ecs)
end

function ecs.define_prefab(name, prefab)
    registered_prefabs[name] = setmetatable(prefab, Entity)
    prefab.__index = prefab

    return prefab
end

function ecs.define_component(name, component)
    registered_components[name] = component
    component.__index = component

    return component
end

function ecs.define_system(name, components, system)
    system.__index = system

    system.components = {}

    for _, name in pairs(components) do
        system.components[name] = true
    end

    registered_systems[name] = system
    
    return system
end

local file_name_pattern = "([%w_]+)%." --capture the file's name without extension. (Use with string:match())

local function recursive_load(folder, load_func)
    for _, file_or_folder_name in pairs(love.filesystem.getDirectoryItems(folder)) do
        local path = folder .. "/" .. file_or_folder_name
        local info = love.filesystem.getInfo(path)

        if info.type == "directory" then
            recursive_load(path)
        elseif info.type == "file" then
            if not (file_or_folder_name == "init.lua") then
                load_func(path)
            end
        end
    end
end

function ecs.load_systems(folder)
    recursive_load(folder, function(path)
        local system = require(path:sub(1, -5))
        local system_name = path:match(file_name_pattern)

        ecs.define_system(system_name, system.components, system.system)
    end)
end

function ecs.load_components(folder)
    recursive_load(folder, function(path)
        local component = require(path:sub(1, -5))
        local component_name = path:match(file_name_pattern)
    
        ecs.define_component(component_name, component)
    end)
end

function ecs.load_prefabs(folder)
    recursive_load(folder, function(path)
        local prefab = require(path:sub(1, -5))
        local prefab_name = path:match(file_name_pattern)

        ecs.define_prefab(prefab_name, prefab)
    end)
end

function ecs.add_event(event_name)
    ecs[event_name] = function(self, ...)
        self:call(event_name, ...)
    end
end

function ecs:add_entity(prefab_name)
    local entity = prefab_name and
    setmetatable({}, registered_prefabs[prefab_name]) or 
    setmetatable({}, Entity)

    entity.ecs = self
    entity.components = {}

    self.entities[entity] = entity

    if entity.init then
        entity:init()
    end

    --entities start with no components, no need to add to systems yet

    return entity
end

function ecs:remove_entity(entity)
    self.entities[entity] = nil

    for system_name, system in pairs(self.systems) do
        sytem.entities[entity] = nil
    end
end

function ecs:add_system(name, ...)
    assert(registered_systems[name], ("add_system(\"%s\"), system not defined."):format(name))

    if self.systems[name] then return end
    if not registered_systems[name] then return end

    local system = setmetatable({
        ecs = self,
        entities = {}
    }, registered_systems[name])

    if system.init then
        system:init(...)
    end

    self.systems[name] = system
    table.insert(self.ordered_systems, system)

    --add all entities with necessary components to the system
    for entity in pairs(self.entities) do
        if not system.entities[entity] then
            local add_to_system = true

            for required_component in pairs(system.components) do
                if not entity.components[required_component] then
                    add_to_system = false
                    break
                end
            end

            if add_to_system then
                system.entities[entity] = entity
            end
        end
    end

    return system
end

function ecs:remove_system(name)
    if not self.systems[name] then return end
    
    for i = #self.ordered_systems, 1 do
        local system = self.ordered_systems[i]
        
        if system == self.systems[name] then
            table.remove(self.ordered_systems, i)
            break
        end
    end

    self.systems[name] = nil
end

function ecs:call(event_name, ...)
    for i = 1, #self.ordered_systems do
        local system = self.ordered_systems[i]
        local func = system[event_name]
        
        if func then
            func(system, ...)
        end
    end
end

local events = {update = true, draw = true}

for event_name in pairs(love.handlers) do
    events[event_name] = true
end

for event_name in pairs(events) do
    ecs.add_event(event_name)
end

function ecs:install(table)
    for event in pairs(events) do
        local old_event = table[event]

        table[event] = function(...)
            local _, a, b, c, d, e, f, g = ...
            local ra, rb, rc, rd, re

            if old_event then
                ra, rb, rc, rd, re = old_event(...)
            end

            if self[event] and not self.uninstalled_events[event] then
                if type(_) == "table" then
                    self[event](self, a, b, c, d, e, f, g)
                else
                    self[event](self, ...)
                end
            end

            return ra, rb, rc, rd, re
        end
    end
end

function ecs:uninstall_event(event)
    self.uninstalled_events[event] = true
end

return ecs