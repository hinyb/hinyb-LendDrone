mods.on_all_mods_loaded(function()
    for _, m in pairs(mods) do
        if type(m) == "table" and m.RoRR_Modding_Toolkit then
            for _, c in ipairs(m.Classes) do
                if m[c] then
                    _G[c] = m[c]
                end
            end
        end
    end
end)

mods.on_all_mods_loaded(function()
    for k, v in pairs(mods) do
        if type(v) == "table" and v.tomlfuncs then
            Toml = v
        end
    end
    params = {
        lend_drone_key = 522,
        stop_lend_key = 512,
        delay = 6,
        cost = 4
    }
    params = Toml.config_update(_ENV["!guid"], params)
end)

mods.on_all_mods_loaded(function()
    for _, v in pairs(mods) do
        if type(v) == "table" and v.MPselector then
            _G["get_select_player"] = v["get_select_player"]
        end
    end
end)

local lend_drone_table = {}
local borrowed_drone_table = {}
local return_table = {}
local function get_instance_with_m_id(id, m_id)
    for k, v in pairs(Instance.find_all(id)) do
        if v.value.m_id == m_id then
            return v
        end
    end
end

local function check_drone_status(drone_m_id, drone_id)
    if borrowed_drone_table[drone_id] == nil then
        borrowed_drone_table[drone_id] = {}
    end
    local num = 0
    for index, m_id in pairs(borrowed_drone_table[drone_id]) do
        num = num + 1
        if m_id == drone_m_id then
            return index
        end
    end
    return nil
end
local lend_drone = function(drone, target, stop_record_flag)
    if stop_record_flag ~= true then
        table.insert(return_table, {
            object_index = drone.object_index,
            m_id = drone.m_id,
            origin_master = gm.variable_instance_get(drone.id, "master")
        })
    end
    gm.variable_instance_set(drone.id, "master", target.id) -- May break some mod, but i can't find a better way to deal with it. I think there maybe some closure issue here, but I'm not a Lua expert.
end
local lend_drone_handler = function(drone_m_id, target_m_id, drone_id, stop_record_flag)
    if stop_record_flag ~= true then
        local status = check_drone_status(drone_m_id, drone_id)
        if status then
            table.remove(borrowed_drone_table[drone_id], status)
        else
            table.insert(borrowed_drone_table[drone_id], drone_m_id)
        end
    end
    lend_drone(get_instance_with_m_id(drone_id, drone_m_id).value,
        get_instance_with_m_id(gm.constants.oP, target_m_id).value, stop_record_flag)
end
local function sync_drone_lend_handler(cost, delay)
    params['delay'] = delay
    params['cost'] = cost
    Toml.save_cfg(_ENV["!guid"], params)
end

gm.post_script_hook(gm.constants.run_create, function(self, other, result, args)
    borrowed_drone_table = {}
    if gm.variable_global_get("host") == true then
        Net.send("sync_drone_lend_handler", Net.TARGET.all, nil, params['cost'], params['delay'])
    end
end)
gm.post_script_hook(gm.constants.run_destroy, function(self, other, result, args)
    for _, drone in pairs(lend_drone_table) do
        drone.stop()
    end
end)
gm.pre_code_execute("gml_Object_pDrone_CleanUp_0", function(self, other)
    for _, drone in pairs(return_table) do
        if self.object_index == drone.object_index then
            if self.m_id == drone.m_id then
                gm.variable_instance_set(self.id, "master", drone.origin_master.id)
                drone.stop()
            end
        end
    end
end)
local function create_lend(cost, delay, onStop, onEmpty, costFunc)
    local lend_flag = true
    local function stop_lend()
        if onStop then
            onStop()
        end
        lend_flag = false
    end
    local function default_costFunc(ohud, ...)
        if ohud.display_gold >= cost and ohud.gold >= cost then
            ohud.display_gold = ohud.display_gold - cost
            ohud.gold = ohud.gold - cost
            return true
        else
            return false
        end
    end
    local cost_money = costFunc or default_costFunc
    local function pay_lend()
        if lend_flag then
            local ohud = Instance.find_all(gm.constants.oHUD)[1]
            if not cost_money(ohud, cost) then
                if onEmpty then
                    if not onEmpty() then
                        stop_lend()
                    end
                end
            end
            Alarm.create(pay_lend, delay * 60)
        end
    end
    pay_lend()
    return stop_lend
end
gui.add_always_draw_imgui(function()
    Net.register("lend_drone_handler", lend_drone_handler)
    Net.register("sync_drone_lend_handler", sync_drone_lend_handler)
    if ImGui.IsKeyPressed(params['lend_drone_key'], false) then
        local player = Player.get_client()
        if Instance.exists(player) then
            if get_select_player() ~= nil then
                local mouse_x = math.floor(gm.variable_global_get("mouse_x"))
                local mouse_y = math.floor(gm.variable_global_get("mouse_y"))
                local drone = gm.instance_nearest(mouse_x, mouse_y, EVariableType.ALL)
                local drone_master = gm.variable_instance_get(drone.id, "master")
                log.info("drone_master.." .. type(drone_master))
                if (drone_master ~= nil) then
                    if check_drone_status(drone.m_id, drone.object_index) == nil then
                        if gm.variable_instance_get(type(drone_master) == "number" and drone_master or drone_master.id,
                            "m_id") == player.value.m_id then
                            local isSniperDrone = drone.object_index == gm.constants.oSniperDrone
                            lend_drone(drone, get_select_player(), isSniperDrone)
                            Net.send("lend_drone_handler", Net.TARGET.all, nil, drone.m_id, get_select_player().m_id,
                                drone.object_index, isSniperDrone)
                            if not isSniperDrone then
                                lend_drone_table[drone.id] = {
                                    object_index = drone.object_index,
                                    m_id = drone.m_id,
                                    origin_master = player.value,
                                    stop = create_lend(params['cost'], params['delay'], function()
                                        lend_drone(drone, player.value)
                                        Net.send("lend_drone_handler", Net.TARGET.all, nil, drone.m_id,
                                            player.value.m_id, drone.object_index)
                                        lend_drone_table[drone.id] = nil
                                    end, function()
                                        return false
                                    end)
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    if ImGui.IsKeyPressed(params['stop_lend_key'], false) then
        local drone
        _, drone = next(lend_drone_table)
        if drone ~= nil then
            drone.stop()
        end
    end
end)

gui.add_to_menu_bar(function()
    local isChanged, keybind_value = ImGui.Hotkey("Lend Drone Key", params['lend_drone_key'])
    if isChanged then
        params['lend_drone_key'] = keybind_value
        Toml.save_cfg(_ENV["!guid"], params)
    end
end)
gui.add_to_menu_bar(function()
    local isChanged, keybind_value = ImGui.Hotkey("Stop Lend Drone Key", params['stop_lend_key'])
    if isChanged then
        params['stop_lend_key'] = keybind_value
        Toml.save_cfg(_ENV["!guid"], params)
    end
end)
gui.add_to_menu_bar(function()
    local value, used = ImGui.InputInt("Lend cost value", params['cost'])
    if used then
        params['cost'] = value
        Toml.save_cfg(_ENV["!guid"], params)
    end
end)
gui.add_to_menu_bar(function()
    local value, used = ImGui.InputInt("Lend cost delay", params['delay'])
    if used then
        params['delay'] = value
        Toml.save_cfg(_ENV["!guid"], params)
    end
end)
