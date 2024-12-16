mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"].auto(true)

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
local lend_drone_send, sync_drone_lend_data_send
local lend_drone = function(drone, target)
    drone.master = target
end
local lend_drone_handler = function(drone, target)
    if borrowed_drone_table[drone.id] then
        borrowed_drone_table[drone.id] = nil
    else
        borrowed_drone_table[drone.id] = true
    end
    lend_drone(drone, target)
end
local function sync_drone_lend_handler(cost, delay)
    params['delay'] = delay
    params['cost'] = cost
    Toml.save_cfg(_ENV["!guid"], params)
end
gm.post_script_hook(gm.constants.run_create, function(self, other, result, args)
    borrowed_drone_table = {}
    lend_drone_table = {}
    if Net.get_type() == Net.TYPE.host then
        sync_drone_lend_data_send(params['cost'], params['delay'])
    end
end)
gm.post_script_hook(gm.constants.run_destroy, function(self, other, result, args)
    for _, drone in pairs(lend_drone_table) do
        drone.stop()
    end
end)
gm.pre_code_execute("gml_Object_pDrone_CleanUp_0", function(self, other)
    if lend_drone_table[self.id] then
        lend_drone_table[self.id].stop()
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

local function init()
    local lend_drone_packet = Packet.new()
    lend_drone_packet:onReceived(function(message, player)
        local drone = message:read_instance().value
        local target = message:read_instance().value
        lend_drone_handler(drone, target)
        if Net.get_type() == Net.TYPE.host then
            local sync_message = lend_drone_packet:message_begin()
            sync_message:write_instance(drone)
            sync_message:write_instance(target)
            sync_message:send_exclude(player)
        end
    end)
    lend_drone_send = function(drone, target)
        local sync_message = lend_drone_packet:message_begin()
        sync_message:write_instance(drone)
        sync_message:write_instance(target)
        if Net.get_type() == Net.TYPE.host then
            sync_message:send_to_all()
        else
            sync_message:send_to_host()
        end
    end

    local sync_drone_lend_data_packet = Packet.new()
    sync_drone_lend_data_packet:onReceived(function(message, player)
        local cost = message:read_int()
        local delay = message:read_int()
        sync_drone_lend_handler(cost, delay)
    end)
    sync_drone_lend_data_send = function(cost, delay)
        local sync_message = sync_drone_lend_data_packet:message_begin()
        sync_message:write_int(cost)
        sync_message:write_int(delay)
        sync_message:send_to_all()
    end
end
gui.add_always_draw_imgui(function()
    if ImGui.IsKeyPressed(params['lend_drone_key'], false) then
        local player = Player.get_client().value
        if Instance.exists(player) then
            if get_select_player() ~= nil then
                local mouse_x = math.floor(gm.variable_global_get("mouse_x"))
                local mouse_y = math.floor(gm.variable_global_get("mouse_y"))
                local drone = gm.instance_nearest(mouse_x, mouse_y, EVariableType.ALL)
                if drone.object_index ~= gm.constants.oSniperDrone and drone.master ~= nil then
                    if borrowed_drone_table[drone.id] ~= true then
                        if type(drone.master) == "number" and drone.master or drone.master.m_id == player.m_id then
                            lend_drone(drone, get_select_player())
                            lend_drone_send(drone, get_select_player())
                            if drone.object_index ~= gm.constants.oSniperDrone then
                                lend_drone_table[drone.id] = {
                                    stop = create_lend(params['cost'], params['delay'], function()
                                        lend_drone(drone, player)
                                        lend_drone_send(drone, player)
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

Initialize(init)
