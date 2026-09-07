--[[
==================================================================
        FutbolUmsu · Bundle.lua (TEK DOSYA - FULL MOBIL FIX)
  Delta X · Arceus X · Hydrogen · Fluxus · Codex · KRNL Destekli
  
  KULLANIM (Executor'da):
    loadstring(game:HttpGet("RAW_GITHUB_LINKINIZ"))()
==================================================================
--]]

-- Eski oturum varsa durdur
if getgenv and getgenv()._FU_Loaded then
    if getgenv()._FU_Stop then
        pcall(getgenv()._FU_Stop)
    end
    task.wait(0.2)
end

-- ===============================================================
-- 1. ROBLOX SERVISLERI
-- ===============================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local CollectionService= game:GetService("CollectionService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
local Camera      = workspace.CurrentCamera or workspace:FindFirstChildOfClass("Camera")

local IS_MOBILE   = UserInputService.TouchEnabled

-- ===============================================================
-- 2. YAPILANDIRMA (CONFIG)
-- ===============================================================
local Config = {
    Combat = {
        AutoParry        = false,
        AutoParryRadius  = 14,
        AutoParryDelay   = 0.05,
        AutoTackle       = false,
        TackleRange      = 12,
        TackleDelay      = 0.1,
        AutoKnockout     = false,
        KORange          = 9,
        KODelay          = 0.15,
        AntiTackle       = false,
        DesyncOffset     = 3.5,
        ParryAnimIDs     = {
            ["punch"] = "rbxassetid://000000001",
            ["slide"] = "rbxassetid://000000002",
        },
        FeintRemoteName  = "BodyFeint",
        TackleRemoteName = "Tackle",
        PunchRemoteName  = "Punch",
    },
    Ball = {
        SilentAim         = false,
        SilentAimCorner   = "BottomLeft",
        SilentAimStrength = 1.0,
        MagnetReach       = false,
        ReachRadius       = 18,
        NoFeintCooldown   = false,
        ShootRemoteName   = "Shoot",
        BallName          = "Ball",
    },
    Items = {
        BoxTeleport     = false,
        BoxTag          = "SkillBox",
        BoxPullMode     = "Teleport",
        BoxScanInterval = 0.5,
        SmartAutoUse    = false,
        AutoUseTrap     = false,
        AutoUseMagnet   = false,
        TrapItemName    = "Trap",
        MagnetItemName  = "Magnet",
        UseItemRemote   = "UseItem",
    },
    ESP = {
        ItemESP          = false,
        ESPMaxDistance   = 150,
        ShowBoxContents  = true,
        ShowEnemyItems   = true,
        BallTrajectory   = false,
        TrajectorySteps  = 60,
        TrajectoryColor  = Color3.fromRGB(255, 200, 0),
        CooldownTracker  = false,
        TrackerColor     = Color3.fromRGB(255, 80, 80),
    },
    Movement = {
        SpeedHack        = false,
        WalkSpeed        = 16,
        MaxWalkSpeed     = 120,
        JumpPower        = false,
        JumpHeight       = 50,
        MaxJumpHeight    = 200,
        SlideBoost       = false,
        SlideMultiplier  = 3.5,
    },
}

-- Baglanti Havuzu
local Connections = {}
local function AddConn(c) table.insert(Connections, c) end
local function DisconnectAll()
    for _, c in ipairs(Connections) do
        if c and c.Connected then pcall(c.Disconnect, c) end
    end
    table.clear(Connections)
end

-- ===============================================================
-- 3. YARDIMCILAR (UTILS)
-- ===============================================================
local function GetChar()
    return LocalPlayer and LocalPlayer.Character
end

local function GetRoot()
    local c = GetChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function GetHum()
    local c = GetChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function Clamp(v, mn, mx)
    return math.max(mn, math.min(mx, v))
end

local function Round(n, d)
    local f = 10 ^ (d or 0)
    return math.floor(n * f + 0.5) / f
end

local function GetNearestEnemy(radius)
    local root = GetRoot()
    if not root then return nil, math.huge end
    local pos, nearest, minD = root.Position, nil, radius or math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local c = p.Character
        if not c then continue end
        local r = c:FindFirstChild("HumanoidRootPart")
        local h = c:FindFirstChildOfClass("Humanoid")
        if r and h and h.Health > 0 then
            local d = (pos - r.Position).Magnitude
            if d < minD then minD = d; nearest = p end
        end
    end
    return nearest, minD
end

local function FindBall()
    local b = workspace:FindFirstChild(Config.Ball.BallName, true)
    if not b then
        local t = CollectionService:GetTagged("Ball")
        b = t[1]
    end
    return b
end

local function FindInWS(name)
    local res = {}
    for _, v in ipairs(workspace:GetDescendants()) do
        if v.Name == name then table.insert(res, v) end
    end
    for _, v in ipairs(CollectionService:GetTagged(name)) do
        table.insert(res, v)
    end
    return res
end

local function IsPlayingAnim(animator, idList)
    if not animator then return false end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local id = tostring(track.Animation.AnimationId)
        for _, chk in ipairs(idList) do
            if id == chk then return true end
        end
    end
    return false
end

local function StepPhysics(pos, vel, dt)
    local g  = -workspace.Gravity
    local nv = vel + Vector3.new(0, g, 0) * dt
    local np = pos + nv * dt
    return np, nv
end

local function GetGoalCorner(cornerName)
    local root = GetRoot()
    if not root then return nil end
    local goals = FindInWS("GoalPost")
    if #goals == 0 then goals = FindInWS("Goal") end
    if #goals == 0 then return nil end

    local best, bestD = nil, -math.huge
    for _, g in ipairs(goals) do
        local part = g:IsA("BasePart") and g or g:FindFirstChildOfClass("BasePart")
        if part then
            local d = (root.Position - part.Position).Magnitude
            if d > bestD then bestD = d; best = part end
        end
    end
    if not best then return nil end

    local sz = best.Size
    local cf = best.CFrame
    local offsets = {
        BottomLeft  = Vector3.new(-sz.X/2, -sz.Y/2, 0),
        BottomRight = Vector3.new( sz.X/2, -sz.Y/2, 0),
        TopLeft     = Vector3.new(-sz.X/2,  sz.Y/2, 0),
        TopRight    = Vector3.new( sz.X/2,  sz.Y/2, 0),
        Center      = Vector3.new(0, 0, 0),
    }
    local off = offsets[cornerName] or offsets.BottomLeft
    return (cf * CFrame.new(off)).Position
end

local _remoteCache = {}
local function GetRemote(name)
    if _remoteCache[name] then return _remoteCache[name] end
    local r = ReplicatedStorage:FindFirstChild(name, true)
    _remoteCache[name] = r
    return r
end

local function SafeFire(name, ...)
    local r = GetRemote(name)
    if r and r:IsA("RemoteEvent") then
        pcall(r.FireServer, r, ...)
        return true
    end
    return false
end

-- ===============================================================
-- 4. OYUN DONGULERI (COMBAT, BALL, ITEM, MOVEMENT, ESP)
-- ===============================================================

local _lastParry   = 0
local _lastTackle  = 0
local _lastKO      = 0
local _desyncDir   = Vector3.new(0, 0, 0)
local _desyncTimer = 0

local function GetBallOwner()
    local ball = FindBall()
    if not ball then return nil end
    local owner = ball:GetAttribute("Owner")
    if owner then return Players:FindFirstChild(owner) end
    local ballPos = ball:IsA("BasePart") and ball.Position or Vector3.new(0, 0, 0)
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local c = p.Character
        if c then
            local r = c:FindFirstChild("HumanoidRootPart")
            if r and (r.Position - ballPos).Magnitude < 3 then return p end
        end
    end
    return nil
end

-- RenderStepped
AddConn(RunService.RenderStepped:Connect(function(dt)
    local now = tick()

    -- Auto Parry
    if Config.Combat.AutoParry and now - _lastParry > Config.Combat.AutoParryDelay then
        local animIDs = {}
        for _, id in pairs(Config.Combat.ParryAnimIDs) do table.insert(animIDs, id) end
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LocalPlayer then continue end
            local c = p.Character
            if not c then continue end
            local root = c:FindFirstChild("HumanoidRootPart")
            local myRoot = GetRoot()
            if root and myRoot then
                if (myRoot.Position - root.Position).Magnitude <= Config.Combat.AutoParryRadius then
                    local h = c:FindFirstChildOfClass("Humanoid")
                    local a = h and h:FindFirstChildOfClass("Animator")
                    if a and IsPlayingAnim(a, animIDs) then
                        if SafeFire(Config.Combat.FeintRemoteName) then
                            _lastParry = now
                        end
                        break
                    end
                end
            end
        end
    end

    -- Anti-Tackle
    if Config.Combat.AntiTackle then
        local myRoot = GetRoot()
        if myRoot then
            _desyncTimer = _desyncTimer + dt
            if _desyncTimer >= 0.3 then
                _desyncTimer = 0
                local ang = math.random() * math.pi * 2
                _desyncDir = Vector3.new(
                    math.cos(ang) * Config.Combat.DesyncOffset,
                    0,
                    math.sin(ang) * Config.Combat.DesyncOffset
                )
            end
            myRoot.CFrame = myRoot.CFrame + _desyncDir
        end
    end
end))

-- Heartbeat
AddConn(RunService.Heartbeat:Connect(function()
    local now = tick()

    -- Auto Tackle
    if Config.Combat.AutoTackle and now - _lastTackle > Config.Combat.TackleDelay then
        local owner = GetBallOwner()
        if owner and owner ~= LocalPlayer then
            local c = owner.Character
            local myRoot = GetRoot()
            if c and myRoot then
                local r = c:FindFirstChild("HumanoidRootPart")
                if r and (myRoot.Position - r.Position).Magnitude <= Config.Combat.TackleRange then
                    myRoot.CFrame = CFrame.new(myRoot.Position, r.Position)
                    if SafeFire(Config.Combat.TackleRemoteName, owner) then
                        _lastTackle = now
                    end
                end
            end
        end
    end

    -- Auto KO
    if Config.Combat.AutoKnockout and now - _lastKO > Config.Combat.KODelay then
        local enemy = GetNearestEnemy(Config.Combat.KORange)
        if enemy then
            local c = enemy.Character
            local myRoot = GetRoot()
            if c and myRoot then
                local r = c:FindFirstChild("HumanoidRootPart")
                if r then
                    myRoot.CFrame = CFrame.new(myRoot.Position, r.Position)
                    if SafeFire(Config.Combat.PunchRemoteName, enemy) then
                        _lastKO = now
                    end
                end
            end
        end
    end

    -- Magnet Reach
    if Config.Ball.MagnetReach then
        local ball = FindBall()
        local myRoot = GetRoot()
        if ball and myRoot and ball:IsA("BasePart") then
            local dist = (myRoot.Position - ball.Position).Magnitude
            if dist < Config.Ball.ReachRadius and dist > 2 then
                local fwd = myRoot.CFrame.LookVector
                ball.CFrame = CFrame.new(myRoot.Position + fwd * 1.5 + Vector3.new(0, 0.5, 0))
                ball.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            end
        end
    end

    -- Movement
    local hum = GetHum()
    if hum then
        if Config.Movement.SpeedHack then
            hum.WalkSpeed = Clamp(Config.Movement.WalkSpeed, 0, Config.Movement.MaxWalkSpeed)
        end
        if Config.Movement.JumpPower then
            local h = Clamp(Config.Movement.JumpHeight, 0, Config.Movement.MaxJumpHeight)
            if hum.UseJumpPower then
                hum.JumpPower = math.sqrt(2 * workspace.Gravity * h)
            else
                hum.JumpHeight = h
            end
        end
    end
end))

-- Silent Aim
local function ApplySilentAim()
    local ball = FindBall()
    if not ball or not ball:IsA("BasePart") then return end
    local target = GetGoalCorner(Config.Ball.SilentAimCorner)
    if not target then return end
    local dir = (target - ball.Position).Unit
    local spd = ball.AssemblyLinearVelocity.Magnitude
    local s   = Clamp(Config.Ball.SilentAimStrength, 0, 1)
    local vy  = ball.AssemblyLinearVelocity.Y
    ball.AssemblyLinearVelocity = Vector3.new(dir.X * spd * s, vy, dir.Z * spd * s)
end

-- Kutu Tarama
local _boxActive = true
task.spawn(function()
    while _boxActive do
        if Config.Items.BoxTeleport then
            pcall(function()
                local myRoot = GetRoot()
                if not myRoot then return end
                local boxes = FindInWS(Config.Items.BoxTag)
                if #boxes == 0 then return end
                local nearest, minD = nil, math.huge
                for _, box in ipairs(boxes) do
                    local part = box:IsA("BasePart") and box or box:FindFirstChildOfClass("BasePart")
                    if part then
                        local d = (myRoot.Position - part.Position).Magnitude
                        if d < minD then minD = d; nearest = part end
                    end
                end
                if nearest then
                    if Config.Items.BoxPullMode == "Teleport" then
                        myRoot.CFrame = CFrame.new(nearest.Position + Vector3.new(0, 3, 0))
                    else
                        nearest.CFrame = CFrame.new(myRoot.Position + Vector3.new(0, 1, 0))
                        nearest.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                    end
                end
            end)
        end
        task.wait(Config.Items.BoxScanInterval)
    end
end)

-- Slide Boost
local _sliding = false
local function SetupSlideBoost()
    local hum = GetHum()
    if not hum then return end
    AddConn(hum.StateChanged:Connect(function(_, new)
        if not Config.Movement.SlideBoost then return end
        if new == Enum.HumanoidStateType.Freefall and not _sliding then
            _sliding = true
            local root = GetRoot()
            if root then
                local vel = root.AssemblyLinearVelocity
                local flat = Vector3.new(vel.X, 0, vel.Z)
                local dir  = flat.Magnitude > 0.5 and flat.Unit or root.CFrame.LookVector
                local spd  = (vel.Magnitude + 16) * Config.Movement.SlideMultiplier

                local lv = Instance.new("LinearVelocity")
                local att = root:FindFirstChildOfClass("Attachment") or Instance.new("Attachment", root)
                lv.Attachment0 = att
                lv.MaxForce = 1e6
                lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
                lv.VectorVelocity = dir * spd
                lv.RelativeTo = Enum.ActuatorRelativeTo.World
                lv.Parent = root
                task.delay(0.3, function() if lv and lv.Parent then lv:Destroy() end end)
            end
        elseif new == Enum.HumanoidStateType.Running then
            _sliding = false
        end
    end))
end
SetupSlideBoost()
AddConn(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1.5)
    _sliding = false
    SetupSlideBoost()
end))

-- ===============================================================
-- 5. ESP KATMANI
-- ===============================================================
local ESPGui do
    local ex = CoreGui:FindFirstChild("FU_ESP")
    if ex then ex:Destroy() end
    ESPGui = Instance.new("ScreenGui")
    ESPGui.Name = "FU_ESP"
    ESPGui.ResetOnSpawn = false
    ESPGui.IgnoreGuiInset = true
    ESPGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ESPGui.Parent = CoreGui
end

local _billboards = {}

local function GetOrCreateBB(key, adornee, size, studOffset, bgColor, textColor, textSize)
    if _billboards[key] and _billboards[key].Parent then
        return _billboards[key]
    end
    local bb = Instance.new("BillboardGui")
    bb.Name = "FU_" .. tostring(key)
    bb.Adornee = adornee
    bb.Size = size or UDim2.new(0, 170, 0, 40)
    bb.StudsOffset = studOffset or Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.Parent = ESPGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundColor3 = bgColor or Color3.fromRGB(15, 15, 30)
    frame.BackgroundTransparency = 0.35
    frame.BorderSizePixel = 0
    frame.Parent = bb
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)
    lbl.TextStrokeTransparency = 0.5
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = textSize or 12
    lbl.TextWrapped = true
    lbl.Text = ""
    lbl.Parent = frame

    _billboards[key] = bb
    return bb
end

local function SetBBText(bb, text)
    local f = bb:FindFirstChildOfClass("Frame")
    local l = f and f:FindFirstChildOfClass("TextLabel")
    if l then l.Text = text end
end

-- ESP RenderStepped
AddConn(RunService.RenderStepped:Connect(function()
    local myRoot = GetRoot()
    if Config.ESP.ItemESP and myRoot then
        if Config.ESP.ShowBoxContents then
            local boxes = FindInWS(Config.Items.BoxTag)
            for _, box in ipairs(boxes) do
                local part = box:IsA("BasePart") and box or box:FindFirstChildOfClass("BasePart")
                if part then
                    local dist = (myRoot.Position - part.Position).Magnitude
                    if dist <= Config.ESP.ESPMaxDistance then
                        local contents = box:GetAttribute("ItemType") or box:GetAttribute("Item") or "Kutu"
                        local key = "box_" .. tostring(box)
                        local bb = GetOrCreateBB(key, part, UDim2.new(0, 150, 0, 34), Vector3.new(0, 3, 0), Color3.fromRGB(25, 25, 55), Color3.fromRGB(255, 220, 80), 12)
                        bb.Enabled = true
                        SetBBText(bb, string.format("📦 %s\n%.0f studs", tostring(contents), dist))
                    end
                end
            end
        end

        if Config.ESP.ShowEnemyItems then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    local r = player.Character:FindFirstChild("HumanoidRootPart")
                    if r then
                        local dist = (myRoot.Position - r.Position).Magnitude
                        if dist <= Config.ESP.ESPMaxDistance then
                            local inv = player.Character:GetAttribute("Inventory") or "?"
                            local key = "pl_" .. player.Name
                            local bb = GetOrCreateBB(key, r, UDim2.new(0, 160, 0, 38), Vector3.new(0, 3.5, 0), Color3.fromRGB(15, 25, 65), Color3.fromRGB(180, 220, 255), 11)
                            bb.Enabled = true
                            SetBBText(bb, "👤 " .. player.Name .. "\n🎒 " .. tostring(inv))
                        end
                    end
                end
            end
        end
    else
        for _, bb in pairs(_billboards) do
            if bb and bb.Parent then bb.Enabled = false end
        end
    end
end))

-- ===============================================================
-- 6. GUI (MOBIL UYUMLU, %100 CALISAN SCROLL VE BUTON SISTEMI)
-- ===============================================================

local THEME = {
    BG         = Color3.fromRGB(16, 16, 22),
    Surface    = Color3.fromRGB(24, 24, 34),
    SurfaceAlt = Color3.fromRGB(30, 30, 44),
    Accent     = Color3.fromRGB(70, 130, 255),
    AccentGlow = Color3.fromRGB(90, 150, 255),
    ON         = Color3.fromRGB(46, 204, 113),
    OFF        = Color3.fromRGB(75, 75, 95),
    TextMain   = Color3.fromRGB(245, 245, 255),
    TextSub    = Color3.fromRGB(160, 160, 190),
    Border     = Color3.fromRGB(55, 55, 75),
    Danger     = Color3.fromRGB(231, 76, 60),
}

-- Guvenli Ekran Boyutlandirmasi
local viewSize = (Camera and Camera.ViewportSize.X > 100) and Camera.ViewportSize or Vector2.new(800, 600)
local WIN_W = IS_MOBILE and math.clamp(viewSize.X - 30, 320, 520) or 540
local WIN_H = IS_MOBILE and math.clamp(viewSize.Y - 50, 280, 420) or 430
local TAB_W = IS_MOBILE and 100 or 120

local function MI(cls, props, parent)
    local inst = Instance.new(cls)
    for k, v in pairs(props) do inst[k] = v end
    inst.Parent = parent
    return inst
end

local function Corner(p, r)
    return MI("UICorner", { CornerRadius = UDim.new(0, r or 6) }, p)
end

local function Padding(p, t, b, l, r)
    return MI("UIPadding", {
        PaddingTop = UDim.new(0, t or 6),
        PaddingBottom = UDim.new(0, b or 6),
        PaddingLeft = UDim.new(0, l or 8),
        PaddingRight = UDim.new(0, r or 8)
    }, p)
end

-- Ana GUI
local guiRoot do
    local ex = CoreGui:FindFirstChild("FU_GUI")
    if ex then ex:Destroy() end
    guiRoot = MI("ScreenGui", {
        Name = "FU_GUI",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
    }, CoreGui)
end

-- 📱 MOBIL FLOATING BUTON (Pencereyi acip kapatmak icin)
local floatBtn = MI("TextButton", {
    Name = "FloatToggle",
    Size = UDim2.new(0, 44, 0, 44),
    Position = UDim2.new(0, 16, 0.5, -22),
    BackgroundColor3 = THEME.Accent,
    Text = "⚽",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    BorderSizePixel = 0,
    ZIndex = 999,
}, guiRoot)
Corner(floatBtn, 22)
MI("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = 1.5, Transparency = 0.3 }, floatBtn)

-- Floating butonu surukleme
do
    local dragging, dragStart, startPos = false, nil, nil
    floatBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = floatBtn.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            floatBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    local function stopDrag() dragging = false end
    floatBtn.InputEnded:Connect(stopDrag)
    UserInputService.InputEnded:Connect(stopDrag)
end

-- Ana Cerceve
local mainFrame = MI("Frame", {
    Name = "MainFrame",
    Size = UDim2.new(0, WIN_W, 0, WIN_H),
    Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
    BackgroundColor3 = THEME.BG,
    BorderSizePixel = 0,
    ClipsDescendants = false,
}, guiRoot)
Corner(mainFrame, 10)
MI("UIStroke", { Color = THEME.Border, Thickness = 1.2 }, mainFrame)

-- Float butonuna basinca ac/kapat
floatBtn.MouseButton1Click:Connect(function()
    mainFrame.Visible = not mainFrame.Visible
end)

-- Baslik Cubugu
local titleBar = MI("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 44),
    BackgroundColor3 = THEME.Surface,
    BorderSizePixel = 0,
}, mainFrame)
Corner(titleBar, 10)
MI("Frame", { Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = THEME.Surface, BorderSizePixel = 0 }, titleBar)
MI("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), BackgroundColor3 = THEME.Accent, BorderSizePixel = 0 }, titleBar)

MI("TextLabel", {
    Size = UDim2.new(1, -90, 1, 0),
    Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1,
    Text = "⚽ FutbolUmsu  v1.0 (Mobile Ready)",
    TextColor3 = THEME.TextMain,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)

-- Kapat / Gizle Butonu
local closeBtn = MI("TextButton", {
    Size = UDim2.new(0, 32, 0, 32),
    Position = UDim2.new(1, -38, 0.5, -16),
    BackgroundColor3 = THEME.Danger,
    BackgroundTransparency = 0.2,
    Text = "✕",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    BorderSizePixel = 0,
}, titleBar)
Corner(closeBtn, 6)
closeBtn.MouseButton1Click:Connect(function()
    mainFrame.Visible = false
end)

-- TitleBar Drag
do
    local dragging, dragStart, startPos = false, nil, nil
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    local function stopDrag() dragging = false end
    titleBar.InputEnded:Connect(stopDrag)
    UserInputService.InputEnded:Connect(stopDrag)
end

-- Sol Sekme Alani
local tabBar = MI("Frame", {
    Name = "TabBar",
    Size = UDim2.new(0, TAB_W, 1, -44),
    Position = UDim2.new(0, 0, 0, 44),
    BackgroundColor3 = THEME.Surface,
    BorderSizePixel = 0,
}, mainFrame)
MI("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = THEME.Border, BorderSizePixel = 0 }, tabBar)

local tabList = MI("ScrollingFrame", {
    Name = "TabList",
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 2,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(0, 0, 0, 240), -- Garanti Canvas
}, tabBar)
Padding(tabList, 8, 8, 6, 6)
local tabListLayout = MI("UIListLayout", {
    FillDirection = Enum.FillDirection.Vertical,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 6),
}, tabList)

-- Sag Icerik Alani
local contentArea = MI("Frame", {
    Name = "ContentArea",
    Size = UDim2.new(1, -TAB_W, 1, -44),
    Position = UDim2.new(0, TAB_W, 0, 44),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, mainFrame)

-- Sekme Yonetimi
local Tabs = {}
local CurrentTab = nil

local function SelectTab(name)
    if CurrentTab and Tabs[CurrentTab] then
        Tabs[CurrentTab].page.Visible = false
        Tabs[CurrentTab].btn.BackgroundColor3 = THEME.SurfaceAlt
        Tabs[CurrentTab].btn.TextColor3 = THEME.TextSub
    end
    CurrentTab = name
    if Tabs[name] then
        Tabs[name].page.Visible = true
        Tabs[name].btn.BackgroundColor3 = THEME.Accent
        Tabs[name].btn.TextColor3 = THEME.TextMain
    end
end

local function CreateTab(name, icon)
    local btn = MI("TextButton", {
        Name = "TabBtn_" .. name,
        Size = UDim2.new(1, 0, 0, IS_MOBILE and 42 or 36),
        BackgroundColor3 = THEME.SurfaceAlt,
        Text = (icon and icon .. " " or "") .. name,
        TextColor3 = THEME.TextSub,
        Font = Enum.Font.GothamBold,
        TextSize = IS_MOBILE and 12 or 11,
        BorderSizePixel = 0,
        AutoButtonColor = false,
    }, tabList)
    Corner(btn, 6)

    local page = MI("ScrollingFrame", {
        Name = "Page_" .. name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = THEME.Accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(0, 0, 0, 600), -- Garanti Canvas boyutu
        Visible = false,
    }, contentArea)
    Padding(page, 10, 16, 10, 10)
    local pageLayout = MI("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
    }, page)

    pageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0, 0, 0, pageLayout.AbsoluteContentSize.Y + 40)
    end)

    btn.MouseButton1Click:Connect(function()
        SelectTab(name)
    end)

    local tabObj = {
        name = name,
        btn = btn,
        page = page,
        totalH = 0,
    }

    function tabObj:AddSection(title)
        local sec = MI("Frame", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundTransparency = 1,
        }, self.page)
        MI("TextLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = THEME.AccentGlow,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, sec)
        MI("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            Position = UDim2.new(0, 0, 1, -1),
            BackgroundColor3 = THEME.Accent,
            BackgroundTransparency = 0.6,
            BorderSizePixel = 0,
        }, sec)
        self.totalH = self.totalH + 34
        self.page.CanvasSize = UDim2.new(0, 0, 0, self.totalH + 60)
    end

    function tabObj:AddToggle(title, defaultVal, callback, desc)
        local state = defaultVal or false
        local rowH = desc and (IS_MOBILE and 56 or 48) or (IS_MOBILE and 44 or 38)

        local row = MI("Frame", {
            Size = UDim2.new(1, 0, 0, rowH),
            BackgroundColor3 = THEME.SurfaceAlt,
            BorderSizePixel = 0,
        }, self.page)
        Corner(row, 6)
        Padding(row, 6, 6, 10, 10)

        MI("TextLabel", {
            Size = UDim2.new(1, -60, 0, 18),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = THEME.TextMain,
            Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 13 or 12,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)

        if desc then
            MI("TextLabel", {
                Size = UDim2.new(1, -60, 0, 14),
                Position = UDim2.new(0, 0, 0, 20),
                BackgroundTransparency = 1,
                Text = desc,
                TextColor3 = THEME.TextSub,
                Font = Enum.Font.Gotham,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
            }, row)
        end

        local trackW = 46
        local trackH = 24
        local track = MI("Frame", {
            Size = UDim2.new(0, trackW, 0, trackH),
            Position = UDim2.new(1, -trackW, 0.5, -trackH / 2),
            BackgroundColor3 = state and THEME.ON or THEME.OFF,
            BorderSizePixel = 0,
        }, row)
        Corner(track, trackH / 2)

        local knobSize = trackH - 4
        local knob = MI("Frame", {
            Size = UDim2.new(0, knobSize, 0, knobSize),
            Position = state and UDim2.new(0, trackW - knobSize - 2, 0.5, -knobSize / 2) or UDim2.new(0, 2, 0.5, -knobSize / 2),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
        }, track)
        Corner(knob, knobSize / 2)

        local clickBtn = MI("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 10,
        }, row)

        local function Toggle(v)
            state = v
            TweenService:Create(track, TweenInfo.new(0.15), { BackgroundColor3 = state and THEME.ON or THEME.OFF }):Play()
            TweenService:Create(knob, TweenInfo.new(0.15), { Position = state and UDim2.new(0, trackW - knobSize - 2, 0.5, -knobSize / 2) or UDim2.new(0, 2, 0.5, -knobSize / 2) }):Play()
            pcall(callback, state)
        end

        clickBtn.MouseButton1Click:Connect(function()
            Toggle(not state)
        end)

        self.totalH = self.totalH + rowH + 8
        self.page.CanvasSize = UDim2.new(0, 0, 0, self.totalH + 60)
        return { Set = Toggle }
    end

    function tabObj:AddSlider(title, minVal, maxVal, defaultVal, callback, suffix)
        suffix = suffix or ""
        local val = math.clamp(defaultVal or minVal, minVal, maxVal)
        local rowH = IS_MOBILE and 58 or 52

        local row = MI("Frame", {
            Size = UDim2.new(1, 0, 0, rowH),
            BackgroundColor3 = THEME.SurfaceAlt,
            BorderSizePixel = 0,
        }, self.page)
        Corner(row, 6)
        Padding(row, 8, 8, 10, 10)

        local header = MI("Frame", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
        }, row)
        MI("TextLabel", {
            Size = UDim2.new(0.65, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = THEME.TextMain,
            Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 13 or 12,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, header)
        local valLbl = MI("TextLabel", {
            Size = UDim2.new(0.35, 0, 1, 0),
            Position = UDim2.new(0.65, 0, 0, 0),
            BackgroundTransparency = 1,
            Text = tostring(val) .. suffix,
            TextColor3 = THEME.AccentGlow,
            Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 13 or 12,
            TextXAlignment = Enum.TextXAlignment.Right,
        }, header)

        local trackH = 8
        local track = MI("Frame", {
            Size = UDim2.new(1, 0, 0, trackH),
            Position = UDim2.new(0, 0, 0, 26),
            BackgroundColor3 = Color3.fromRGB(45, 45, 60),
            BorderSizePixel = 0,
        }, row)
        Corner(track, 4)

        local fill = MI("Frame", {
            Size = UDim2.new((val - minVal) / (maxVal - minVal), 0, 1, 0),
            BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0,
        }, track)
        Corner(fill, 4)

        local thumbSize = 16
        local thumb = MI("Frame", {
            Size = UDim2.new(0, thumbSize, 0, thumbSize),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new((val - minVal) / (maxVal - minVal), 0, 0.5, 0),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
            ZIndex = 3,
        }, track)
        Corner(thumb, 8)

        local hitArea = MI("TextButton", {
            Size = UDim2.new(1, 0, 0, 30),
            Position = UDim2.new(0, 0, 0, -11),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 10,
        }, track)

        local sliding = false
        local function UpdateSlider(inputX)
            local t = math.clamp((inputX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            local step = (maxVal - minVal) <= 10 and 0.1 or 1
            val = math.floor((minVal + (maxVal - minVal) * t) / step + 0.5) * step
            val = math.clamp(val, minVal, maxVal)
            fill.Size = UDim2.new(t, 0, 1, 0)
            thumb.Position = UDim2.new(t, 0, 0.5, 0)
            valLbl.Text = tostring(Round(val, 1)) .. suffix
            pcall(callback, val)
        end

        hitArea.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                sliding = true
                UpdateSlider(input.Position.X)
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                sliding = false
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                UpdateSlider(input.Position.X)
            end
        end)

        self.totalH = self.totalH + rowH + 8
        self.page.CanvasSize = UDim2.new(0, 0, 0, self.totalH + 60)
    end

    function tabObj:AddButton(title, callback)
        local rowH = IS_MOBILE and 40 or 34
        local btn = MI("TextButton", {
            Size = UDim2.new(1, 0, 0, rowH),
            BackgroundColor3 = THEME.Accent,
            BackgroundTransparency = 0.25,
            Text = title,
            TextColor3 = THEME.TextMain,
            Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 13 or 12,
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, self.page)
        Corner(btn, 6)
        btn.MouseButton1Click:Connect(function()
            pcall(callback)
        end)

        self.totalH = self.totalH + rowH + 8
        self.page.CanvasSize = UDim2.new(0, 0, 0, self.totalH + 60)
    end

    function tabObj:AddDropdown(title, options, defaultVal, callback)
        local sel = defaultVal or options[1]
        local rowH = IS_MOBILE and 42 or 36

        local row = MI("Frame", {
            Size = UDim2.new(1, 0, 0, rowH),
            BackgroundColor3 = THEME.SurfaceAlt,
            BorderSizePixel = 0,
            ZIndex = 5,
        }, self.page)
        Corner(row, 6)
        Padding(row, 0, 0, 10, 10)

        MI("TextLabel", {
            Size = UDim2.new(0.55, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = THEME.TextMain,
            Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 13 or 12,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)

        local curLbl = MI("TextLabel", {
            Size = UDim2.new(0.45, 0, 1, 0),
            Position = UDim2.new(0.55, 0, 0, 0),
            BackgroundTransparency = 1,
            Text = "▼ " .. tostring(sel),
            TextColor3 = THEME.AccentGlow,
            Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 12 or 11,
            TextXAlignment = Enum.TextXAlignment.Right,
        }, row)

        local dropPanel = MI("Frame", {
            Size = UDim2.new(1, 0, 0, #options * 30 + 8),
            Position = UDim2.new(0, 0, 1, 4),
            BackgroundColor3 = THEME.Surface,
            BorderSizePixel = 0,
            ZIndex = 20,
            Visible = false,
        }, row)
        Corner(dropPanel, 6)
        MI("UIStroke", { Color = THEME.Border, Thickness = 1 }, dropPanel)
        Padding(dropPanel, 4, 4, 4, 4)
        MI("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 2) }, dropPanel)

        for _, opt in ipairs(options) do
            local ob = MI("TextButton", {
                Size = UDim2.new(1, 0, 0, 28),
                BackgroundColor3 = THEME.SurfaceAlt,
                BackgroundTransparency = 0.5,
                Text = tostring(opt),
                TextColor3 = THEME.TextSub,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                BorderSizePixel = 0,
                ZIndex = 21,
            }, dropPanel)
            Corner(ob, 4)
            ob.MouseButton1Click:Connect(function()
                sel = opt
                curLbl.Text = "▼ " .. tostring(opt)
                dropPanel.Visible = false
                pcall(callback, opt)
            end)
        end

        local toggleDrop = MI("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 6,
        }, row)
        toggleDrop.MouseButton1Click:Connect(function()
            dropPanel.Visible = not dropPanel.Visible
        end)

        self.totalH = self.totalH + rowH + 8
        self.page.CanvasSize = UDim2.new(0, 0, 0, self.totalH + 60)
    end

    Tabs[name] = tabObj
    if not CurrentTab then
        SelectTab(name)
    end
    return tabObj
end

-- ===============================================================
-- 7. SEKME VE ELEMANLARI EKLEME
-- ===============================================================

-- 1. COMBAT
local tCombat = CreateTab("Combat", "⚔️")
tCombat:AddSection("🥊 Dövüş Otomasyonu")
tCombat:AddToggle("Auto Parry", Config.Combat.AutoParry, function(v) Config.Combat.AutoParry = v end, "Vurma animasyonunda otomatik Feint")
tCombat:AddSlider("Parry Menzili", 4, 30, Config.Combat.AutoParryRadius, function(v) Config.Combat.AutoParryRadius = v end, " studs")
tCombat:AddSlider("Parry Gecikmesi", 0.0, 0.5, Config.Combat.AutoParryDelay, function(v) Config.Combat.AutoParryDelay = v end, "s")
tCombat:AddSection("🏃 Tackle & Kayma")
tCombat:AddToggle("Auto Tackle", Config.Combat.AutoTackle, function(v) Config.Combat.AutoTackle = v end, "Top rakipteyken otomatik kayma")
tCombat:AddSlider("Tackle Menzili", 3, 25, Config.Combat.TackleRange, function(v) Config.Combat.TackleRange = v end, " studs")
tCombat:AddSection("👊 Knockout & Savunma")
tCombat:AddToggle("Auto Knockout", Config.Combat.AutoKnockout, function(v) Config.Combat.AutoKnockout = v end, "Menzildeki rakibe sürekli yumruk")
tCombat:AddSlider("KO Menzili", 3, 20, Config.Combat.KORange, function(v) Config.Combat.KORange = v end, " studs")
tCombat:AddSlider("KO Aralığı", 0.05, 1.0, Config.Combat.KODelay, function(v) Config.Combat.KODelay = v end, "s")
tCombat:AddToggle("Anti-Tackle (Desync)", Config.Combat.AntiTackle, function(v) Config.Combat.AntiTackle = v end, "Hitbox kaydırma ile korunma")
tCombat:AddSlider("Desync Ofseti", 1, 8, Config.Combat.DesyncOffset, function(v) Config.Combat.DesyncOffset = v end, " studs")

-- 2. BALL / GOAL
local tBall = CreateTab("Ball", "⚽")
tBall:AddSection("🎯 Şut Yönlendirme (Silent Aim)")
tBall:AddToggle("Silent Aim", Config.Ball.SilentAim, function(v) Config.Ball.SilentAim = v end, "Topu boş köşeye yönlendir")
tBall:AddDropdown("Hedef Köşe", { "BottomLeft", "BottomRight", "TopLeft", "TopRight", "Center" }, Config.Ball.SilentAimCorner, function(v) Config.Ball.SilentAimCorner = v end)
tBall:AddSlider("Aim Gücü", 0.1, 1.0, Config.Ball.SilentAimStrength, function(v) Config.Ball.SilentAimStrength = v end, "x")
tBall:AddButton("⚽ Manuel Aim Uygula", function() pcall(ApplySilentAim) end)
tBall:AddSection("🧲 Top Mıknatısı")
tBall:AddToggle("Magnet Reach", Config.Ball.MagnetReach, function(v) Config.Ball.MagnetReach = v end, "Topu önünüze çeker")
tBall:AddSlider("Reach Menzili", 5, 50, Config.Ball.ReachRadius, function(v) Config.Ball.ReachRadius = v end, " studs")
tBall:AddToggle("No Feint Cooldown", Config.Ball.NoFeintCooldown, function(v) Config.Ball.NoFeintCooldown = v end, "Çalım bekleme süresini sıfırla")

-- 3. ITEMS / ESP
local tItems = CreateTab("Items", "📦")
tItems:AddSection("📦 Kutu Toplama")
tItems:AddToggle("Box Auto-Collect", Config.Items.BoxTeleport, function(v) Config.Items.BoxTeleport = v end, "Kutulara otomatik git")
tItems:AddDropdown("Toplama Modu", { "Teleport", "Pull" }, Config.Items.BoxPullMode, function(v) Config.Items.BoxPullMode = v end)
tItems:AddSlider("Tarama Aralığı", 0.1, 3.0, Config.Items.BoxScanInterval, function(v) Config.Items.BoxScanInterval = v end, "s")
tItems:AddSection("🤖 Akıllı Eşya")
tItems:AddToggle("Smart Auto-Use", Config.Items.SmartAutoUse, function(v) Config.Items.SmartAutoUse = v end)
tItems:AddToggle("  ↳ Otomatik Tuzak", Config.Items.AutoUseTrap, function(v) Config.Items.AutoUseTrap = v end)
tItems:AddToggle("  ↳ Otomatik Mıknatıs", Config.Items.AutoUseMagnet, function(v) Config.Items.AutoUseMagnet = v end)
tItems:AddSection("👁️ Görsel (ESP)")
tItems:AddToggle("Item & Kutu ESP", Config.ESP.ItemESP, function(v) Config.ESP.ItemESP = v end)
tItems:AddToggle("  ↳ Kutu İçeriklerini Göster", Config.ESP.ShowBoxContents, function(v) Config.ESP.ShowBoxContents = v end)
tItems:AddToggle("  ↳ Rakip Envanterini Göster", Config.ESP.ShowEnemyItems, function(v) Config.ESP.ShowEnemyItems = v end)
tItems:AddSlider("ESP Görüş Mesafesi", 30, 300, Config.ESP.ESPMaxDistance, function(v) Config.ESP.ESPMaxDistance = v end, " studs")
tItems:AddToggle("Top Tahmin Çizgisi", Config.ESP.BallTrajectory, function(v) Config.ESP.BallTrajectory = v end)
tItems:AddToggle("Rakip Cooldown Takip", Config.ESP.CooldownTracker, function(v) Config.ESP.CooldownTracker = v end)

-- 4. MOVEMENT
local tMove = CreateTab("Move", "🏃")
tMove:AddSection("⚡ Hız & Zıplama")
tMove:AddToggle("Speed Hack", Config.Movement.SpeedHack, function(v) Config.Movement.SpeedHack = v end)
tMove:AddSlider("Yürüme Hızı", 16, 120, Config.Movement.WalkSpeed, function(v) Config.Movement.WalkSpeed = v end, " ws")
tMove:AddToggle("Jump Power", Config.Movement.JumpPower, function(v) Config.Movement.JumpPower = v end)
tMove:AddSlider("Zıplama Yüksekliği", 7, 200, Config.Movement.JumpHeight, function(v) Config.Movement.JumpHeight = v end, " studs")
tMove:AddSection("💨 Kayma Boost")
tMove:AddToggle("Slide Velocity Boost", Config.Movement.SlideBoost, function(v) Config.Movement.SlideBoost = v end, "Kayarken ekstra hız ivmesi")
tMove:AddSlider("Slide Çarpanı", 1.0, 8.0, Config.Movement.SlideMultiplier, function(v) Config.Movement.SlideMultiplier = v end, "x")
tMove:AddButton("💨 Anlık Slide Boost Uygula", function()
    local root = GetRoot()
    if not root then return end
    local vel = root.AssemblyLinearVelocity
    local flat = Vector3.new(vel.X, 0, vel.Z)
    local dir  = flat.Magnitude > 0.5 and flat.Unit or root.CFrame.LookVector
    local spd  = (vel.Magnitude + 16) * Config.Movement.SlideMultiplier
    local lv = Instance.new("LinearVelocity")
    local att = root:FindFirstChildOfClass("Attachment") or Instance.new("Attachment", root)
    lv.Attachment0 = att
    lv.MaxForce = 1e6
    lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    lv.VectorVelocity = dir * spd
    lv.RelativeTo = Enum.ActuatorRelativeTo.World
    lv.Parent = root
    task.delay(0.3, function() if lv and lv.Parent then lv:Destroy() end end)
end)

-- Varsayilan acilis
SelectTab("Combat")

-- Temizlik Fonksiyonu
local function FullCleanup()
    _boxActive = false
    DisconnectAll()
    pcall(function() ESPGui:Destroy() end)
    pcall(function() guiRoot:Destroy() end)
    local hum = GetHum()
    if hum then hum.WalkSpeed = 16; hum.JumpHeight = 7.2 end
    print("[FutbolUmsu] Kapatıldı ve temizlendi.")
end

if getgenv then
    getgenv()._FU_Loaded = true
    getgenv()._FU_Stop   = FullCleanup
    getgenv()._FU_Config = Config
end

print("=================================================")
print("  ⚽ FutbolUmsu v1.0 Mobile Full Fix Yüklendi!")
print("  📱 Sol taraftaki ⚽ butonuna basarak paneli aç/kapat!")
print("=================================================")
