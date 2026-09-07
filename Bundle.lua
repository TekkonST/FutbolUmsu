--[[
╔══════════════════════════════════════════════════════════════╗
║          FutbolUmsu · Bundle.lua (TEK DOSYA)                ║
║  Mobil + Masaüstü · Executor uyumlu                         ║
║  Delta X · Arceus X · Hydrogen · Fluxus · KRNL destekli     ║
║                                                              ║
║  KULLANIM (executor'da):                                     ║
║    loadstring(game:HttpGet("RAW_GITHUB_LINKIN"))()           ║
╚══════════════════════════════════════════════════════════════╝
--]]

-- ──────────────────────────────────────────────────────────────
--  KORUMA: Yeniden yüklemede temizlik
-- ──────────────────────────────────────────────────────────────
if getgenv and getgenv()._FU_Loaded then
    if getgenv()._FU_Stop then
        pcall(getgenv()._FU_Stop)
    end
    task.wait(0.2)
end

-- ──────────────────────────────────────────────────────────────
--  SERVİSLER
-- ──────────────────────────────────────────────────────────────
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local CollectionService= game:GetService("CollectionService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- Mobil mi?
local IS_MOBILE   = UserInputService.TouchEnabled

-- ──────────────────────────────────────────────────────────────
--  MERKEZİ YAPILANDIRMA (Config)
-- ──────────────────────────────────────────────────────────────
local Config = {
    Combat = {
        AutoParry        = false,
        AutoParryRadius  = 12,
        AutoParryDelay   = 0.05,
        AutoTackle       = false,
        TackleRange      = 10,
        TackleDelay      = 0.1,
        AutoKnockout     = false,
        KORange          = 8,
        KODelay          = 0.15,
        AntiTackle       = false,
        DesyncOffset     = 3.5,
        -- ⬇️ OYUNA ÖZEL: Remote adlarını buradan değiştir
        ParryAnimIDs     = {
            ["punch"] = "rbxassetid://000000001",
            ["slide"] = "rbxassetid://000000002",
        },
        FeintRemoteName  = "BodyFeint",
        TackleRemoteName = "Tackle",
        PunchRemoteName  = "Punch",
    },
    Ball = {
        SilentAim           = false,
        SilentAimCorner     = "BottomLeft",
        SilentAimStrength   = 1.0,
        MagnetReach         = false,
        ReachRadius         = 18,
        NoFeintCooldown     = false,
        ShootRemoteName     = "Shoot",
        BallName            = "Ball",   -- ⬅️ Workspace'teki top adı
    },
    Items = {
        BoxTeleport     = false,
        BoxTag          = "SkillBox",   -- ⬅️ Kutu adı/tag'i
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

-- ──────────────────────────────────────────────────────────────
--  BAĞLANTI HAVUZU
-- ──────────────────────────────────────────────────────────────
local Connections = {}
local function AddConn(c) table.insert(Connections, c) end
local function DisconnectAll()
    for _, c in ipairs(Connections) do
        if c and c.Connected then pcall(c.Disconnect, c) end
    end
    table.clear(Connections)
end

-- ──────────────────────────────────────────────────────────────
--  YARDIMCI FONKSİYONLAR
-- ──────────────────────────────────────────────────────────────

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

local function GetAnimator()
    local h = GetHum()
    return h and h:FindFirstChildOfClass("Animator")
end

local function Clamp(v, mn, mx)
    return math.max(mn, math.min(mx, v))
end

local function Round(n, d)
    local f = 10^(d or 0)
    return math.floor(n * f + 0.5) / f
end

-- En yakın düşman
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

-- Top bul
local function FindBall()
    local b = workspace:FindFirstChild(Config.Ball.BallName, true)
    if not b then
        local t = CollectionService:GetTagged("Ball")
        b = t[1]
    end
    return b
end

-- Workspace'te ada/tag ile bul
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

-- Animasyon ID kontrolü
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

-- Verlet fizik adımı
local function StepPhysics(pos, vel, dt)
    local g   = -workspace.Gravity
    local nv  = vel + Vector3.new(0, g, 0) * dt
    local np  = pos + nv * dt
    return np, nv
end

-- Hedef kale köşesi
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

-- Remote cache + safe fire
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

-- ══════════════════════════════════════════════════════════════
--  MODÜL 1 · COMBAT
-- ══════════════════════════════════════════════════════════════

local _lastParry   = 0
local _lastTackle  = 0
local _lastKO      = 0
local _desyncDir   = Vector3.new(0,0,0)
local _desyncTimer = 0

local function GetBallOwner()
    local ball = FindBall()
    if not ball then return nil end
    local owner = ball:GetAttribute("Owner")
    if owner then return Players:FindFirstChild(owner) end
    local ballPos = ball:IsA("BasePart") and ball.Position or Vector3.new(0,0,0)
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

-- RenderStepped: Auto Parry + Anti Tackle
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
            if not root then continue end
            local myRoot = GetRoot()
            if not myRoot then break end
            if (myRoot.Position - root.Position).Magnitude > Config.Combat.AutoParryRadius then continue end
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

    -- Anti Tackle / Desync
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

-- Heartbeat: Auto Tackle + Auto KO
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
end))

-- ══════════════════════════════════════════════════════════════
--  MODÜL 2 · BALL CONTROL
-- ══════════════════════════════════════════════════════════════

-- Silent Aim: Shoot Remote hook (RemoteSpy yoksa Heartbeat ile)
local function ApplySilentAim()
    local ball = FindBall()
    if not ball or not ball:IsA("BasePart") then return end
    local target = GetGoalCorner(Config.Ball.SilentAimCorner)
    if not target then return end
    local dir = (target - ball.Position).Unit
    local spd = ball.AssemblyLinearVelocity.Magnitude
    local s   = Clamp(Config.Ball.SilentAimStrength, 0, 1)
    local vy  = ball.AssemblyLinearVelocity.Y
    ball.AssemblyLinearVelocity = Vector3.new(dir.X*spd*s, vy, dir.Z*spd*s)
end

-- Magnet Reach + Silent Aim post-hook
AddConn(RunService.Heartbeat:Connect(function()
    -- Magnet Reach
    if Config.Ball.MagnetReach then
        local ball   = FindBall()
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

    -- No Feint Cooldown (getgenv yöntemi)
    if Config.Ball.NoFeintCooldown and getgenv then
        local env = getgenv()
        if env._feintCooldown ~= nil then env._feintCooldown = 0 end
        if env.feintCooldown  ~= nil then env.feintCooldown  = 0 end
    end
end))

-- __namecall hook (Shoot Remote yakalamak için)
pcall(function()
    if not getrawmetatable then return end
    local mt = getrawmetatable(game)
    if setreadonly then setreadonly(mt, false) end
    local origNC = mt.__namecall
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer"
            and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction"))
            and self.Name == Config.Ball.ShootRemoteName
        then
            if Config.Ball.SilentAim then
                task.delay(0.03, ApplySilentAim)
            end
        end
        return origNC(self, ...)
    end)
    if setreadonly then setreadonly(mt, true) end
end)

-- ══════════════════════════════════════════════════════════════
--  MODÜL 3 · ITEM AUTOMATION
-- ══════════════════════════════════════════════════════════════

-- Box Teleport döngüsü
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
                        nearest.AssemblyLinearVelocity = Vector3.new(0,0,0)
                    end
                end
            end)
        end
        task.wait(Config.Items.BoxScanInterval)
    end
end)

-- Smart Auto-Use
local _lastItemUse = 0
AddConn(RunService.Heartbeat:Connect(function()
    if not Config.Items.SmartAutoUse then return end
    if tick() - _lastItemUse < 0.8 then return end

    local myRoot = GetRoot()
    if not myRoot then return end

    -- Arkadan yaklaşan düşman → tuzak
    if Config.Items.AutoUseTrap then
        local back = -myRoot.CFrame.LookVector
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LocalPlayer then continue end
            local c = p.Character
            if not c then continue end
            local r = c:FindFirstChild("HumanoidRootPart")
            if r then
                local toEnemy = (r.Position - myRoot.Position)
                if toEnemy.Magnitude < 12 and toEnemy.Unit:Dot(back) > 0.5 then
                    if SafeFire(Config.Items.UseItemRemote, Config.Items.TrapItemName) then
                        _lastItemUse = tick()
                    end
                    return
                end
            end
        end
    end

    -- Top kayıp → mıknatıs
    if Config.Items.AutoUseMagnet then
        local ball = FindBall()
        if ball and ball:IsA("BasePart") then
            local dist = (myRoot.Position - ball.Position).Magnitude
            if dist > 3 then
                if SafeFire(Config.Items.UseItemRemote, Config.Items.MagnetItemName) then
                    _lastItemUse = tick()
                end
            end
        end
    end
end))

-- ══════════════════════════════════════════════════════════════
--  MODÜL 4 · ESP
-- ══════════════════════════════════════════════════════════════

-- ESP ScreenGui
local ESPGui do
    local ex = CoreGui:FindFirstChild("FU_ESP")
    if ex then ex:Destroy() end
    ESPGui = Instance.new("ScreenGui")
    ESPGui.Name          = "FU_ESP"
    ESPGui.ResetOnSpawn  = false
    ESPGui.IgnoreGuiInset= true
    ESPGui.ZIndexBehavior= Enum.ZIndexBehavior.Sibling
    ESPGui.Parent        = CoreGui
end

local _billboards = {}  -- key→BillboardGui

local function GetOrCreateBB(key, adornee, size, studOffset, bgColor, textColor, textSize)
    if _billboards[key] and _billboards[key].Parent then
        return _billboards[key]
    end
    local bb = Instance.new("BillboardGui")
    bb.Name          = "FU_" .. tostring(key)
    bb.Adornee       = adornee
    bb.Size          = size or UDim2.new(0, 180, 0, 40)
    bb.StudsOffset   = studOffset or Vector3.new(0, 3, 0)
    bb.AlwaysOnTop   = true
    bb.LightInfluence= 0
    bb.Parent        = ESPGui

    local frame = Instance.new("Frame")
    frame.Size                  = UDim2.fromScale(1,1)
    frame.BackgroundColor3      = bgColor or Color3.fromRGB(10,10,30)
    frame.BackgroundTransparency= 0.4
    frame.BorderSizePixel       = 0
    frame.Parent                = bb
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0,5)

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.fromScale(1,1)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3             = textColor or Color3.fromRGB(255,255,255)
    lbl.TextStrokeTransparency = 0.5
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextSize               = textSize or (IS_MOBILE and 14 or 12)
    lbl.TextWrapped             = true
    lbl.Text                   = ""
    lbl.Parent                 = frame

    _billboards[key] = bb
    return bb
end

local function SetBBText(bb, text)
    local frame = bb:FindFirstChildOfClass("Frame")
    local lbl   = frame and frame:FindFirstChildOfClass("TextLabel")
    if lbl then lbl.Text = text end
end

-- Yörünge part'ları
local _trajParts   = {}
local _trajFolder  = nil

local function EnsureTrajParts(n)
    if not _trajFolder or not _trajFolder.Parent then
        _trajFolder = Instance.new("Folder")
        _trajFolder.Name   = "FU_Traj"
        _trajFolder.Parent = workspace
        table.clear(_trajParts)
    end
    while #_trajParts < n do
        local p = Instance.new("Part")
        p.Anchored    = true
        p.CanCollide  = false
        p.CanQuery    = false
        p.Size        = Vector3.new(0.15,0.15,0.15)
        p.Shape       = Enum.PartType.Ball
        p.Material    = Enum.Material.Neon
        p.CastShadow  = false
        p.Parent      = _trajFolder
        table.insert(_trajParts, p)
    end
    for i = n+1, #_trajParts do
        _trajParts[i].Transparency = 1
    end
end

-- Cooldown verileri
local _cdData  = {}
local _animCons= {}

local COOLDOWN_DURATIONS = { feint=3, punch=2, tackle=4, kick=3 }

local function ConnectCooldownListener(player)
    local c = player.Character
    if not c then return end
    local h = c:FindFirstChildOfClass("Humanoid")
    local a = h and h:FindFirstChildOfClass("Animator")
    if not a then return end

    if _animCons[player.Name] then
        pcall(function() _animCons[player.Name]:Disconnect() end)
    end
    _animCons[player.Name] = a.AnimationPlayed:Connect(function(track)
        local id = tostring(track.Animation.AnimationId):lower()
        for t, dur in pairs(COOLDOWN_DURATIONS) do
            if id:find(t) then
                _cdData[player.Name] = { type=t, endTime=tick()+dur }
                break
            end
        end
    end)
end

-- RenderStepped: ESP güncellemeleri
AddConn(RunService.RenderStepped:Connect(function()
    local myRoot = GetRoot()

    -- Item ESP
    if Config.ESP.ItemESP and myRoot then
        -- Kutu ESP
        if Config.ESP.ShowBoxContents then
            local boxes = FindInWS(Config.Items.BoxTag)
            for _, box in ipairs(boxes) do
                local part = box:IsA("BasePart") and box or box:FindFirstChildOfClass("BasePart")
                if not part then continue end
                local dist = (myRoot.Position - part.Position).Magnitude
                if dist > Config.ESP.ESPMaxDistance then continue end
                local contents = box:GetAttribute("ItemType") or box:GetAttribute("Item") or "?"
                local key  = "box_" .. tostring(box)
                local bb   = GetOrCreateBB(key, part, UDim2.new(0,160,0,36),
                                            Vector3.new(0,3,0),
                                            Color3.fromRGB(20,20,50),
                                            Color3.fromRGB(255,220,80), IS_MOBILE and 13 or 11)
                bb.Enabled = true
                SetBBText(bb, string.format("📦 %s\n%.0f studs", tostring(contents), dist))
            end
        end

        -- Rakip envanter ESP
        if Config.ESP.ShowEnemyItems then
            for _, player in ipairs(Players:GetPlayers()) do
                if player == LocalPlayer then continue end
                local c = player.Character
                if not c then continue end
                local r = c:FindFirstChild("HumanoidRootPart")
                if not r then continue end
                local dist = (myRoot.Position - r.Position).Magnitude
                if dist > Config.ESP.ESPMaxDistance then
                    if _billboards["pl_"..player.Name] then
                        _billboards["pl_"..player.Name].Enabled = false
                    end
                    continue
                end
                local inv = c:GetAttribute("Inventory")
                       or c:GetAttribute("Item1") and (tostring(c:GetAttribute("Item1")).." | "..tostring(c:GetAttribute("Item2") or "-"))
                       or "?"
                local key = "pl_"..player.Name
                local bb  = GetOrCreateBB(key, r, UDim2.new(0,180,0,40),
                                           Vector3.new(0,3.5,0),
                                           Color3.fromRGB(10,20,60),
                                           Color3.fromRGB(180,220,255), IS_MOBILE and 13 or 11)
                bb.Enabled = true
                SetBBText(bb, "👤 "..player.Name.."\n🎒 "..tostring(inv))
            end
        end
    else
        for _, bb in pairs(_billboards) do
            if bb and bb.Parent then bb.Enabled = false end
        end
    end

    -- Ball Trajectory
    if Config.ESP.BallTrajectory then
        local ball = FindBall()
        if ball and ball:IsA("BasePart") and ball.AssemblyLinearVelocity.Magnitude > 2 then
            local steps = Config.ESP.TrajectorySteps
            EnsureTrajParts(steps)
            local pos, vel = ball.Position, ball.AssemblyLinearVelocity
            local dt = 1/60
            for i = 1, steps do
                pos, vel = StepPhysics(pos, vel, dt)
                local p = _trajParts[i]
                p.CFrame       = CFrame.new(pos)
                p.Color        = Config.ESP.TrajectoryColor
                p.Transparency = 0.3 + (i/steps)*0.6
            end
        else
            if _trajParts then
                for _, p in ipairs(_trajParts) do p.Transparency = 1 end
            end
        end
    else
        if _trajParts then
            for _, p in ipairs(_trajParts) do p.Transparency = 1 end
        end
    end

    -- Cooldown Tracker
    if Config.ESP.CooldownTracker and myRoot then
        for _, player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            local c = player.Character
            if not c then continue end
            local r = c:FindFirstChild("HumanoidRootPart")
            if not r then continue end

            if not _animCons[player.Name] then
                ConnectCooldownListener(player)
            end

            local dist = (myRoot.Position - r.Position).Magnitude
            if dist > Config.ESP.ESPMaxDistance then continue end

            local data = _cdData[player.Name]
            local key  = "cd_" .. player.Name
            local bb   = GetOrCreateBB(key, r, UDim2.new(0,160,0,32),
                                        Vector3.new(0,5.5,0),
                                        Color3.fromRGB(40,0,0),
                                        Config.ESP.TrackerColor, IS_MOBILE and 13 or 11)
            bb.Enabled = true
            if data and tick() < data.endTime then
                local rem = Round(data.endTime - tick(), 1)
                SetBBText(bb, string.format("⏱ %s: %.1fs", data.type, rem))
            else
                SetBBText(bb, "✅ Hazır")
            end
        end
    end
end))

-- ══════════════════════════════════════════════════════════════
--  MODÜL 5 · MOVEMENT
-- ══════════════════════════════════════════════════════════════

local _sliding = false

AddConn(RunService.Heartbeat:Connect(function()
    local hum = GetHum()
    if not hum then return end

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
end))

-- Slide Boost
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
                lv.MaxForce    = 1e6
                lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
                lv.VectorVelocity = dir * spd
                lv.RelativeTo = Enum.ActuatorRelativeTo.World
                lv.Parent     = root
                task.delay(0.3, function() if lv.Parent then lv:Destroy() end end)
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

-- ══════════════════════════════════════════════════════════════
--  GUI · Kustom UI Kütüphanesi (Mobil Optimize)
-- ══════════════════════════════════════════════════════════════

local THEME = {
    BG        = Color3.fromRGB(14, 14, 20),
    Surface   = Color3.fromRGB(22, 22, 30),
    SurfaceAlt= Color3.fromRGB(28, 28, 40),
    Accent    = Color3.fromRGB(80, 140, 255),
    AccentDark= Color3.fromRGB(50, 90, 180),
    ON        = Color3.fromRGB(60, 200, 120),
    OFF       = Color3.fromRGB(65, 65, 80),
    TextMain  = Color3.fromRGB(240, 240, 255),
    TextSub   = Color3.fromRGB(140, 140, 180),
    Border    = Color3.fromRGB(50, 50, 70),
    Danger    = Color3.fromRGB(220, 70, 70),
}

-- Mobil boyutlar: büyük dokunma alanları
local ROW_H   = IS_MOBILE and 48 or 36
local TAB_W   = IS_MOBILE and 90 or 110
local WIN_W   = IS_MOBILE and (workspace.CurrentCamera.ViewportSize.X - 20) or 520
local WIN_H   = IS_MOBILE and (workspace.CurrentCamera.ViewportSize.Y * 0.85) or 440
local TXT_SZ  = IS_MOBILE and 14 or 12

local function MI(cls, props, parent)
    local i = Instance.new(cls)
    for k,v in pairs(props) do i[k] = v end
    i.Parent = parent
    return i
end

local function Corner(p, r) MI("UICorner",{CornerRadius=UDim.new(0,r or 6)},p) end
local function Padding(p,t,b,l,r)
    MI("UIPadding",{PaddingTop=UDim.new(0,t or 6),PaddingBottom=UDim.new(0,b or 6),
                    PaddingLeft=UDim.new(0,l or 8),PaddingRight=UDim.new(0,r or 8)},p)
end
local function ListLayout(p, dir, pad)
    MI("UIListLayout",{FillDirection=dir or Enum.FillDirection.Vertical,
                       SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,pad or 4)},p)
end

local function Tween(inst, goal, t)
    TweenService:Create(inst, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad), goal):Play()
end

-- Ana GUI
local guiRoot do
    local ex = CoreGui:FindFirstChild("FU_GUI")
    if ex then ex:Destroy() end
    guiRoot = MI("ScreenGui",{
        Name="FU_GUI", ResetOnSpawn=false,
        ZIndexBehavior=Enum.ZIndexBehavior.Global,
        IgnoreGuiInset=true
    }, CoreGui)
end

-- Ana çerçeve
local mainFrame = MI("Frame",{
    Name="Main",
    Size=UDim2.new(0,WIN_W,0,WIN_H),
    Position=UDim2.new(0.5,-WIN_W/2, 0.5,-WIN_H/2),
    BackgroundColor3=THEME.BG,
    BorderSizePixel=0,
    ClipsDescendants=true,
},guiRoot)
Corner(mainFrame, 10)
MI("UIStroke",{Color=THEME.Border,Thickness=1,Transparency=0.4},mainFrame)

-- Başlık çubuğu
local titleBar = MI("Frame",{
    Size=UDim2.new(1,0,0, IS_MOBILE and 50 or 42),
    BackgroundColor3=THEME.Surface,
    BorderSizePixel=0,
},mainFrame)
Corner(titleBar,10)
MI("Frame",{Size=UDim2.new(1,0,0.5,0),Position=UDim2.new(0,0,0.5,0),
            BackgroundColor3=THEME.Surface,BorderSizePixel=0},titleBar)
MI("Frame",{Size=UDim2.new(1,0,0,2),Position=UDim2.new(0,0,1,-2),
            BackgroundColor3=THEME.Accent,BorderSizePixel=0},titleBar)

local logoFrame = MI("Frame",{Size=UDim2.new(0,28,0,28),Position=UDim2.new(0,10,0.5,-14),
                               BackgroundColor3=THEME.Accent,BorderSizePixel=0},titleBar)
Corner(logoFrame,14)
MI("TextLabel",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
                Text="⚽",TextSize=16,Font=Enum.Font.Gotham},logoFrame)

MI("TextLabel",{
    Size=UDim2.new(1,-120,1,0), Position=UDim2.new(0,46,0,0),
    BackgroundTransparency=1, Text="⚽ FutbolUmsu  v1.0",
    TextColor3=THEME.TextMain, Font=Enum.Font.GothamBold,
    TextSize=IS_MOBILE and 16 or 14, TextXAlignment=Enum.TextXAlignment.Left,
},titleBar)

-- Kapat butonu
local closeBtn = MI("TextButton",{
    Size=UDim2.new(0,IS_MOBILE and 38 or 30,0,IS_MOBILE and 38 or 30),
    Position=UDim2.new(1,-(IS_MOBILE and 44 or 36),0.5,-(IS_MOBILE and 19 or 15)),
    BackgroundColor3=THEME.Danger, BackgroundTransparency=0.3,
    Text="✕", TextColor3=THEME.TextMain,
    Font=Enum.Font.GothamBold, TextSize=IS_MOBILE and 16 or 13,
    BorderSizePixel=0, AutoButtonColor=false,
},titleBar)
Corner(closeBtn,6)
closeBtn.MouseButton1Click:Connect(function()
    mainFrame.Visible = not mainFrame.Visible
end)

-- Drag
local _drag, _dragStart, _dragPos = false, nil, nil
titleBar.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        _drag=true; _dragStart=i.Position
        _dragPos=mainFrame.Position
    end
end)
titleBar.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        _drag=false
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if not _drag then return end
    if i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch then
        local d = i.Position - _dragStart
        mainFrame.Position = UDim2.new(
            _dragPos.X.Scale, _dragPos.X.Offset+d.X,
            _dragPos.Y.Scale, _dragPos.Y.Offset+d.Y
        )
    end
end)

-- Sekme çubuğu (sol)
local tabBarFrame = MI("Frame",{
    Size=UDim2.new(0,TAB_W,1,-(IS_MOBILE and 50 or 42)),
    Position=UDim2.new(0,0,0,IS_MOBILE and 50 or 42),
    BackgroundColor3=THEME.Surface, BorderSizePixel=0,
},mainFrame)
MI("Frame",{Size=UDim2.new(0,1,1,0),Position=UDim2.new(1,-1,0,0),
            BackgroundColor3=THEME.Border,BorderSizePixel=0},tabBarFrame)

local tabScroll = MI("ScrollingFrame",{
    Size=UDim2.new(1,0,1,-8), Position=UDim2.new(0,0,0,4),
    BackgroundTransparency=1, BorderSizePixel=0,
    ScrollBarThickness=0, ScrollingDirection=Enum.ScrollingDirection.Y,
    CanvasSize=UDim2.new(0,0,0,0),
},tabBarFrame)
ListLayout(tabScroll, Enum.FillDirection.Vertical, 3)
Padding(tabScroll,4,4,5,5)

-- İçerik alanı
local contentArea = MI("Frame",{
    Size=UDim2.new(1,-TAB_W,1,-(IS_MOBILE and 50 or 42)),
    Position=UDim2.new(0,TAB_W,0,IS_MOBILE and 50 or 42),
    BackgroundTransparency=1, BorderSizePixel=0, ClipsDescendants=true,
},mainFrame)

-- Sekme yönetimi
local _tabs = {}
local _activeTab = nil

local function SelectTab(name)
    if _activeTab and _tabs[_activeTab] then
        _tabs[_activeTab].page.Visible = false
        Tween(_tabs[_activeTab].btn,{BackgroundColor3=THEME.SurfaceAlt, TextColor3=THEME.TextSub},0.12)
    end
    _activeTab = name
    if _tabs[name] then
        _tabs[name].page.Visible = true
        Tween(_tabs[name].btn,{BackgroundColor3=THEME.Accent, TextColor3=THEME.TextMain},0.12)
    end
end

local function AddTab(name, icon)
    local btn = MI("TextButton",{
        Name=name,
        Size=UDim2.new(1,0,0,IS_MOBILE and 44 or 34),
        BackgroundColor3=THEME.SurfaceAlt,
        Text=(icon and icon.." " or "")..name,
        TextColor3=THEME.TextSub,
        Font=Enum.Font.GothamBold,
        TextSize=IS_MOBILE and 12 or 11,
        TextWrapped=true,
        BorderSizePixel=0,
        AutoButtonColor=false,
    },tabScroll)
    Corner(btn,5)

    local page = MI("ScrollingFrame",{
        Name=name.."_Page",
        Size=UDim2.fromScale(1,1),
        BackgroundTransparency=1,
        BorderSizePixel=0,
        ScrollBarThickness=IS_MOBILE and 4 or 3,
        ScrollBarImageColor3=THEME.Accent,
        ScrollingDirection=Enum.ScrollingDirection.Y,
        CanvasSize=UDim2.new(0,0,0,0),
        Visible=false,
    },contentArea)
    ListLayout(page, Enum.FillDirection.Vertical, IS_MOBILE and 6 or 4)
    Padding(page, IS_MOBILE and 10 or 6, IS_MOBILE and 10 or 6, IS_MOBILE and 10 or 8, IS_MOBILE and 10 or 8)

    page:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0,0,0,page.AbsoluteContentSize.Y+16)
    end)

    btn.MouseButton1Click:Connect(function() SelectTab(name) end)

    _tabs[name] = {btn=btn, page=page}
    if not _activeTab then SelectTab(name) end

    -- TabList canvas güncelle
    local layout = tabScroll:FindFirstChildOfClass("UIListLayout")
    if layout then tabScroll.CanvasSize=UDim2.new(0,0,0,layout.AbsoluteContentSize.Y) end

    return page
end

-- Eleman oluşturucular
local function AddSection(page, text)
    local f = MI("Frame",{
        Size=UDim2.new(1,0,0,IS_MOBILE and 32 or 26),
        BackgroundTransparency=1,BorderSizePixel=0,
    },page)
    MI("TextLabel",{
        Size=UDim2.fromScale(1,1), BackgroundTransparency=1,
        Text=text, TextColor3=THEME.Accent,
        Font=Enum.Font.GothamBold,
        TextSize=IS_MOBILE and 13 or 11,
        TextXAlignment=Enum.TextXAlignment.Left,
    },f)
    MI("Frame",{
        Size=UDim2.new(1,0,0,1), Position=UDim2.new(0,0,1,-1),
        BackgroundColor3=THEME.Accent, BackgroundTransparency=0.6,
        BorderSizePixel=0,
    },f)
end

local function AddToggle(page, name, default, callback, desc)
    local state = default or false
    local rowH  = (desc and IS_MOBILE) and 62 or (desc and 52 or ROW_H)

    local row = MI("Frame",{
        Size=UDim2.new(1,0,0,rowH),
        BackgroundColor3=THEME.SurfaceAlt,
        BorderSizePixel=0,
    },page)
    Corner(row,6)
    Padding(row, IS_MOBILE and 8 or 6, IS_MOBILE and 8 or 6, IS_MOBILE and 12 or 10, IS_MOBILE and 12 or 10)

    MI("TextLabel",{
        Size=UDim2.new(1,-60,0,IS_MOBILE and 22 or 18),
        BackgroundTransparency=1,
        Text=name, TextColor3=THEME.TextMain,
        Font=Enum.Font.GothamBold,
        TextSize=TXT_SZ, TextXAlignment=Enum.TextXAlignment.Left,
    },row)

    if desc then
        MI("TextLabel",{
            Size=UDim2.new(1,-60,0,IS_MOBILE and 18 or 14),
            Position=UDim2.new(0,0,0,IS_MOBILE and 24 or 20),
            BackgroundTransparency=1,
            Text=desc, TextColor3=THEME.TextSub,
            Font=Enum.Font.Gotham,
            TextSize=IS_MOBILE and 11 or 10,
            TextXAlignment=Enum.TextXAlignment.Left,
        },row)
    end

    -- Toggle track (daha büyük dokunma alanı için mobilde)
    local tW = IS_MOBILE and 52 or 44
    local tH = IS_MOBILE and 28 or 22
    local kS = tH - 4

    local track = MI("Frame",{
        Size=UDim2.new(0,tW,0,tH),
        Position=UDim2.new(1,-tW,0.5,-tH/2),
        BackgroundColor3=state and THEME.ON or THEME.OFF,
        BorderSizePixel=0,
    },row)
    Corner(track, tH//2)

    local knob = MI("Frame",{
        Size=UDim2.new(0,kS,0,kS),
        Position=state and UDim2.new(0,tW-kS-2,0.5,-kS/2) or UDim2.new(0,2,0.5,-kS/2),
        BackgroundColor3=Color3.fromRGB(255,255,255),
        BorderSizePixel=0,
    },track)
    Corner(knob, kS//2)

    local clickArea = MI("TextButton",{
        Size=UDim2.fromScale(1,1), BackgroundTransparency=1,
        Text="", ZIndex=5,
    },row)

    local function SetState(v)
        state = v
        Tween(track, {BackgroundColor3=v and THEME.ON or THEME.OFF})
        Tween(knob,  {Position=v and UDim2.new(0,tW-kS-2,0.5,-kS/2) or UDim2.new(0,2,0.5,-kS/2)})
        pcall(callback, v)
    end
    clickArea.MouseButton1Click:Connect(function() SetState(not state) end)

    return {Set=SetState, Get=function() return state end}
end

local function AddSlider(page, name, mn, mx, default, callback, suffix)
    suffix  = suffix or ""
    local value = math.clamp(default or mn, mn, mx)

    local row = MI("Frame",{
        Size=UDim2.new(1,0,0,IS_MOBILE and 68 or 56),
        BackgroundColor3=THEME.SurfaceAlt, BorderSizePixel=0,
    },page)
    Corner(row,6)
    Padding(row, IS_MOBILE and 10 or 8, IS_MOBILE and 10 or 8, IS_MOBILE and 12 or 10, IS_MOBILE and 12 or 10)

    local header = MI("Frame",{
        Size=UDim2.new(1,0,0,IS_MOBILE and 22 or 18),
        BackgroundTransparency=1,
    },row)
    MI("TextLabel",{
        Size=UDim2.new(0.65,0,1,0),BackgroundTransparency=1,
        Text=name, TextColor3=THEME.TextMain,
        Font=Enum.Font.GothamBold,TextSize=TXT_SZ,
        TextXAlignment=Enum.TextXAlignment.Left,
    },header)
    local valLbl = MI("TextLabel",{
        Size=UDim2.new(0.35,0,1,0), Position=UDim2.new(0.65,0,0,0),
        BackgroundTransparency=1,
        Text=tostring(value)..suffix, TextColor3=THEME.Accent,
        Font=Enum.Font.GothamBold, TextSize=TXT_SZ,
        TextXAlignment=Enum.TextXAlignment.Right,
    },header)

    local trackH = IS_MOBILE and 10 or 8
    local track = MI("Frame",{
        Size=UDim2.new(1,0,0,trackH),
        Position=UDim2.new(0,0,0, IS_MOBILE and 30 or 24),
        BackgroundColor3=Color3.fromRGB(40,40,55),
        BorderSizePixel=0,
    },row)
    Corner(track, trackH//2)

    local fill = MI("Frame",{
        Size=UDim2.new((value-mn)/(mx-mn),0,1,0),
        BackgroundColor3=THEME.Accent, BorderSizePixel=0,
    },track)
    Corner(fill, trackH//2)

    local thumbSz = IS_MOBILE and 22 or 16
    local thumb = MI("Frame",{
        Size=UDim2.new(0,thumbSz,0,thumbSz),
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.new((value-mn)/(mx-mn),0,0.5,0),
        BackgroundColor3=Color3.fromRGB(255,255,255),
        BorderSizePixel=0, ZIndex=3,
    },track)
    Corner(thumb, thumbSz//2)
    MI("UIStroke",{Color=THEME.Accent,Thickness=2},thumb)

    local hitarea = MI("TextButton",{
        Size=UDim2.new(1,0,0, IS_MOBILE and 40 or 28),
        Position=UDim2.new(0,0,0,-IS_MOBILE and 15 or 10),
        BackgroundTransparency=1, Text="", ZIndex=5,
    },track)

    local sliding = false
    local function Update(ix)
        local ta = track.AbsolutePosition.X
        local tw = track.AbsoluteSize.X
        local t  = math.clamp((ix-ta)/tw,0,1)
        local step = (mx-mn)<=10 and 0.1 or 1
        value = math.floor((mn+(mx-mn)*t)/step+0.5)*step
        value = math.clamp(value, mn, mx)
        Tween(fill,  {Size=UDim2.new(t,0,1,0)})
        Tween(thumb, {Position=UDim2.new(t,0,0.5,0)})
        valLbl.Text = tostring(Round(value,1))..suffix
        pcall(callback, value)
    end

    hitarea.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            sliding=true; Update(i.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            sliding=false
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if not sliding then return end
        if i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch then
            Update(i.Position.X)
        end
    end)

    return {Get=function() return value end, Set=function(v)
        value=math.clamp(v,mn,mx)
        local t=(value-mn)/(mx-mn)
        fill.Size=UDim2.new(t,0,1,0)
        thumb.Position=UDim2.new(t,0,0.5,0)
        valLbl.Text=tostring(value)..suffix
    end}
end

local function AddButton(page, label, cb, color)
    local btn = MI("TextButton",{
        Size=UDim2.new(1,0,0,ROW_H),
        BackgroundColor3=color or THEME.Accent,
        BackgroundTransparency=0.3,
        Text=label, TextColor3=THEME.TextMain,
        Font=Enum.Font.GothamBold, TextSize=TXT_SZ,
        BorderSizePixel=0, AutoButtonColor=false,
    },page)
    Corner(btn,6)
    btn.MouseButton1Click:Connect(function() pcall(cb) end)
    return btn
end

local function AddDropdown(page, label, opts, default, cb)
    local sel = default or opts[1]
    local container = MI("Frame",{
        Size=UDim2.new(1,0,0,ROW_H),
        BackgroundColor3=THEME.SurfaceAlt, BorderSizePixel=0,
        ClipsDescendants=false, ZIndex=10,
    },page)
    Corner(container,6)
    Padding(container,0,0,12,12)

    MI("TextLabel",{
        Size=UDim2.new(0.55,0,1,0), BackgroundTransparency=1,
        Text=label, TextColor3=THEME.TextMain,
        Font=Enum.Font.GothamBold, TextSize=TXT_SZ,
        TextXAlignment=Enum.TextXAlignment.Left,
    },container)
    local cur = MI("TextLabel",{
        Size=UDim2.new(0.45,0,1,0), Position=UDim2.new(0.55,0,0,0),
        BackgroundTransparency=1,
        Text="▼ "..tostring(sel), TextColor3=THEME.Accent,
        Font=Enum.Font.GothamBold, TextSize=TXT_SZ,
        TextXAlignment=Enum.TextXAlignment.Right,
    },container)

    local panel = MI("Frame",{
        Size=UDim2.new(1,0,0,#opts*(IS_MOBILE and 36 or 28)+8),
        Position=UDim2.new(0,0,1,4),
        BackgroundColor3=THEME.Surface, BorderSizePixel=0,
        ZIndex=20, Visible=false,
    },container)
    Corner(panel,6)
    MI("UIStroke",{Color=THEME.Border,Thickness=1},panel)
    ListLayout(panel,Enum.FillDirection.Vertical,2)
    Padding(panel,4,4,4,4)

    for _, opt in ipairs(opts) do
        local ob = MI("TextButton",{
            Size=UDim2.new(1,0,0,IS_MOBILE and 34 or 26),
            BackgroundTransparency=1,
            Text=tostring(opt), TextColor3=THEME.TextSub,
            Font=Enum.Font.Gotham, TextSize=TXT_SZ,
            BorderSizePixel=0, ZIndex=21, AutoButtonColor=false,
        },panel)
        Corner(ob,4)
        ob.MouseButton1Click:Connect(function()
            sel=opt; cur.Text="▼ "..tostring(opt)
            panel.Visible=false; pcall(cb,opt)
        end)
    end

    local tb = MI("TextButton",{
        Size=UDim2.fromScale(1,1), BackgroundTransparency=1,
        Text="", ZIndex=11,
    },container)
    tb.MouseButton1Click:Connect(function() panel.Visible=not panel.Visible end)
    return {Get=function() return sel end}
end

local function AddLabel(page, text, clr)
    MI("TextLabel",{
        Size=UDim2.new(1,0,0,IS_MOBILE and 30 or 22),
        BackgroundTransparency=1,
        Text=text, TextColor3=clr or THEME.TextSub,
        Font=Enum.Font.Gotham, TextSize=IS_MOBILE and 12 or 10,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextWrapped=true,
    },page)
end

-- ══════════════════════════════════════════════════════════════
--  MENÜ · 4 Sekme
-- ══════════════════════════════════════════════════════════════

-- 1. COMBAT
local pCombat = AddTab("Combat","⚔️")
AddSection(pCombat,"🥊 Dövüş Otomasyonu")
AddToggle(pCombat,"Auto Parry",Config.Combat.AutoParry,function(v) Config.Combat.AutoParry=v end,"Vurma animasyonu algılanınca anında parry")
AddSlider(pCombat,"Parry Menzili",4,30,Config.Combat.AutoParryRadius,function(v) Config.Combat.AutoParryRadius=v end," st")
AddSlider(pCombat,"Parry Gecikmesi",0.0,0.5,Config.Combat.AutoParryDelay,function(v) Config.Combat.AutoParryDelay=v end,"s")
AddSection(pCombat,"🏃 Tackle")
AddToggle(pCombat,"Auto Tackle",Config.Combat.AutoTackle,function(v) Config.Combat.AutoTackle=v end,"Top rakipteyken otomatik kayma")
AddSlider(pCombat,"Tackle Menzili",3,25,Config.Combat.TackleRange,function(v) Config.Combat.TackleRange=v end," st")
AddSection(pCombat,"👊 KO & Savunma")
AddToggle(pCombat,"Auto Knockout",Config.Combat.AutoKnockout,function(v) Config.Combat.AutoKnockout=v end,"Sürekli yumruk döngüsü")
AddSlider(pCombat,"KO Menzili",3,20,Config.Combat.KORange,function(v) Config.Combat.KORange=v end," st")
AddSlider(pCombat,"KO Aralığı",0.05,1,Config.Combat.KODelay,function(v) Config.Combat.KODelay=v end,"s")
AddToggle(pCombat,"Anti-Tackle",Config.Combat.AntiTackle,function(v) Config.Combat.AntiTackle=v end,"Desync ile tackle'dan kaçın")
AddSlider(pCombat,"Desync Ofseti",1,8,Config.Combat.DesyncOffset,function(v) Config.Combat.DesyncOffset=v end," st")

-- 2. BALL/GOAL
local pBall = AddTab("Ball","⚽")
AddSection(pBall,"🎯 Şut Yönlendirme")
AddToggle(pBall,"Silent Aim",Config.Ball.SilentAim,function(v) Config.Ball.SilentAim=v end,"Topu kale köşesine otomatik yönlendir")
AddDropdown(pBall,"Hedef Köşe",{"BottomLeft","BottomRight","TopLeft","TopRight","Center"},Config.Ball.SilentAimCorner,function(v) Config.Ball.SilentAimCorner=v end)
AddSlider(pBall,"Aim Gücü",0.1,1.0,Config.Ball.SilentAimStrength,function(v) Config.Ball.SilentAimStrength=v end,"x")
AddButton(pBall,"⚽ Manuel Aim Uygula",function() pcall(ApplySilentAim) end)
AddSection(pBall,"🧲 Top Kontrolü")
AddToggle(pBall,"Magnet Reach",Config.Ball.MagnetReach,function(v) Config.Ball.MagnetReach=v end,"Topu manyetik alan ile çek")
AddSlider(pBall,"Reach Menzili",5,50,Config.Ball.ReachRadius,function(v) Config.Ball.ReachRadius=v end," st")
AddToggle(pBall,"No Feint Cooldown",Config.Ball.NoFeintCooldown,function(v) Config.Ball.NoFeintCooldown=v end,"Vücut çalımı bekleme bypass")

-- 3. ITEMS / ESP
local pItems = AddTab("Items","📦")
AddSection(pItems,"📦 Kutu Toplama")
AddToggle(pItems,"Box Auto-Collect",Config.Items.BoxTeleport,function(v) Config.Items.BoxTeleport=v end,"Kutulara otomatik git/çek")
AddDropdown(pItems,"Mod",{"Teleport","Pull"},Config.Items.BoxPullMode,function(v) Config.Items.BoxPullMode=v end)
AddSlider(pItems,"Tarama Aralığı",0.1,3,Config.Items.BoxScanInterval,function(v) Config.Items.BoxScanInterval=v end,"s")
AddButton(pItems,"📦 Şimdi Topla",function()
    local myRoot=GetRoot()
    if not myRoot then return end
    local boxes=FindInWS(Config.Items.BoxTag)
    if #boxes==0 then return end
    local nearest,minD=nil,math.huge
    for _,box in ipairs(boxes) do
        local p=box:IsA("BasePart") and box or box:FindFirstChildOfClass("BasePart")
        if p then local d=(myRoot.Position-p.Position).Magnitude if d<minD then minD=d nearest=p end end
    end
    if nearest then myRoot.CFrame=CFrame.new(nearest.Position+Vector3.new(0,3,0)) end
end)
AddSection(pItems,"🤖 Akıllı Eşya")
AddToggle(pItems,"Smart Auto-Use",Config.Items.SmartAutoUse,function(v) Config.Items.SmartAutoUse=v end)
AddToggle(pItems,"  ↳ Otomatik Tuzak",Config.Items.AutoUseTrap,function(v) Config.Items.AutoUseTrap=v end)
AddToggle(pItems,"  ↳ Otomatik Mıknatıs",Config.Items.AutoUseMagnet,function(v) Config.Items.AutoUseMagnet=v end)
AddSection(pItems,"👁️ ESP")
AddToggle(pItems,"Item ESP",Config.ESP.ItemESP,function(v) Config.ESP.ItemESP=v end,"Kutu ve envanter göstergesi")
AddToggle(pItems,"  ↳ Kutu İçerikleri",Config.ESP.ShowBoxContents,function(v) Config.ESP.ShowBoxContents=v end)
AddToggle(pItems,"  ↳ Rakip Envanteri",Config.ESP.ShowEnemyItems,function(v) Config.ESP.ShowEnemyItems=v end)
AddSlider(pItems,"ESP Mesafesi",30,300,Config.ESP.ESPMaxDistance,function(v) Config.ESP.ESPMaxDistance=v end," st")
AddToggle(pItems,"Ball Trajectory",Config.ESP.BallTrajectory,function(v) Config.ESP.BallTrajectory=v end,"Top yörüngesi tahmin çizgisi")
AddSlider(pItems,"Yörünge Adımları",10,120,Config.ESP.TrajectorySteps,function(v) Config.ESP.TrajectorySteps=v end)
AddToggle(pItems,"Cooldown Tracker",Config.ESP.CooldownTracker,function(v) Config.ESP.CooldownTracker=v end,"Rakip cooldown sayaçları")

-- 4. MOVEMENT
local pMove = AddTab("Move","🏃")
AddSection(pMove,"⚡ Hız")
AddToggle(pMove,"Speed Hack",Config.Movement.SpeedHack,function(v) Config.Movement.SpeedHack=v end)
AddSlider(pMove,"Yürüme Hızı",16,120,Config.Movement.WalkSpeed,function(v) Config.Movement.WalkSpeed=v end," ws")
AddSection(pMove,"🦘 Zıplama")
AddToggle(pMove,"Jump Power",Config.Movement.JumpPower,function(v) Config.Movement.JumpPower=v end)
AddSlider(pMove,"Zıplama Yüksekliği",7,200,Config.Movement.JumpHeight,function(v) Config.Movement.JumpHeight=v end," st")
AddSection(pMove,"💨 Slide Boost")
AddToggle(pMove,"Slide Velocity Boost",Config.Movement.SlideBoost,function(v) Config.Movement.SlideBoost=v end,"Kayma anında ek hız")
AddSlider(pMove,"Kayma Çarpanı",1,8,Config.Movement.SlideMultiplier,function(v) Config.Movement.SlideMultiplier=v end,"x")
AddButton(pMove,"💨 Anlık Slide Boost",function()
    local root=GetRoot()
    if not root then return end
    local vel=root.AssemblyLinearVelocity
    local flat=Vector3.new(vel.X,0,vel.Z)
    local dir=flat.Magnitude>0.5 and flat.Unit or root.CFrame.LookVector
    local spd=(vel.Magnitude+16)*Config.Movement.SlideMultiplier
    local lv=Instance.new("LinearVelocity")
    local att=root:FindFirstChildOfClass("Attachment") or Instance.new("Attachment",root)
    lv.Attachment0=att; lv.MaxForce=1e6
    lv.VelocityConstraintMode=Enum.VelocityConstraintMode.Vector
    lv.VectorVelocity=dir*spd
    lv.RelativeTo=Enum.ActuatorRelativeTo.World
    lv.Parent=root
    task.delay(0.3,function() if lv.Parent then lv:Destroy() end end)
end)
AddSection(pMove,"ℹ️ Bilgi")
AddLabel(pMove, IS_MOBILE and "Kapat butonuna bas → Gizle/Göster" or "RightShift: GUI Gizle/Göster")

-- RightShift: GUI toggle (masaüstü)
if not IS_MOBILE then
    UserInputService.InputBegan:Connect(function(i, gpe)
        if gpe then return end
        if i.KeyCode == Enum.KeyCode.RightShift then
            mainFrame.Visible = not mainFrame.Visible
        end
    end)
end

-- ══════════════════════════════════════════════════════════════
--  GLOBAL TEMİZLİK KAYDI
-- ══════════════════════════════════════════════════════════════

local function StopAll()
    _boxActive = false
    DisconnectAll()
    pcall(function() ESPGui:Destroy() end)
    pcall(function() guiRoot:Destroy() end)
    pcall(function() if _trajFolder then _trajFolder:Destroy() end end)
    for _, c in pairs(_animCons) do pcall(function() c:Disconnect() end) end
    table.clear(_animCons)
    local hum = GetHum()
    if hum then hum.WalkSpeed=16; hum.JumpHeight=7.2 end
    print("[FutbolUmsu] Temizlendi.")
end

if getgenv then
    getgenv()._FU_Loaded = true
    getgenv()._FU_Stop   = StopAll
    getgenv()._FU_Config = Config
end

print("═══════════════════════════════════════")
print("  ⚽  FutbolUmsu  v1.0  HAZIR")
print("  Platform:", IS_MOBILE and "MOBİL 📱" or "MASAÜSTÜ 🖥️")
print("  GUI: Ekranın ortasında görünür")
print("  Kapat butonu (✕) → Gizle/Göster")
print("═══════════════════════════════════════")
