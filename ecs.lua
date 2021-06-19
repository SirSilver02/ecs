local registered_components = {}
local registered_systems = {}

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
            system.entities[entity] = nil
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

function ecs.define_component(name, data)
    registered_components[name] = data
    data.__index = data

    return data
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

function ecs.load_systems(folder)
    for _, file_path in pairs(love.filesystem.getDirectoryItems(folder)) do
        local values = require(folder .. "/" .. file_path:sub(1, -5))
        local system_name = file_path:sub(1, -5)

        ecs.define_system(file_path:sub(1, -5), values.components, values.system)
    end
end

function ecs.load_components(folder)
    for _, file_path in pairs(love.filesystem.getDirectoryItems(folder)) do
        local component = require(folder .. "/" .. file_path:sub(1, -5))
        
        ecs.define_component(file_path:sub(1, -5), component)
    end
end

function ecs.add_event(event_name)
    ecs[event_name] = function(self, ...)
        self:call(event_name, ...)
    end
end

function ecs:add_entity()
    local entity = setmetatable({
        ecs = self,
        components = {}
    }, Entity)

    self.entities[entity] = entity

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