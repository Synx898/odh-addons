-- Skidded by @sl1yyy/Synx

local shared = odh_shared_plugins

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local userWantsEnabled = false
local enabled = false
local velocityConnection = nil
local hadKnifeLastFrame = false

local ignoreListEnabled = true
local slot1Player = nil
local slot2Player = nil
local slot3Player = nil

local velocityIntensity = 320
local spinEnabled = false
local multiSpikeEnabled = true
local isMurderer = false

-- MM2 shows Weapon.Murderer frame when role is assigned — watch that instead of Team (Team is nil in lobby)
task.spawn(function()
    local pg = LocalPlayer:WaitForChild("PlayerGui")
    local mainGui = pg:WaitForChild("MainGUI", 30)
    if not mainGui then return end
    local murdererFrame = mainGui:WaitForChild("Game", 10) and mainGui.Game:WaitForChild("Weapon", 10) and mainGui.Game.Weapon:WaitForChild("Murderer", 10)
    if not murdererFrame then return end
    isMurderer = murdererFrame.Visible
    murdererFrame:GetPropertyChangedSignal("Visible"):Connect(function()
        isMurderer = murdererFrame.Visible
    end)
end)


-- some knife games rename the tool so just check common names
local knifeTags = {"knife", "blade", "melee", "dagger", "shiv"}

local function isKnifeTool(tool)
    local n = tool.Name:lower()
    for _, tag in ipairs(knifeTags) do
        if n:find(tag) then return true end
    end
    return false
end

local function hasKnife()
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local character = LocalPlayer.Character
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and isKnifeTool(item) then return true end
        end
    end
    if character then
        for _, item in ipairs(character:GetChildren()) do
            if item:IsA("Tool") and isKnifeTool(item) then return true end
        end
    end
    return false
end

local function isPlayerNearby(hrp)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local otherHrp = player.Character.HumanoidRootPart
            -- 18 studs: AA cuts off at real chase range, not just melee
            if (otherHrp.Position - hrp.Position).Magnitude <= 18 then
                return true
            end
        end
    end
    return false
end

local function isInWater(humanoid)
    local state = humanoid:GetState()
    return state == Enum.HumanoidStateType.Swimming or humanoid.FloorMaterial == Enum.Material.Water
end

-- ignore list should only care about actual weapons, not cosmetics
local cosmeticTags = {"hat", "accessory", "gear", "badge", "trail"}

local function isCombatTool(tool)
    local n = tool.Name:lower()
    for _, tag in ipairs(cosmeticTags) do
        if n:find(tag) then return false end
    end
    return true
end

local function isIgnoredPlayerArmed()
    if not ignoreListEnabled then return false end
    local targets = {slot1Player, slot2Player}
    for _, player in ipairs(targets) do
        if player and player.Parent then
            local backpack = player:FindFirstChild("Backpack")
            local character = player.Character
            if backpack then
                for _, item in ipairs(backpack:GetChildren()) do
                    if item:IsA("Tool") and isCombatTool(item) then return true end
                end
            end
            if character then
                for _, item in ipairs(character:GetChildren()) do
                    if item:IsA("Tool") and isCombatTool(item) then return true end
                end
            end
        end
    end
    return false
end

-- Anti-Aim

local function rsign()
    return math.random(0, 1) == 0 and 1 or -1
end

-- x and z are independent so you get 4 real directions, not just the 2 diagonals
local function makeSpike(baseY)
    local x = velocityIntensity * rsign() + math.random(-40, 40)
    local z = velocityIntensity * rsign() + math.random(-40, 40)
    return Vector3.new(x, baseY, z)
end

local function doRollStep(humanoid)
    task.spawn(function()
        local dir = Vector3.new(rsign(), 0, rsign()).Unit
        local t = tick()
        while tick() - t < 0.15 do
            if humanoid and humanoid.Parent then
                humanoid:Move(dir, false)
            end
            RunService.RenderStepped:Wait()
        end
    end)
end

local desyncRunning = false

local function applyDesync(hrp, humanoid)
    if desyncRunning then return end
    desyncRunning = true

    local oldVel = hrp.AssemblyLinearVelocity
    local oldCF = hrp.CFrame
    local state = humanoid:GetState()
    local jumping = state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall
    local stopped = humanoid.MoveDirection.Magnitude == 0

    local mag = stopped and (velocityIntensity * 1.25) or velocityIntensity
    local baseY = jumping and (mag * rsign() * 0.78) or 0

    hrp.AssemblyLinearVelocity = makeSpike(baseY)

    if spinEnabled then
        local ang = math.rad(math.random(60, 150)) * rsign()
        hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, ang, 0)
    end

    if multiSpikeEnabled then
        RunService.RenderStepped:Wait()
        hrp.AssemblyLinearVelocity = Vector3.new(
            -oldVel.X + math.random(-25, 25),
            baseY,
            -oldVel.Z + math.random(-25, 25)
        )
    end

    RunService.RenderStepped:Wait()
    hrp.AssemblyLinearVelocity = oldVel
    if spinEnabled then
        hrp.CFrame = CFrame.new(hrp.Position, oldCF.LookVector + hrp.Position)
    end

    desyncRunning = false
end

local function stopAA()
    if velocityConnection then
        velocityConnection:Disconnect()
        velocityConnection = nil
    end
end

local function startAA()
    if velocityConnection then return end
    velocityConnection = RunService.Heartbeat:Connect(function()
        if isIgnoredPlayerArmed() then
            if enabled then enabled = false end
            return
        else
            if userWantsEnabled and not enabled then enabled = true end
        end

        if not enabled then return end

        local char = LocalPlayer.Character
        if not (char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid")) then
            hadKnifeLastFrame = false
            return
        end

        local hum = char.Humanoid
        if hum.Health <= 0 then return end

        local hrp = char.HumanoidRootPart
        local gotKnife = hasKnife()

        if gotKnife and not hadKnifeLastFrame then
            doRollStep(hum)
        end
        hadKnifeLastFrame = gotKnife

        if isMurderer then return end

        if gotKnife and not isPlayerNearby(hrp) and not isInWater(hum) then
            applyDesync(hrp, hum)
        end
    end)
end

local aaSection = shared.AddSection("Anti Lock")

aaSection:AddParagraph("This was", "Skidded by @sl1yyy/Synx")

aaSection:AddToggle("Enable Anti-Aim", function(bool)
    userWantsEnabled = bool
    enabled = bool
    if bool then
        startAA()
        shared.Notify("Anti-Aim Enabled", 2)
    else
        stopAA()
        shared.Notify("Anti-Aim Disabled", 2)
    end
end)

aaSection:AddToggle("Enable Ignore List", function(bool)
    ignoreListEnabled = bool
    shared.Notify("Ignore List " .. (bool and "Enabled" or "Disabled"), 2)
end)

aaSection:AddToggle("Spin Jitter (CFrame)", function(bool)
    spinEnabled = bool
    shared.Notify("Spin Jitter " .. (bool and "On" or "Off"), 2)
end)

aaSection:AddToggle("Multi-Spike", function(bool)
    multiSpikeEnabled = bool
    shared.Notify("Multi-Spike " .. (bool and "On" or "Off"), 2)
end)

aaSection:AddSlider("Intensity", 100, 600, velocityIntensity, function(val)
    velocityIntensity = val
end)

aaSection:AddPlayerDropdown("Ignore Player 1", function(player)
    slot1Player = player
    shared.Notify("Slot 1: " .. (player and player.Name or "None"), 2)
end)

aaSection:AddPlayerDropdown("Ignore Player 2", function(player)
    slot2Player = player
    shared.Notify("Slot 2: " .. (player and player.Name or "None"), 2)
end)

aaSection:AddPlayerDropdown("Ignore Player 3", function(player)
    slot3Player = player
    shared.Notify("Slot 3: " .. (player and player.Name or "None"), 2)
end)

Players.PlayerRemoving:Connect(function(player)
    if slot1Player == player then slot1Player = nil end
    if slot2Player == player then slot2Player = nil end
    if slot3Player == player then slot3Player = nil end
end)
