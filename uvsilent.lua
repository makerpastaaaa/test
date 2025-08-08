-- Wait for game to load
if not game:IsLoaded() then 
    game.Loaded:Wait()
end

-- Fallback for GUI protection
if not syn or not protectgui then
    getgenv().protectgui = function() end
end

-- Silent Aim Settings
local SilentAimSettings = {
    Enabled = false,
    AutoShoot = true,
    CPS = 15,
    TeamCheck = false,
    VisibleCheck = false, 
    TargetPart = "Head",
    SilentAimMethod = "Raycast",
    FOVRadius = 70,
    FOVVisible = true,
    ShowSilentAimTarget = false,
    MouseHitPrediction = false,
    MouseHitPredictionAmount = 0.165,
    HitChance = 100,
    MaxTargetDistance = 500
}

-- Variables
getgenv().SilentAimSettings = SilentAimSettings
local LastShotTime = 0
local VisibleCheckCache = {}
local CacheDuration = 0.3

local Camera = workspace.CurrentCamera
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local GetPlayers = Players.GetPlayers
local WorldToScreen = Camera.WorldToScreenPoint
local WorldToViewportPoint = Camera.WorldToViewportPoint
local FindFirstChild = game.FindFirstChild
local RenderStepped = RunService.RenderStepped
local GetMouseLocation = UserInputService.GetMouseLocation

local ValidTargetParts = {"Head", "Torso", "LeftLeg", "RightLeg"}
local PredictionAmount = 0.165

-- ***** NEW: Global table for key bindings *****
local keyBindings = {}

-- Convert degrees to pixels for FOV
local function degreesToPixels(degrees)
    local cameraFOV = Camera.FieldOfView
    local screenHeight = Camera.ViewportSize.Y
    local radians = math.rad(degrees / 2)
    local cameraFOVRad = math.rad(cameraFOV / 2)
    return math.tan(radians) * (screenHeight / (2 * math.tan(cameraFOVRad)))
end

-- Drawing objects
local target_circle = Drawing.new("Circle")
target_circle.Visible = false
target_circle.ZIndex = 999
target_circle.Color = Color3.fromRGB(54, 57, 241)
target_circle.Thickness = 2
target_circle.NumSides = 100
target_circle.Radius = 10
target_circle.Filled = false
target_circle.Transparency = 0.8

local pulse_circle = Drawing.new("Circle")
pulse_circle.Visible = false
pulse_circle.ZIndex = 998
pulse_circle.Color = Color3.fromRGB(54, 57, 241)
pulse_circle.Thickness = 1
pulse_circle.NumSides = 100
pulse_circle.Radius = 10
pulse_circle.Filled = false
pulse_circle.Transparency = 0.5

local fov_circle = Drawing.new("Circle")
fov_circle.Thickness = 1
fov_circle.NumSides = 100
fov_circle.Radius = degreesToPixels(SilentAimSettings.FOVRadius)
fov_circle.Filled = false
fov_circle.Visible = SilentAimSettings.FOVVisible
fov_circle.ZIndex = 999
fov_circle.Transparency = 1
fov_circle.Color = Color3.fromRGB(54, 57, 241)

-- Check Drawing API
if not _G.Drawing then
    warn("Drawing API is not available.")
end

local ExpectedArguments = {
    Raycast = {
        ArgCountRequired = 3,
        Args = {
            "Instance", "Vector3", "Vector3", "RaycastParams"
        }
    }
}

-- Initialize Compact UI Library
local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/cueshut/saves/main/compact"))()
if not UI then
    warn("Не удалось загрузить библиотеку UI!")
    return
end
UI = UI.init("Unloosed.pel", "v1.4.88", "Pasta")

-- UI Setup
local AimOne, AimTwo = UI:AddTab("Aim", "Silent Aim") do
    local Section = AimOne:AddSeperator("Silent Aim Settings") do
        local masterToggle = Section:AddToggle({
            title = "Enabled",
            desc = "Enable Silent Aim (RightAlt to toggle)",
            checked = SilentAimSettings.Enabled,
            callback = function(state)
                SilentAimSettings.Enabled = state
                target_circle.Visible = state and SilentAimSettings.ShowSilentAimTarget
                pulse_circle.Visible = state and SilentAimSettings.ShowSilentAimTarget
            end
        })

        Section:AddToggle({
            title = "Auto Shoot",
            desc = "Enable Auto Shoot",
            checked = SilentAimSettings.AutoShoot,
            callback = function(state)
                SilentAimSettings.AutoShoot = state
            end
        })

        Section:AddSlider({
            title = "Clicks Per Second",
            desc = "Set CPS for Auto Shoot",
            values = {min=1, max=30, default=SilentAimSettings.CPS},
            callback = function(set)
                SilentAimSettings.CPS = math.clamp(set, 1, 30)
            end
        })

        Section:AddToggle({
            title = "Team Check",
            desc = "Check for team",
            checked = SilentAimSettings.TeamCheck,
            callback = function(state)
                SilentAimSettings.TeamCheck = state
            end
        })

        Section:AddToggle({
            title = "Visible Check",
            desc = "Check for visibility",
            checked = SilentAimSettings.VisibleCheck,
            callback = function(state)
                SilentAimSettings.VisibleCheck = state
            end
        })

        local bodyparts = {"Head", "Torso", "LeftLeg", "RightLeg"}
        Section:AddSelection({
            title = "Target Part",
            desc = "Select target part",
            options = bodyparts,
            callback = function(selected)
                SilentAimSettings.TargetPart = bodyparts[selected[1]] or "Head"
            end
        })

        Section:AddSlider({
            title = "Hit Chance",
            desc = "Set hit chance percentage",
            values = {min=0, max=100, default=SilentAimSettings.HitChance},
            callback = function(set)
                SilentAimSettings.HitChance = set
            end
        })

        Section:AddToggle({
            title = "Mouse Hit Prediction",
            desc = "Enable mouse hit prediction",
            checked = SilentAimSettings.MouseHitPrediction,
            callback = function(state)
                SilentAimSettings.MouseHitPrediction = state
            end
        })

        Section:AddSlider({
            title = "Prediction Amount",
            desc = "Set prediction amount",
            values = {min=0.165, max=1, default=SilentAimSettings.MouseHitPredictionAmount},
            callback = function(set)
                SilentAimSettings.MouseHitPredictionAmount = set
                PredictionAmount = set
            end
        })
    end

    local VisualsSection = AimTwo:AddSeperator("Silent Aim Visuals") do
        local fovToggle, fovColor = Section:AddToggle({
            title = "Show FOV Circle",
            desc = "Show FOV circle",
            checked = SilentAimSettings.FOVVisible,
            callback = function(state)
                SilentAimSettings.FOVVisible = state
                fov_circle.Visible = state
            end,
            colorpicker = {
                default = Color3.fromRGB(54, 57, 241),
                callback = function(color)
                    fov_circle.Color = color
                end
            }
        })

        Section:AddSlider({
            title = "FOV Radius (Degrees)",
            desc = "Set FOV radius",
            values = {min=0, max=2000, default=SilentAimSettings.FOVRadius},
            callback = function(set)
                SilentAimSettings.FOVRadius = set
                fov_circle.Radius = degreesToPixels(set)
            end
        })

        local targetToggle, targetColor = Section:AddToggle({
            title = "Show Silent Aim Target",
            desc = "Show aim target",
            checked = SilentAimSettings.ShowSilentAimTarget,
            callback = function(state)
                SilentAimSettings.ShowSilentAimTarget = state
                target_circle.Visible = state and SilentAimSettings.Enabled
                pulse_circle.Visible = state and SilentAimSettings.Enabled
            end,
            colorpicker = {
                default = Color3.fromRGB(54, 57, 241),
                callback = function(color)
                    target_circle.Color = color
                    pulse_circle.Color = color
                end
            }
        })
    end
end

-- ***** NEW: Add Settings Tab for Key Bindings *****
local SettingsTab = UI:AddTab("Настройки", "Выбор кнопки") do
    local Section = SettingsTab:AddSeperator("Выбор кнопки") do
        local keyOptions = {"Insert", "Home", "Delete", "End"}
        local keyDropdown = Section:AddDropdown({
            title = "Выбери кнопку",
            options = keyOptions,
            callback = function(selected)
                local selectedKey = keyOptions[selected]
                print("Выбрана кнопка:", selectedKey)
            end
        })

        Section:AddButton({
            title = "Назначить переключение UI",
            callback = function()
                local selectedIndex = keyDropdown.getSelected()
                if selectedIndex and selectedIndex > 0 and selectedIndex <= #keyOptions then
                    local selectedKey = keyOptions[selectedIndex]
                    keyBindings[selectedKey] = "ToggleUI"
                    print("Кнопка", selectedKey, "назначена для переключения UI")
                else
                    warn("Выбери кнопку сначала!")
                end
            end
        })
    end
end

-- Functions
local function getPositionOnScreen(Vector)
    local Vec3, OnScreen = WorldToScreen(Camera, Vector)
    return Vector2.new(Vec3.X, Vec3.Y), OnScreen
end

local function ValidateArguments(Args, RayMethod)
    local Matches = 0
    if #Args < RayMethod.ArgCountRequired then
        return false
    end
    for Pos, Argument in next, Args do
        if typeof(Argument) == RayMethod.Args[Pos] then
            Matches = Matches + 1
        end
    end
    return Matches >= RayMethod.ArgCountRequired
end

local function getDirection(Origin, Position)
    return (Position - Origin).Unit * 1000
end

local function getMousePosition()
    return GetMouseLocation(UserInputService)
end

local function visibleCheck(target, part)
    if not SilentAimSettings.VisibleCheck then return true end
    if not target or not target.Character or not part then
        return false
    end

    local currentTime = tick()
    local cacheKey = tostring(target.UserId)

    if VisibleCheckCache[cacheKey] and currentTime - VisibleCheckCache[cacheKey].time < CacheDuration then
        return VisibleCheckCache[cacheKey].visible
    end

    local PlayerCharacter = target.Character
    local LocalPlayerCharacter = LocalPlayer.Character

    if not (PlayerCharacter and LocalPlayerCharacter) then
        VisibleCheckCache[cacheKey] = { visible = false, time = currentTime }
        return false
    end

    local PlayerRoot = FindFirstChild(PlayerCharacter, SilentAimSettings.TargetPart) or FindFirstChild(PlayerCharacter, "HumanoidRootPart")
    local LocalPlayerRoot = FindFirstChild(LocalPlayerCharacter, "HumanoidRootPart")

    if not (PlayerRoot and LocalPlayerRoot) then
        VisibleCheckCache[cacheKey] = { visible = false, time = currentTime }
        return false
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayerCharacter, PlayerCharacter}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.IgnoreWater = true
    raycastParams.RespectCanCollide = true

    local pointsToCheck = {
        PlayerRoot.Position,
        PlayerRoot.Position + Vector3.new(0, 2, 0),
        PlayerRoot.Position + Vector3.new(0, -1, 0)
    }

    for _, point in ipairs(pointsToCheck) do
        local direction = (point - LocalPlayerRoot.Position).Unit
        local distance = (point - LocalPlayerRoot.Position).Magnitude
        local raycastResult = workspace:Raycast(LocalPlayerRoot.Position, direction * distance, raycastParams)
        if not raycastResult or (raycastResult.Instance:IsDescendantOf(PlayerCharacter)) then
            VisibleCheckCache[cacheKey] = { visible = true, time = currentTime }
            return true
        end
    end

    VisibleCheckCache[cacheKey] = { visible = false, time = currentTime }
    return false
end

local function getClosestPlayer()
    if not SilentAimSettings.TargetPart then return end
    local Closest
    local DistanceToMouse
    local pixelRadius = degreesToPixels(SilentAimSettings.FOVRadius)
    local LocalPlayerRoot = LocalPlayer.Character and FindFirstChild(LocalPlayer.Character, "HumanoidRootPart")
    if not LocalPlayerRoot then return end

    for _, Player in next, GetPlayers(Players) do
        if Player == LocalPlayer then continue end
        if SilentAimSettings.TeamCheck and Player.Team == LocalPlayer.Team then continue end

        local Character = Player.Character
        if not Character then continue end
        
        local TargetPart = FindFirstChild(Character, SilentAimSettings.TargetPart)
        local Humanoid = FindFirstChild(Character, "Humanoid")
        if not TargetPart or not Humanoid or Humanoid.Health <= 0 then continue end

        local PlayerRoot = FindFirstChild(Character, "HumanoidRootPart")
        if PlayerRoot and (LocalPlayerRoot.Position - PlayerRoot.Position).Magnitude > SilentAimSettings.MaxTargetDistance then
            continue
        end

        local ScreenPosition, OnScreen = getPositionOnScreen(TargetPart.Position)
        if not OnScreen then continue end

        local Distance = (getMousePosition() - ScreenPosition).Magnitude
        if Distance > pixelRadius then continue end
        
        if SilentAimSettings.VisibleCheck and not visibleCheck(Player, TargetPart) then continue end

        if Distance <= (DistanceToMouse or pixelRadius or 2000) then
            Closest = TargetPart
            DistanceToMouse = Distance
        end
    end
    return Closest
end

local function CalculateChance(Percentage)
    Percentage = math.floor(Percentage)
    local chance = math.floor(Random.new().NextNumber(Random.new(), 0, 1) * 100) / 100
    return chance <= Percentage / 100
end

-- Pulse animation for target
local pulse_start = tick()
local function updatePulseAnimation()
    local elapsed = tick() - pulse_start
    local scale = 1 + 0.5 * math.sin(elapsed * 2)
    pulse_circle.Radius = 10 * scale
    pulse_circle.Transparency = 0.5 * (1 - math.abs(math.sin(elapsed * 2)))
end

-- Update visuals and auto shoot
coroutine.resume(coroutine.create(function()
    RenderStepped:Connect(function()
        updatePulseAnimation()
        
        if SilentAimSettings.ShowSilentAimTarget and SilentAimSettings.Enabled then
            local closest = getClosestPlayer()
            if closest then 
                local rootToViewportPoint, isOnScreen = WorldToViewportPoint(Camera, closest.Position)
                target_circle.Visible = isOnScreen
                pulse_circle.Visible = isOnScreen
                target_circle.Position = Vector2.new(rootToViewportPoint.X, rootToViewportPoint.Y)
                pulse_circle.Position = Vector2.new(rootToViewportPoint.X, rootToViewportPoint.Y)
            else 
                target_circle.Visible = false
                pulse_circle.Visible = false
                target_circle.Position = Vector2.new(0, 0)
                pulse_circle.Position = Vector2.new(0, 0)
            end
        end
        
        if SilentAimSettings.FOVVisible then 
            fov_circle.Visible = SilentAimSettings.FOVVisible
            fov_circle.Position = getMousePosition()
        end

        if SilentAimSettings.Enabled and SilentAimSettings.AutoShoot then
            local currentTime = tick()
            local shootInterval = 1 / math.max(SilentAimSettings.CPS, 1)
            if currentTime - LastShotTime >= shootInterval then
                local target = getClosestPlayer()
                if target and CalculateChance(SilentAimSettings.HitChance) then
                    local success, err = pcall(function()
                        mouse1press()
                        mouse1release()
                    end)
                    if not success then
                        warn("AutoShoot: Failed to fire - " .. tostring(err))
                    end
                    LastShotTime = currentTime
                end
            end
        end
    end)
end))

-- Hooks
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
    local Method = getnamecallmethod()
    local Arguments = {...}
    local self = Arguments[1]
    local chance = CalculateChance(SilentAimSettings.HitChance)
    if SilentAimSettings.Enabled and self == workspace and not checkcaller() and chance then
        if Method == "Raycast" and SilentAimSettings.SilentAimMethod == "Raycast" then
            if ValidateArguments(Arguments, ExpectedArguments.Raycast) then
                local A_Origin = Arguments[2]
                local HitPart = getClosestPlayer()
                if HitPart then
                    local targetPosition = HitPart.Position
                    if SilentAimSettings.MouseHitPrediction then
                        local humanoid = HitPart.Parent:FindFirstChild("Humanoid")
                        if humanoid and humanoid.MoveDirection.Magnitude > 0 then
                            targetPosition = targetPosition + (humanoid.MoveDirection * SilentAimSettings.MouseHitPredictionAmount)
                        end
                    end
                    Arguments[3] = getDirection(A_Origin, targetPosition)
                    return oldNamecall(unpack(Arguments))
                end
            end
        end
    end
    return oldNamecall(...)
end))

-- ***** MODIFIED: Merge Input Handling for Aimbot and UI Toggle *****
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    -- Handle Aimbot toggle (RightAlt)
    if input.KeyCode == Enum.KeyCode.RightAlt then
        SilentAimSettings.Enabled = not SilentAimSettings.Enabled
        target_circle.Visible = SilentAimSettings.Enabled and SilentAimSettings.ShowSilentAimTarget
        pulse_circle.Visible = SilentAimSettings.Enabled and SilentAimSettings.ShowSilentAimTarget
        AimOne:Find("Enabled"):Set(SilentAimSettings.Enabled)
    end

    -- Handle UI toggle based on key bindings
    local keyMap = {
        Insert = Enum.KeyCode.Insert,
        Home = Enum.KeyCode.Home,
        Delete = Enum.KeyCode.Delete,
        End = Enum.KeyCode.End
    }
    for keyName, keyCode in pairs(keyMap) do
        if input.KeyCode == keyCode and keyBindings[keyName] == "ToggleUI" then
            UI:ToggleGUI()
            print("UI переключён через", keyName, "в", os.date("%H:%M:%S", os.time()))
        end
    end
end)

-- Cleanup on death and respawn
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid", 5)
        if humanoid then
            humanoid.Died:Connect(function()
                VisibleCheckCache[tostring(player.UserId)] = nil
            end)
        end
    end)
end)

LocalPlayer.CharacterAdded:Connect(function(newChar)
    task.wait(1)
    target_circle.Visible = false
    pulse_circle.Visible = false
    fov_circle.Visible = false
end)
