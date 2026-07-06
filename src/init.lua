-- Copyright (c) 2026 manshanko
-- SPDX-License-Identifier: MIT

local lua_loaders = {package.loaders[1]}
for i=2, 4 do
    lua_loaders = package.loaders[i]
    package.loaders[i] = package.loaded[i]
    package.loaded[i] = nil
end
package.loaded["scripts/main"] = nil
__PACKAGE_LOADERS = lua_loaders

-- based on `notify` in `9ba626afa44a3aa3.patch_999` from DML
local function notify(message)
    local event_manager = Managers and Managers.event

    if event_manager then
        local event = "event_add_notification_message"
        local chat_sound = "wwise/events/ui/play_ui_click"
        event_manager:trigger(event, "default", message, nil, chat_sound)
    end

    print(message)
end

local path = "mods/base/init.lua"
local fd, err = io.open("../mods/base/init.lua", "r")
if err then
    path = "binaries/mod_loader"
    fd, err = io.open("./mod_loader", "r")
end

if fd then
    _, err = pcall(function()
        local data = fd:read("*all")
        local func = loadstring(data, path)
        func()
    end)

    if err then
        notify("[DMA] Error running mod loader entry \"" .. path .. "\"")
    end

    fd:close()
else
    notify("[DMA] Error finding mod loader entry (\"binaries/mod_loader\" or \"mods/base/init.lua\")")

    require("scripts/main")
end
