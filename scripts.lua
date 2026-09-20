--[[
    Funky Friday AutoPlayer - Simulation Build
    + Accuracy Sliders
    + Release Delay Slider
    + Manual Force Mode
    + Keybind (PC) + On-screen Buttons (Mobile)
    + Full Mobile Support
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local IS_MOBILE = UserInputService.TouchEnabled

-- =========================================================
-- SETTINGS
-- =========================================================

local Settings = {
    Enabled = false,

    Accuracy = {
        Sick = 100,
        Good = 0,
        OK = 0,
        Bad = 0,
        Miss = 0,
    },

    Timing = {
        Sick = 0.000,
        Good = 0.035,
        OK = 0.075,
        Bad = 0.120,
    },

    DefaultHoldLength = 0.03,
    ReleaseDelay = 0.03,

    DetectionWindow = {
        Min = -0.04,
        Max = 0.75,
    },

    ManualMode = false,
    ForceResult = nil,

    ToggleKey = Enum.KeyCode.P,
    Debug = true,
}

-- =========================================================
-- STATE
-- =========================================================

local State = {
    Connection = nil,
    Generation = 0,
    Scheduled = {},
    Processed = {},

    Statistics = {
        Sick = 0,
        Good = 0,
        OK = 0,
        Bad = 0,
        Miss = 0,
    },
}

-- =========================================================
-- UTILITY
-- =========================================================

local function debugPrint(...)
    if Settings.Debug then
        print("[FFAutoPlayer]", ...)
    end
end

local function resetStatistics()
    for key in pairs(State.Statistics) do
        State.Statistics[key] = 0
    end
end

local function getStatistics()
    local result = {}
    for key, value in pairs(State.Statistics) do
        result[key] = value
    end
    return result
end

local function clearProcessed()
    table.clear(State.Processed)
end

-- =========================================================
-- ACCURACY
-- =========================================================

local Accuracy = {}

function Accuracy.getTotalWeight()
    local total = 0
    for _, weight in pairs(Settings.Accuracy) do
        total += math.max(0, tonumber(weight) or 0)
    end
    return total
end

function Accuracy.roll()
    if Settings.ManualMode and Settings.ForceResult then
        return Settings.ForceResult
    end

    local total = Accuracy.getTotalWeight()
    if total <= 0 then return "Sick" end

    local roll = math.random() * total
    local accumulated = 0
    local order = {"Sick", "Good", "OK", "Bad", "Miss"}

    for _, result in ipairs(order) do
        accumulated += math.max(0, tonumber(Settings.Accuracy[result]) or 0)
        if roll <= accumulated then
            return result
        end
    end
    return "Miss"
end

function Accuracy.getOffset(result)
    return Settings.Timing[result] or 0
end

-- =========================================================
-- HIT HANDLER (Simulation)
-- =========================================================

local HitHandler = {}

function HitHandler.press(lane, result, note)
    if result == "Miss" then
        debugPrint("MISS | lane=" .. tostring(lane))
        State.Statistics.Miss += 1
        return
    end
    State.Statistics[result] += 1
    debugPrint(string.format("%s | lane=%s | offset=%.3fs", result, tostring(lane), Accuracy.getOffset(result)))
end

function HitHandler.release(lane, result)
    debugPrint(string.format("RELEASE | lane=%s | result=%s", tostring(lane), tostring(result)))
end

-- =========================================================
-- SCHEDULER
-- =========================================================

local Scheduler = {}

function Scheduler.cancelAll()
    State.Generation += 1
    State.Scheduled = {}
    clearProcessed()
end

function Scheduler.schedule(delayTime, callback)
    local generation = State.Generation
    local job = {cancelled = false}
    table.insert(State.Scheduled, job)

    task.delay(math.max(0, delayTime), function()
        if job.cancelled or generation \~= State.Generation then return end
        local ok, err = pcall(callback)
        if not ok then warn("[FFAutoPlayer]", err) end
    end)
    return job
end

-- =========================================================
-- NOTE PROCESSOR + SCANNER
-- =========================================================

local NoteProcessor = {}

function NoteProcessor.isValid(note)
    return note and not State.Processed[note] and not note.Marked
end

function NoteProcessor.markAsProcessed(note)
    State.Processed[note] = true
end

function NoteProcessor.getLane(note)
    return note.Direction or note.Lane
end

function NoteProcessor.getTime(note)
    return tonumber(note.Time)
end

function NoteProcessor.getLength(note)
    return tonumber(note.Length) or Settings.DefaultHoldLength
end

function NoteProcessor.calculateDifference(noteTime, currentTime, playback)
    playback = tonumber(playback) or 1
    if playback <= 0 then playback = 1 end
    return (noteTime - currentTime) / playback
end

local function scheduleNote(note, diff, playback)
    if not NoteProcessor.isValid(note) then return end
    local lane = NoteProcessor.getLane(note)
    if not lane then return end

    NoteProcessor.markAsProcessed(note)
    local currentGeneration = State.Generation

    Scheduler.schedule(math.max(0, diff), function()
        if currentGeneration \~= State.Generation then return end

        local result = Accuracy.roll()
        if result == "Miss" then
            HitHandler.press(lane, result, note)
            return
        end

        HitHandler.press(lane, result, note)

        local holdLength = (NoteProcessor.getLength(note) / math.max(playback, 0.001)) + Settings.ReleaseDelay
        if holdLength > 0 then
            Scheduler.schedule(holdLength, function()
                if currentGeneration \~= State.Generation then return end
                HitHandler.release(lane, result)
            end)
        end
    end)
end

local NoteScanner = {}

function NoteScanner.scan(noteCache, side, currentTime, playback)
    if type(noteCache) \~= "table" then return end
    local minDiff, maxDiff = Settings.DetectionWindow.Min, Settings.DetectionWindow.Max

    for _, note in pairs(noteCache) do
        if NoteProcessor.isValid(note) and note.Field == side then
            local noteTime = NoteProcessor.getTime(note)
            if noteTime then
                local diff = NoteProcessor.calculateDifference(noteTime, currentTime, playback)
                if diff > minDiff and diff < maxDiff then
                    scheduleNote(note, diff, playback)
                end
            end
        end
    end
end

-- =========================================================
-- AUTO PLAYER
-- =========================================================

local AutoPlayer = {}

function AutoPlayer.stop()
    Settings.Enabled = false
    Scheduler.cancelAll()
    if State.Connection then
        State.Connection:Disconnect()
        State.Connection = nil
    end
    debugPrint("AutoPlayer stopped.")
end

function AutoPlayer.start(getGameState)
    AutoPlayer.stop()
    resetStatistics()
    clearProcessed()
    Settings.Enabled = true
    State.Generation += 1

    State.Connection = RunService.RenderStepped:Connect(function()
        if not Settings.Enabled then return end
        if type(getGameState) \~= "function" then return end

        local ok, gameState = pcall(getGameState)
        if not ok or type(gameState) \~= "table" or not gameState.Playing then return end

        NoteScanner.scan(gameState.NoteCache, gameState.Side, gameState.TimePosition, gameState.Playback)
    end)
    debugPrint("AutoPlayer started.")
end

function AutoPlayer.getStats()
    return getStatistics()
end

function AutoPlayer.toggle()
    if Settings.Enabled then
        AutoPlayer.stop()
    else
        AutoPlayer.start(function()
            return {
                Playing = false,
                NoteCache = {},
                Side = nil,
                TimePosition = 0,
                Playback = 1,
            }
        end)
    end
end

-- =========================================================
-- INPUT (PC + Mobile)
-- =========================================================

local function setForce(result)
    Settings.ManualMode = true
    Settings.ForceResult = result
    debugPrint("Manual Force: " .. result)
end

local function clearForce()
    Settings.ManualMode = false
    Settings.ForceResult = nil
    debugPrint("Manual Force: OFF")
end

-- PC Keybinds
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Settings.ToggleKey then
        AutoPlayer.toggle()
    elseif input.KeyCode == Enum.KeyCode.Q then setForce("Sick")
    elseif input.KeyCode == Enum.KeyCode.E then setForce("Good")
    elseif input.KeyCode == Enum.KeyCode.R then setForce("OK")
    elseif input.KeyCode == Enum.KeyCode.F then setForce("Bad")
    elseif input.KeyCode == Enum.KeyCode.G then setForce("Miss")
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E
    or input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.F
    or input.KeyCode == Enum.KeyCode.G then
        clearForce()
    end
end)

-- =========================================================
-- GUI
-- =========================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FFAutoPlayer"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Size = IS_MOBILE and UDim2.new(0, 340, 0, 620) or UDim2.new(0, 360, 0, 580)
Main.Position = UDim2.new(0.5, IS_MOBILE and -170 or -180, 0.5, IS_MOBILE and -310 or -290)
Main.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
Main.Parent = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 12)

-- Title + Drag
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 42)
Title.BackgroundTransparency = 1
Title.Text = "Funky Friday AutoPlayer"
Title.TextColor3 = Color3.fromRGB(0, 255, 180)
Title.TextScaled = true
Title.Font = Enum.Font.GothamBold
Title.Parent = Main

local dragging, dragStart, startPos, dragConn
local function beginDrag(input)
    dragging = true
    dragStart = input.Position
    startPos = Main.Position
    if dragConn then dragConn:Disconnect() end
    dragConn = UserInputService.InputChanged:Connect(function(changed)
        if not dragging then return end
        if changed.UserInputType == Enum.UserInputType.MouseMovement or changed.UserInputType == Enum.UserInputType.Touch then
            local delta = changed.Position - dragStart
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

Title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        beginDrag(input)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        if dragConn then dragConn:Disconnect() dragConn = nil end
    end
end)

-- =========================================================
-- GUI HELPERS
-- =========================================================

local function createToggle(name, y, default, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -20, 0, IS_MOBILE and 44 or 36)
    frame.Position = UDim2.new(0, 10, 0, y)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.Parent = Main
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.55, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "  " .. name
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0, IS_MOBILE and 90 or 80, 0, IS_MOBILE and 32 or 26)
    button.Position = UDim2.new(1, IS_MOBILE and -100 or -90, 0.5, IS_MOBILE and -16 or -13)
    button.TextScaled = true
    button.Font = Enum.Font.GothamBold
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Parent = frame
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)

    local state = default
    local function update()
        button.Text = state and "ON" or "OFF"
        button.BackgroundColor3 = state and Color3.fromRGB(0, 170, 0) or Color3.fromRGB(170, 0, 0)
    end
    button.MouseButton1Click:Connect(function()
        state = not state
        update()
        callback(state)
    end)
    update()
end

local function createSlider(name, y, min, max, default, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -20, 0, IS_MOBILE and 56 or 50)
    frame.Position = UDim2.new(0, 10, 0, y)
    frame.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
    frame.Parent = Main
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -12, 0, 22)
    label.Position = UDim2.new(0, 8, 0, 4)
    label.BackgroundTransparency = 1
    label.Text = name .. ": " .. default
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.TextScaled = true
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -16, 0, IS_MOBILE and 14 or 10)
    bar.Position = UDim2.new(0, 8, 0, IS_MOBILE and 32 or 30)
    bar.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    bar.Parent = frame
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 6)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 200, 140)
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)

    local draggingSlider = false

    local function update(value)
        value = math.clamp(value, min, max)
        fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
        label.Text = name .. ": " .. string.format(max <= 1 and "%.3f" or "%d", value)
        callback(value)
    end

    local function onInput(input)
        local relative = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
        update(min + relative * (max - min))
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
            onInput(input)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            onInput(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)

    update(default)
end

-- =========================================================
-- TOGGLES + SLIDERS
-- =========================================================

createToggle("Auto Player", 52, false, function(enabled)
    if enabled then
        AutoPlayer.start(function()
            return {Playing = false, NoteCache = {}, Side = nil, TimePosition = 0, Playback = 1}
        end)
    else
        AutoPlayer.stop()
    end
end)

createToggle("Debug Logging", 102, true, function(v) Settings.Debug = v end)

local sliderY = 155
createSlider("Sick %", sliderY, 0, 100, 100, function(v) Settings.Accuracy.Sick = v end)
createSlider("Good %", sliderY + 60, 0, 100, 0, function(v) Settings.Accuracy.Good = v end)
createSlider("OK %", sliderY + 120, 0, 100, 0, function(v) Settings.Accuracy.OK = v end)
createSlider("Bad %", sliderY + 180, 0, 100, 0, function(v) Settings.Accuracy.Bad = v end)
createSlider("Miss %", sliderY + 240, 0, 100, 0, function(v) Settings.Accuracy.Miss = v end)
createSlider("Release Delay", sliderY + 300, 0, 0.15, 0.03, function(v) Settings.ReleaseDelay = v end)

-- =========================================================
-- MOBILE FORCE BUTTONS
-- =========================================================

if IS_MOBILE then
    local forceFrame = Instance.new("Frame")
    forceFrame.Size = UDim2.new(1, -20, 0, 70)
    forceFrame.Position = UDim2.new(0, 10, 0, 520)
    forceFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    forceFrame.Parent = Main
    Instance.new("UICorner", forceFrame).CornerRadius = UDim.new(0, 8)

    local function makeForceBtn(text, result, x)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 58, 0, 50)
        btn.Position = UDim2.new(0, x, 0.5, -25)
        btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextScaled = true
        btn.Font = Enum.Font.GothamBold
        btn.Parent = forceFrame
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

        btn.MouseButton1Down:Connect(function() setForce(result) end)
        btn.MouseButton1Up:Connect(clearForce)
        btn.MouseLeave:Connect(clearForce)
    end

    makeForceBtn("SICK", "Sick", 8)
    makeForceBtn("GOOD", "Good", 72)
    makeForceBtn("OK", "OK", 136)
    makeForceBtn("BAD", "Bad", 200)
    makeForceBtn("MISS", "Miss", 264)
end

-- =========================================================
-- STATS + CLOSE
-- =========================================================

local StatsLabel = Instance.new("TextLabel")
StatsLabel.Size = UDim2.new(1, -20, 0, 26)
StatsLabel.Position = UDim2.new(0, 10, 0, IS_MOBILE and 600 or 470)
StatsLabel.BackgroundTransparency = 1
StatsLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
StatsLabel.TextScaled = true
StatsLabel.Font = Enum.Font.Gotham
StatsLabel.Parent = Main

local InfoLabel = Instance.new("TextLabel")
InfoLabel.Size = UDim2.new(1, -20, 0, 20)
InfoLabel.Position = UDim2.new(0, 10, 0, IS_MOBILE and 625 or 498)
InfoLabel.BackgroundTransparency = 1
InfoLabel.Text = IS_MOBILE and "Mobile Mode • Hold buttons to Force" or "PC: P = Toggle | Q/E/R/F/G = Force"
InfoLabel.TextColor3 = Color3.fromRGB(130, 130, 130)
InfoLabel.TextScaled = true
InfoLabel.Font = Enum.Font.Gotham
InfoLabel.Parent = Main

task.spawn(function()
    while ScreenGui.Parent do
        local s = AutoPlayer.getStats()
        StatsLabel.Text = string.format("Sick %d | Good %d | OK %d | Bad %d | Miss %d", s.Sick, s.Good, s.OK, s.Bad, s.Miss)
        task.wait(0.3)
    end
end)

local CloseButton = Instance.new("TextButton")
CloseButton.Size = UDim2.new(0, 120, 0, 34)
CloseButton.Position = UDim2.new(0.5, -60, 1, IS_MOBILE and -45 or -42)
CloseButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
CloseButton.Text = "CLOSE"
CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseButton.TextScaled = true
CloseButton.Font = Enum.Font.GothamBold
CloseButton.Parent = Main
Instance.new("UICorner", CloseButton).CornerRadius = UDim.new(0, 8)

CloseButton.MouseButton1Click:Connect(function()
    AutoPlayer.stop()
    ScreenGui:Destroy()
end)

print("Funky Friday AutoPlayer loaded • Mobile Support:", IS_MOBILE)
