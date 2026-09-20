--[[
    K4to ESP + Target Selector
    Script by itsK4to

    Features:
    - 2D ESP Box
    - Name
    - Distance
    - Health bar
    - Team check
    - Alive check
    - Visibility check
    - FOV circle
    - Closest target selector
    - Target highlight
    - Max distance
    - PC + Mobile
    - Draggable GUI
    - RightCtrl = Cursor Mode
]]

--========================================================--
-- SERVICES
--========================================================--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = Workspace.CurrentCamera

--========================================================--
-- SETTINGS
--========================================================--

local Settings = {

    ESP = {
        Enabled = true,
        Box = true,
        Name = true,
        Distance = true,
        Health = true,

        TeamCheck = true,
        AliveCheck = true,
        VisibilityCheck = false,

        MaxDistance = 1500,

        BoxColor = Color3.fromRGB(255, 255, 255),
        EnemyColor = Color3.fromRGB(255, 80, 80),
        TeamColor = Color3.fromRGB(80, 170, 255),

        TextSize = 12,
    },

    Target = {
        Enabled = true,

        TeamCheck = true,
        AliveCheck = true,
        VisibilityCheck = false,

        MaxDistance = 1500,

        FOVEnabled = true,
        FOVRadius = 180,

        TargetPart = "Head",

        TargetColor = Color3.fromRGB(255, 220, 80),
    },

    UI = {
        RightCtrlCursor = true,
    }
}

--========================================================--
-- STATE
--========================================================--

local State = {
    ESPObjects = {},
    SelectedPlayer = nil,
    CursorMode = false,
    Connections = {},
}

--========================================================--
-- HELPERS
--========================================================--

local function getCharacter(player)
    return player and player.Character
end

local function getHumanoid(character)
    if not character then
        return nil
    end

    return character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(character)
    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
end

local function isAlive(player)

    local character = getCharacter(player)
    local humanoid = getHumanoid(character)

    if not humanoid then
        return false
    end

    return humanoid.Health > 0
end

local function isSameTeam(player)

    if not Settings.ESP.TeamCheck then
        return false
    end

    return player.Team ~= nil
        and LocalPlayer.Team ~= nil
        and player.Team == LocalPlayer.Team
end

local function isSameTargetTeam(player)

    if not Settings.Target.TeamCheck then
        return false
    end

    return player.Team ~= nil
        and LocalPlayer.Team ~= nil
        and player.Team == LocalPlayer.Team
end

local function getTeamColor(player)

    if player.Team ~= nil then

        if LocalPlayer.Team ~= nil
            and player.Team == LocalPlayer.Team then

            return Settings.ESP.TeamColor
        end
    end

    return Settings.ESP.EnemyColor
end

local function getTargetPart(character)

    if not character then
        return nil
    end

    return character:FindFirstChild(
        Settings.Target.TargetPart
    )
        or character:FindFirstChild("Head")
        or character:FindFirstChild("HumanoidRootPart")
end

local function isVisible(part, character)

    if not part then
        return false
    end

    local origin = Camera.CFrame.Position
    local direction = part.Position - origin

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        LocalPlayer.Character,
    }

    local result = Workspace:Raycast(
        origin,
        direction,
        params
    )

    if not result then
        return true
    end

    return result.Instance:IsDescendantOf(character)
end

--========================================================--
-- GUI ROOT
--========================================================--

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "K4toESP"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

--========================================================--
-- FOV GUI
--========================================================--

local FOVFrame = Instance.new("Frame")
FOVFrame.Name = "FOV"
FOVFrame.AnchorPoint = Vector2.new(0.5, 0.5)
FOVFrame.Position = UDim2.fromOffset(0, 0)
FOVFrame.Size = UDim2.fromOffset(
    Settings.Target.FOVRadius * 2,
    Settings.Target.FOVRadius * 2
)
FOVFrame.BackgroundTransparency = 1
FOVFrame.Visible = Settings.Target.FOVEnabled
FOVFrame.Parent = ScreenGui

local FOVCorner = Instance.new("UICorner")
FOVCorner.CornerRadius = UDim.new(1, 0)
FOVCorner.Parent = FOVFrame

local FOVStroke = Instance.new("UIStroke")
FOVStroke.Thickness = 1.5
FOVStroke.Color = Color3.fromRGB(
    255,
    255,
    255
)
FOVStroke.Transparency = 0
FOVStroke.Parent = FOVFrame

--========================================================--
-- CENTER DOT
--========================================================--

local CenterDot = Instance.new("Frame")
CenterDot.Name = "CenterDot"
CenterDot.AnchorPoint = Vector2.new(0.5, 0.5)
CenterDot.Size = UDim2.fromOffset(4, 4)
CenterDot.BackgroundColor3 =
    Color3.fromRGB(255, 255, 255)
CenterDot.BorderSizePixel = 0
CenterDot.Parent = ScreenGui

local CenterCorner = Instance.new("UICorner")
CenterCorner.CornerRadius = UDim.new(1, 0)
CenterCorner.Parent = CenterDot

--========================================================--
-- TARGET LABEL
--========================================================--

local TargetLabel = Instance.new("TextLabel")
TargetLabel.Name = "TargetLabel"
TargetLabel.AnchorPoint = Vector2.new(0.5, 0)
TargetLabel.Position = UDim2.new(0.5, 0, 0.5, 18)
TargetLabel.Size = UDim2.fromOffset(300, 28)
TargetLabel.BackgroundTransparency = 1
TargetLabel.Text = "TARGET: NONE"
TargetLabel.TextColor3 =
    Settings.Target.TargetColor
TargetLabel.TextSize = 14
TargetLabel.Font = Enum.Font.GothamBold
TargetLabel.Visible = Settings.Target.Enabled
TargetLabel.Parent = ScreenGui

--========================================================--
-- GUI PANEL
--========================================================--

local Main = Instance.new("Frame")
Main.Name = "ControlPanel"
Main.Size = UDim2.fromOffset(280, 340)
Main.Position = UDim2.new(
    0.5,
    -140,
    0.5,
    -170
)
Main.BackgroundColor3 =
    Color3.fromRGB(22, 22, 30)
Main.BackgroundTransparency = 0.04
Main.BorderSizePixel = 0
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = Main

--========================================================--
-- TITLE
--========================================================--

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -45, 0, 40)
Title.BackgroundColor3 =
    Color3.fromRGB(40, 40, 55)
Title.BackgroundTransparency = 0.1
Title.Text = "👁 K4to ESP"
Title.TextColor3 =
    Color3.fromRGB(255, 255, 255)
Title.TextSize = 16
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Active = true
Title.Parent = Main

local TitlePadding = Instance.new("UIPadding")
TitlePadding.PaddingLeft = UDim.new(0, 12)
TitlePadding.Parent = Title

--========================================================--
-- CLOSE
--========================================================--

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(32, 30)
Close.Position = UDim2.new(1, -37, 0, 5)
Close.BackgroundColor3 =
    Color3.fromRGB(180, 50, 50)
Close.Text = "✕"
Close.TextColor3 =
    Color3.fromRGB(255, 255, 255)
Close.TextSize = 14
Close.Font = Enum.Font.GothamBold
Close.BorderSizePixel = 0
Close.Parent = Main

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = Close

--========================================================--
-- STATUS
--========================================================--

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -20, 0, 24)
Status.Position = UDim2.fromOffset(10, 50)
Status.BackgroundTransparency = 1
Status.Text = "ESP: ON | TARGET: ON"
Status.TextColor3 =
    Color3.fromRGB(100, 255, 140)
Status.TextSize = 12
Status.Font = Enum.Font.Gotham
Status.TextXAlignment =
    Enum.TextXAlignment.Left
Status.Parent = Main

--========================================================--
-- BUTTON MAKER
--========================================================--

local function CreateButton(
    text,
    y,
    callback
)

    local Button = Instance.new("TextButton")

    Button.Size =
        UDim2.new(1, -20, 0, 38)

    Button.Position =
        UDim2.fromOffset(10, y)

    Button.BackgroundColor3 =
        Color3.fromRGB(40, 40, 52)

    Button.Text = text

    Button.TextColor3 =
        Color3.fromRGB(255, 255, 255)

    Button.TextSize = 12
    Button.Font = Enum.Font.GothamBold
    Button.BorderSizePixel = 0

    Button.Parent = Main

    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 7)
    Corner.Parent = Button

    Button.Activated:Connect(callback)

    return Button
end

--========================================================--
-- ESP TOGGLE
--========================================================--

local ESPButton

ESPButton = CreateButton(
    "ESP: ON",
    82,
    function()

        Settings.ESP.Enabled =
            not Settings.ESP.Enabled

        ESPButton.Text =
            "ESP: "
            .. (
                Settings.ESP.Enabled
                and "ON"
                or "OFF"
            )

        Status.Text =
            "ESP: "
            .. (
                Settings.ESP.Enabled
                and "ON"
                or "OFF"
            )
            .. " | TARGET: "
            .. (
                Settings.Target.Enabled
                and "ON"
                or "OFF"
            )
    end
)

--========================================================--
-- TARGET TOGGLE
--========================================================--

local TargetButton

TargetButton = CreateButton(
    "Target Selector: ON",
    128,
    function()

        Settings.Target.Enabled =
            not Settings.Target.Enabled

        TargetButton.Text =
            "Target Selector: "
            .. (
                Settings.Target.Enabled
                and "ON"
                or "OFF"
            )

        TargetLabel.Visible =
            Settings.Target.Enabled

        Status.Text =
            "ESP: "
            .. (
                Settings.ESP.Enabled
                and "ON"
                or "OFF"
            )
            .. " | TARGET: "
            .. (
                Settings.Target.Enabled
                and "ON"
                or "OFF"
            )
    end
)

--========================================================--
-- FOV TOGGLE
--========================================================--

local FOVButton

FOVButton = CreateButton(
    "FOV Circle: ON",
    174,
    function()

        Settings.Target.FOVEnabled =
            not Settings.Target.FOVEnabled

        FOVFrame.Visible =
            Settings.Target.FOVEnabled

        FOVButton.Text =
            "FOV Circle: "
            .. (
                Settings.Target.FOVEnabled
                and "ON"
                or "OFF"
            )
    end
)

--========================================================--
-- VISIBILITY CHECK
--========================================================--

local VisibilityButton

VisibilityButton = CreateButton(
    "Visibility Check: OFF",
    220,
    function()

        Settings.Target.VisibilityCheck =
            not Settings.Target.VisibilityCheck

        Settings.ESP.VisibilityCheck =
            Settings.Target.VisibilityCheck

        VisibilityButton.Text =
            "Visibility Check: "
            .. (
                Settings.Target.VisibilityCheck
                and "ON"
                or "OFF"
            )
    end
)

--========================================================--
-- TEAM CHECK
--========================================================--

local TeamButton

TeamButton = CreateButton(
    "Team Check: ON",
    266,
    function()

        Settings.Target.TeamCheck =
            not Settings.Target.TeamCheck

        Settings.ESP.TeamCheck =
            Settings.Target.TeamCheck

        TeamButton.Text =
            "Team Check: "
            .. (
                Settings.Target.TeamCheck
                and "ON"
                or "OFF"
            )
    end
)

--========================================================--
-- CREDIT
--========================================================--

local Credit = Instance.new("TextLabel")
Credit.Size = UDim2.new(1, -20, 0, 20)
Credit.Position =
    UDim2.new(0, 10, 1, -28)
Credit.BackgroundTransparency = 1
Credit.Text = "Script by itsK4to"
Credit.TextColor3 =
    Color3.fromRGB(130, 130, 150)
Credit.TextSize = 10
Credit.Font = Enum.Font.Gotham
Credit.TextXAlignment =
    Enum.TextXAlignment.Right
Credit.Parent = Main

--========================================================--
-- GUI DRAG
--========================================================--

local dragging = false
local dragStart
local startPos
local activeInput

local function BeginDrag(input)

    dragging = true
    activeInput = input

    dragStart = input.Position
    startPos = Main.Position
end

local function EndDrag(input)

    if input == activeInput then

        dragging = false
        activeInput = nil
    end
end

Title.InputBegan:Connect(function(input)

    if input.UserInputType
        == Enum.UserInputType.MouseButton1
        or input.UserInputType
        == Enum.UserInputType.Touch then

        if UserInputService.MouseBehavior
            == Enum.MouseBehavior.Default
            or input.UserInputType
                == Enum.UserInputType.Touch then

            BeginDrag(input)
        end
    end
end)

Title.InputEnded:Connect(
    EndDrag
)

UserInputService.InputChanged:Connect(
    function(input)

        if not dragging then
            return
        end

        if input.UserInputType
            ~= Enum.UserInputType.MouseMovement
            and input.UserInputType
            ~= Enum.UserInputType.Touch then

            return
        end

        local delta =
            input.Position - dragStart

        Main.Position =
            UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,

                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
    end
)

UserInputService.InputEnded:Connect(
    function(input)

        if input == activeInput then

            dragging = false
            activeInput = nil
        end
    end
)

--========================================================--
-- CURSOR MODE
--========================================================--

local oldMouseBehavior =
    UserInputService.MouseBehavior

local oldMouseIcon =
    UserInputService.MouseIconEnabled

local function SetCursorMode(enabled)

    State.CursorMode = enabled

    if enabled then

        oldMouseBehavior =
            UserInputService.MouseBehavior

        oldMouseIcon =
            UserInputService.MouseIconEnabled

        UserInputService.MouseBehavior =
            Enum.MouseBehavior.Default

        UserInputService.MouseIconEnabled =
            true

    else

        UserInputService.MouseBehavior =
            oldMouseBehavior

        UserInputService.MouseIconEnabled =
            oldMouseIcon
    end
end

UserInputService.InputBegan:Connect(
    function(input, processed)

        if processed then
            return
        end

        if not Settings.UI.RightCtrlCursor then
            return
        end

        if input.KeyCode
            == Enum.KeyCode.RightControl then

            SetCursorMode(
                not State.CursorMode
            )
        end
    end
)

--========================================================--
-- ESP OBJECT
--========================================================--

local function CreateESP(player)

    if State.ESPObjects[player] then
        return State.ESPObjects[player]
    end

    local Holder = Instance.new("Frame")
    Holder.Name = "ESP_" .. player.Name
    Holder.BackgroundTransparency = 1
    Holder.BorderSizePixel = 0
    Holder.Visible = false
    Holder.ZIndex = 5
    Holder.Parent = ScreenGui

    -- Box
    local Box = Instance.new("Frame")
    Box.Name = "Box"
    Box.BackgroundTransparency = 1
    Box.BorderSizePixel = 0
    Box.Parent = Holder

    local Stroke = Instance.new("UIStroke")
    Stroke.Thickness = 1.5
    Stroke.Color =
        Settings.ESP.BoxColor
    Stroke.Parent = Box

    -- Name
    local NameLabel = Instance.new("TextLabel")
    NameLabel.Name = "Name"
    NameLabel.AnchorPoint =
        Vector2.new(0.5, 1)
    NameLabel.Position =
        UDim2.new(0.5, 0, 0, -3)
    NameLabel.Size =
        UDim2.new(0, 180, 0, 18)
    NameLabel.BackgroundTransparency = 1
    NameLabel.TextColor3 =
        Color3.fromRGB(255, 255, 255)
    NameLabel.TextSize =
        Settings.ESP.TextSize
    NameLabel.Font =
        Enum.Font.GothamBold
    NameLabel.TextStrokeTransparency = 0
    NameLabel.Parent = Box

    -- Distance
    local DistanceLabel =
        Instance.new("TextLabel")

    DistanceLabel.Name = "Distance"
    DistanceLabel.AnchorPoint =
        Vector2.new(0.5, 0)
    DistanceLabel.Position =
        UDim2.new(0.5, 0, 1, 3)
    DistanceLabel.Size =
        UDim2.new(0, 180, 0, 18)
    DistanceLabel.BackgroundTransparency = 1
    DistanceLabel.TextColor3 =
        Color3.fromRGB(220, 220, 220)
    DistanceLabel.TextSize = 11
    DistanceLabel.Font =
        Enum.Font.Gotham
    DistanceLabel.TextStrokeTransparency = 0
    DistanceLabel.Parent = Box

    -- Health background
    local HealthBack = Instance.new("Frame")
    HealthBack.Name = "HealthBack"
    HealthBack.AnchorPoint =
        Vector2.new(1, 1)
    HealthBack.Position =
        UDim2.new(0, -4, 1, 0)
    HealthBack.Size =
        UDim2.new(0, 4, 1, 0)
    HealthBack.BackgroundColor3 =
        Color3.fromRGB(35, 35, 35)
    HealthBack.BorderSizePixel = 0
    HealthBack.Parent = Box

    local HealthFill = Instance.new("Frame")
    HealthFill.Name = "HealthFill"
    HealthFill.AnchorPoint =
        Vector2.new(0, 1)
    HealthFill.Position =
        UDim2.new(0, 0, 1, 0)
    HealthFill.Size =
        UDim2.new(1, 0, 1, 0)
    HealthFill.BackgroundColor3 =
        Color3.fromRGB(80, 255, 80)
    HealthFill.BorderSizePixel = 0
    HealthFill.Parent = HealthBack

    State.ESPObjects[player] = {
        Holder = Holder,
        Box = Box,
        Stroke = Stroke,
        NameLabel = NameLabel,
        DistanceLabel = DistanceLabel,
        HealthBack = HealthBack,
        HealthFill = HealthFill,
    }

    return State.ESPObjects[player]
end

--========================================================--
-- REMOVE ESP
--========================================================--

local function RemoveESP(player)

    local data =
        State.ESPObjects[player]

    if not data then
        return
    end

    if data.Holder then
        data.Holder:Destroy()
    end

    State.ESPObjects[player] = nil
end

--========================================================--
-- UPDATE ESP
--========================================================--

local function UpdateESP(player)

    local data =
        CreateESP(player)

    if not Settings.ESP.Enabled then

        data.Holder.Visible = false
        return
    end

    if player == LocalPlayer then

        data.Holder.Visible = false
        return
    end

    local character =
        getCharacter(player)

    local humanoid =
        getHumanoid(character)

    local root =
        getRoot(character)

    if not character
        or not humanoid
        or not root then

        data.Holder.Visible = false
        return
    end

    if Settings.ESP.AliveCheck
        and humanoid.Health <= 0 then

        data.Holder.Visible = false
        return
    end

    if Settings.ESP.TeamCheck
        and isSameTeam(player) then

        data.Holder.Visible = false
        return
    end

    local distance =
        (
            Camera.CFrame.Position
            - root.Position
        ).Magnitude

    if distance >
        Settings.ESP.MaxDistance then

        data.Holder.Visible = false
        return
    end

    local head =
        character:FindFirstChild("Head")

    if not head then
        data.Holder.Visible = false
        return
    end

    if Settings.ESP.VisibilityCheck
        and not isVisible(head, character) then

        data.Holder.Visible = false
        return
    end

    local rootPos, rootVisible =
        Camera:WorldToViewportPoint(
            root.Position
        )

    local headPos, headVisible =
        Camera:WorldToViewportPoint(
            head.Position + Vector3.new(
                0,
                0.5,
                0
            )
        )

    if not rootVisible
        or not headVisible
        or rootPos.Z <= 0 then

        data.Holder.Visible = false
        return
    end

    local height =
        math.abs(
            rootPos.Y
            - headPos.Y
        ) * 2

    if height < 20 then
        height = 20
    end

    local width =
        height * 0.55

    local centerX =
        headPos.X

    local centerY =
        (
            headPos.Y
            + rootPos.Y
        ) / 2

    data.Holder.Position =
        UDim2.fromOffset(
            centerX,
            centerY
        )

    data.Holder.Size =
        UDim2.fromOffset(
            width,
            height
        )

    data.Box.Size =
        UDim2.fromScale(1, 1)

    local color =
        getTeamColor(player)

    data.Stroke.Color =
        color

    data.NameLabel.Visible =
        Settings.ESP.Name

    data.DistanceLabel.Visible =
        Settings.ESP.Distance

    data.HealthBack.Visible =
        Settings.ESP.Health

    data.NameLabel.Text =
        player.DisplayName
        .. " ["
        .. player.Name
        .. "]"

    data.DistanceLabel.Text =
        string.format(
            "%.0f studs",
            distance
        )

    local healthPercent =
        math.clamp(
            humanoid.Health
            / math.max(
                humanoid.MaxHealth,
                1
            ),
            0,
            1
        )

    data.HealthFill.Size =
        UDim2.new(
            1,
            0,
            healthPercent,
            0
        )

    if healthPercent <= 0.25 then

        data.HealthFill.BackgroundColor3 =
            Color3.fromRGB(
                255,
                60,
                60
            )

    elseif healthPercent <= 0.5 then

        data.HealthFill.BackgroundColor3 =
            Color3.fromRGB(
                255,
                180,
                60
            )

    else

        data.HealthFill.BackgroundColor3 =
            Color3.fromRGB(
                80,
                255,
                80
            )
    end

    data.Holder.Visible =
        Settings.ESP.Box
        or Settings.ESP.Name
        or Settings.ESP.Distance
        or Settings.ESP.Health
end

--========================================================--
-- TARGET SELECTION
--========================================================--

local function GetClosestTarget()

    if not Settings.Target.Enabled then
        return nil
    end

    local mousePos =
        UserInputService:GetMouseLocation()

    -- Center of screen for controller/mobile
    -- / when cursor is not actively moved.
    local screenCenter =
        Vector2.new(
            Camera.ViewportSize.X / 2,
            Camera.ViewportSize.Y / 2
        )

    local center =
        State.CursorMode
        and mousePos
        or screenCenter

    local bestPlayer = nil
    local bestDistance =
        Settings.Target.FOVEnabled
        and Settings.Target.FOVRadius
        or math.huge

    local best3D =
        Settings.Target.MaxDistance

    for _, player in ipairs(
        Players:GetPlayers()
    ) do

        if player == LocalPlayer then
            continue
        end

        if Settings.Target.TeamCheck
            and isSameTargetTeam(player) then
            continue
        end

        local character =
            getCharacter(player)

        local humanoid =
            getHumanoid(character)

        if not character
            or not humanoid then
            continue
        end

        if Settings.Target.AliveCheck
            and humanoid.Health <= 0 then
            continue
        end

        local root =
            getRoot(character)

        local part =
            getTargetPart(character)

        if not root or not part then
            continue
        end

        local distance3D =
            (
                Camera.CFrame.Position
                - root.Position
            ).Magnitude

        if distance3D >
            best3D then
            continue
        end

        if Settings.Target.VisibilityCheck
            and not isVisible(
                part,
                character
            ) then
            continue
        end

        local point, visible =
            Camera:WorldToViewportPoint(
                part.Position
            )

        if not visible
            or point.Z <= 0 then
            continue
        end

        local screenPoint =
            Vector2.new(
                point.X,
                point.Y
            )

        local screenDistance =
            (
                center
                - screenPoint
            ).Magnitude

        if screenDistance < bestDistance then

            bestDistance =
                screenDistance

            best3D =
                distance3D

            bestPlayer =
                player
        end
    end

    return bestPlayer
end

--========================================================--
-- TARGET HIGHLIGHT
--========================================================--

local TargetHighlight = Instance.new("Highlight")

TargetHighlight.Name =
    "K4toTargetHighlight"

TargetHighlight.DepthMode =
    Enum.HighlightDepthMode.AlwaysOnTop

TargetHighlight.FillColor =
    Settings.Target.TargetColor

TargetHighlight.OutlineColor =
    Color3.fromRGB(255, 255, 255)

TargetHighlight.FillTransparency = 0.75
TargetHighlight.OutlineTransparency = 0

TargetHighlight.Enabled = false
TargetHighlight.Parent = ScreenGui

--========================================================--
-- RENDER LOOP
--========================================================--

local RenderConnection =
    RunService.RenderStepped:Connect(
        function()

            Camera =
                Workspace.CurrentCamera

            -- Center dot
            CenterDot.Position =
                UDim2.fromOffset(
                    Camera.ViewportSize.X / 2,
                    Camera.ViewportSize.Y / 2
                )

            -- FOV
            FOVFrame.Position =
                UDim2.fromOffset(
                    Camera.ViewportSize.X / 2,
                    Camera.ViewportSize.Y / 2
                )

            FOVFrame.Size =
                UDim2.fromOffset(
                    Settings.Target.FOVRadius * 2,
                    Settings.Target.FOVRadius * 2
                )

            FOVFrame.Visible =
                Settings.Target.Enabled
                and Settings.Target.FOVEnabled

            -- ESP
            for _, player in ipairs(
                Players:GetPlayers()
            ) do

                if player ~= LocalPlayer then
                    UpdateESP(player)
                end
            end

            -- Target
            local target =
                GetClosestTarget()

            State.SelectedPlayer =
                target

            if target then

                TargetLabel.Text =
                    "TARGET: "
                    .. target.DisplayName

                TargetLabel.TextColor3 =
                    Settings.Target.TargetColor

                local character =
                    getCharacter(target)

                if character then

                    TargetHighlight.Adornee =
                        character

                    TargetHighlight.Enabled =
                        Settings.Target.Enabled
                end

            else

                TargetLabel.Text =
                    "TARGET: NONE"

                TargetHighlight.Enabled =
                    false

                TargetHighlight.Adornee =
                    nil
            end
        end
    )

table.insert(
    State.Connections,
    RenderConnection
)

--========================================================--
-- PLAYER EVENTS
--========================================================--

local PlayerAddedConnection =
    Players.PlayerAdded:Connect(
        function(player)

            if player ~= LocalPlayer then
                CreateESP(player)
            end
        end
    )

local PlayerRemovingConnection =
    Players.PlayerRemoving:Connect(
        function(player)

            RemoveESP(player)

            if State.SelectedPlayer
                == player then

                State.SelectedPlayer =
                    nil
            end
        end
    )

table.insert(
    State.Connections,
    PlayerAddedConnection
)

table.insert(
    State.Connections,
    PlayerRemovingConnection
)

-- Create existing ESP
for _, player in ipairs(
    Players:GetPlayers()
) do

    if player ~= LocalPlayer then
        CreateESP(player)
    end
end

--========================================================--
-- CLOSE
--========================================================--

Close.Activated:Connect(
    function()

        for _, connection in ipairs(
            State.Connections
        ) do

            pcall(
                function()
                    connection:Disconnect()
                end
            )
        end

        for player, _ in pairs(
            State.ESPObjects
        ) do

            RemoveESP(player)
        end

        TargetHighlight:Destroy()

        if State.CursorMode then

            UserInputService.MouseBehavior =
                oldMouseBehavior

            UserInputService.MouseIconEnabled =
                oldMouseIcon
        end

        ScreenGui:Destroy()
    end
)

--========================================================--
-- LOADED
--========================================================--

print(
    "======================================"
)

print(
    "👁 K4to ESP + Target Selector"
)

print(
    "✅ Script by itsK4to"
)

print(
    "✅ ESP Box / Name / HP / Distance"
)

print(
    "✅ FOV + Closest Target"
)

print(
    "✅ Team + Visibility Check"
)

print(
    "✅ PC + Mobile"
)

print(
    "✅ RightCtrl = Cursor Mode"
)

print(
    "======================================"
)
