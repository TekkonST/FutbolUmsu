--[[
==================================================================
        FutbolUmsu · Bundle.lua (V2 - MOBIL & MEKANIK FIX)
  Delta X · Arceus X · Hydrogen · Fluxus · Codex · KRNL Destekli
==================================================================
--]]

-- Eski oturumu temizle
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

-- GUI Parent Belirleme (Mobilde en stabil calisan yer)
local function GetSafeGuiParent()
    local success, hui = pcall(function()
        if gethui then return gethui() end
    end)
    if success and hui then return hui end
    return CoreGui or LocalPlayer:WaitForChild("PlayerGui")
end

-- ===============================================================
-- 2. MERKEZI AYARLAR (CONFIG)
-- ===============================================================
local Config = {
    Combat = {
        AutoParry        = false,
        AutoParryRadius  = 15,
        AutoParryDelay   = 0.05,
        AutoTackle       = false,
        TackleRange      = 12,
        TackleDelay      = 0.15,
        AutoKnockout     = false,
        KORange          = 9,
        KODelay          = 0.12,
        AntiStealFeint   = false,   -- GERCEK TOP KORUMA (Top sendeyken rakip yaklasirsa Feint)
        FeintRemoteName  = "BodyFeint",
        TackleRemoteName = "Tackle",
        PunchRemoteName  = "Punch",
    },
    Ball = {
        SilentAim         = false,
        SilentAimCorner   = "BottomLeft",
        SilentAimStrength = 1.0,
        MagnetReach       = false,   -- Real Touch & Steal
        ReachRadius       = 20,
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
        PlayerESP        = false,   -- Duvar arkasi gorme (Highlight + Bilgi)
        BoxESP           = false,   -- Sahadaki kutulari gorme
        BallTrajectory   = false,   -- Topun gidecegi yolu 3D cizme
        CooldownTracker  = false,   -- Rakip feint/vurma sayaci
        ESPMaxDistance   = 250,
        TrajectoryColor  = Color3.fromRGB(255, 215, 0),
    },
    Movement = {
        SpeedHack        = false,
        WalkSpeed        = 16,
        MaxWalkSpeed     = 100,
        JumpPower        = false,
        JumpHeight       = 50,
        SlideBoost       = false,
        SlideMultiplier  = 3.5,
    },
}

-- Baglanti Takip
local Connections = {}
local function AddConn(c) table.insert(Connections, c) end
local function DisconnectAll()
    for _, c in ipairs(Connections) do
        if c and c.Connected then pcall(c.Disconnect, c) end
    end
    table.clear(Connections)
end

-- ===============================================================
-- 3. YARDIMCI FONKSIYONLAR
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

-- Sahadaki Topu Bul (Gelistirilmis Arama)
local function FindBall()
    -- 1. Workspace direkt
    local b = workspace:FindFirstChild(Config.Ball.BallName, true)
    if b and b:IsA("BasePart") then return b end

    -- 2. Tag ile
    local tagged = CollectionService:GetTagged("Ball")
    if tagged and #tagged > 0 then
        for _, t in ipairs(tagged) do
            if t:IsA("BasePart") then return t end
            local bp = t:FindFirstChildOfClass("BasePart")
            if bp then return bp end
        end
    end

    -- 3. Isminde 'ball' veya 'football' gecen part
    for _, v in ipairs(workspace:GetChildren()) do
        local n = v.Name:lower()
        if n == "ball" or n:find("football") or n:find("soccer") then
            if v:IsA("BasePart") then return v end
            local bp = v:FindFirstChildOfClass("BasePart")
            if bp then return bp end
        end
    end
    return nil
end

-- Top Sende mi?
local function DoIHaveBall()
    local ball = FindBall()
    local root = GetRoot()
    if not ball or not root then return false end
    return (root.Position - ball.Position).Magnitude < 4.5
end

-- En Yakin Dusman
local function GetNearestEnemy(radius)
    local root = GetRoot()
    if not root then return nil, math.huge end
    local pos, nearest, minD = root.Position, nil, radius or math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            local h = p.Character:FindFirstChildOfClass("Humanoid")
            if r and h and h.Health > 0 then
                local d = (pos - r.Position).Magnitude
                if d < minD then
                    minD = d
                    nearest = p
                end
            end
        end
    end
    return nearest, minD
end

-- Sahadaki Kutulari Bul (Esnek Arama)
local function FindAllBoxes()
    local found = {}
    local tagBoxes = CollectionService:GetTagged(Config.Items.BoxTag)
    for _, b in ipairs(tagBoxes) do
        local bp = b:IsA("BasePart") and b or b:FindFirstChildOfClass("BasePart")
        if bp then table.insert(found, bp) end
    end

    -- Isim taramasi
    for _, v in ipairs(workspace:GetDescendants()) do
        local n = v.Name:lower()
        if n == Config.Items.BoxTag:lower() or n:find("skillbox") or n:find("luckyblock") or n:find("itembox") then
            local bp = v:IsA("BasePart") and v or v:FindFirstChildOfClass("BasePart")
            if bp and not table.find(found, bp) then
                table.insert(found, bp)
            end
        end
    end
    return found
end

-- Remote Bul ve Calistir
local _remoteCache = {}
local function GetRemote(name)
    if _remoteCache[name] then return _remoteCache[name] end
    local r = ReplicatedStorage:FindFirstChild(name, true)
    if not r then
        for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
            if v.Name:lower() == name:lower() and (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) then
                r = v
                break
            end
        end
    end
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

-- Kale Koseleri
local function GetGoalCorner(cornerName)
    local root = GetRoot()
    if not root then return nil end
    local goals = {}
    for _, v in ipairs(workspace:GetDescendants()) do
        local n = v.Name:lower()
        if n:find("goal") or n:find("kale") or n:find("post") then
            local bp = v:IsA("BasePart") and v or v:FindFirstChildOfClass("BasePart")
            if bp and bp.Size.X > 5 then
                table.insert(goals, bp)
            end
        end
    end
    if #goals == 0 then return nil end

    local best, bestD = nil, -math.huge
    for _, g in ipairs(goals) do
        local d = (root.Position - g.Position).Magnitude
        if d > bestD then bestD = d; best = g end
    end
    if not best then return nil end

    local sz = best.Size
    local cf = best.CFrame
    local offsets = {
        BottomLeft  = Vector3.new(-sz.X/2.5, -sz.Y/3, 0),
        BottomRight = Vector3.new( sz.X/2.5, -sz.Y/3, 0),
        TopLeft     = Vector3.new(-sz.X/2.5,  sz.Y/3, 0),
        TopRight    = Vector3.new( sz.X/2.5,  sz.Y/3, 0),
        Center      = Vector3.new(0, 0, 0),
    }
    local off = offsets[cornerName] or offsets.BottomLeft
    return (cf * CFrame.new(off)).Position
end

-- ===============================================================
-- 4. OYUN MEKANIKLERI
-- ===============================================================

local _lastParry   = 0
local _lastTackle  = 0
local _lastKO      = 0
local _lastFeint   = 0

-- A) AUTO PARRY & ANTI-STEAL (TOP KORUMA)
AddConn(RunService.Heartbeat:Connect(function()
    local now = tick()
    local myRoot = GetRoot()
    if not myRoot then return end

    -- 1. TOP KAYBETMEME (ANTI-STEAL AUTO FEINT)
    -- Top sendeyken rakip yaklasirsa ve vurmaya/kaymaya calisirsa otomatik Dokunulmazlik (Feint) bas
    if Config.Combat.AntiStealFeint and DoIHaveBall() then
        if now - _lastFeint > 0.8 then
            local enemy, dist = GetNearestEnemy(9)
            if enemy and dist <= 8 then
                local c = enemy.Character
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                local anim = hum and hum:FindFirstChildOfClass("Animator")
                local isAttacking = false

                if anim then
                    for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                        local name = track.Animation.Name:lower()
                        local id = tostring(track.Animation.AnimationId):lower()
                        if name:find("tackle") or name:find("slide") or name:find("punch") or name:find("kick")
                           or id:find("slide") or id:find("tackle") then
                            isAttacking = true
                            break
                        end
                    end
                end

                -- Rakip 4 stud yakinimizdaysa veya saldiriyorsa FEINT BAS!
                if isAttacking or dist < 5 then
                    if SafeFire(Config.Combat.FeintRemoteName) then
                        _lastFeint = now
                    end
                end
            end
        end
    end

    -- 2. AUTO PARRY (SAVUNMA)
    if Config.Combat.AutoParry and now - _lastParry > Config.Combat.AutoParryDelay then
        local enemy, dist = GetNearestEnemy(Config.Combat.AutoParryRadius)
        if enemy and dist <= Config.Combat.AutoParryRadius then
            local c = enemy.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            local anim = hum and hum:FindFirstChildOfClass("Animator")
            if anim then
                for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                    local n = track.Animation.Name:lower()
                    if n:find("punch") or n:find("tackle") or n:find("slide") or n:find("hit") then
                        if SafeFire(Config.Combat.FeintRemoteName) then
                            _lastParry = now
                        end
                        break
                    end
                end
            end
        end
    end

    -- 3. AUTO TACKLE
    if Config.Combat.AutoTackle and now - _lastTackle > Config.Combat.TackleDelay then
        local ball = FindBall()
        if ball and not DoIHaveBall() then
            local enemy, dist = GetNearestEnemy(Config.Combat.TackleRange)
            if enemy then
                local er = enemy.Character and enemy.Character:FindFirstChild("HumanoidRootPart")
                if er and (er.Position - ball.Position).Magnitude < 4 then
                    -- Top rakipte!
                    myRoot.CFrame = CFrame.new(myRoot.Position, Vector3.new(er.Position.X, myRoot.Position.Y, er.Position.Z))
                    if SafeFire(Config.Combat.TackleRemoteName, enemy) then
                        _lastTackle = now
                    end
                end
            end
        end
    end

    -- 4. AUTO KNOCKOUT
    if Config.Combat.AutoKnockout and now - _lastKO > Config.Combat.KODelay then
        local enemy, dist = GetNearestEnemy(Config.Combat.KORange)
        if enemy and enemy.Character then
            local er = enemy.Character:FindFirstChild("HumanoidRootPart")
            if er then
                myRoot.CFrame = CFrame.new(myRoot.Position, Vector3.new(er.Position.X, myRoot.Position.Y, er.Position.Z))
                if SafeFire(Config.Combat.PunchRemoteName, enemy) then
                    _lastKO = now
                end
            end
        end
    end

    -- 5. GERCEK TOP MIKNATISI & CALMA (MAGNET REACH / AUTO STEAL)
    if Config.Ball.MagnetReach then
        local ball = FindBall()
        if ball and not DoIHaveBall() then
            local dist = (myRoot.Position - ball.Position).Magnitude
            if dist <= Config.Ball.ReachRadius and dist > 1.5 then
                -- Yontem 1: firetouchinterest (Executor destekliyorsa %100 calisir)
                if firetouchinterest then
                    pcall(function()
                        firetouchinterest(myRoot, ball, 0)
                        task.wait()
                        firetouchinterest(myRoot, ball, 1)
                    end)
                end

                -- Yontem 2: Blink Touch (Topun tam noktasina mikro temas yap)
                -- Boylece sunucu Network Ownership'i dogrudan oyuncuya verir
                local oldCF = myRoot.CFrame
                local ballPos = ball.Position
                myRoot.CFrame = CFrame.new(ballPos + Vector3.new(0, 0.5, 0))
                task.wait(0.03)
                myRoot.CFrame = oldCF

                -- Top serbestse hizi bize yonlendir
                if ball:IsA("BasePart") and ball.AssemblyLinearVelocity then
                    local pullDir = (myRoot.Position - ball.Position).Unit
                    ball.AssemblyLinearVelocity = pullDir * 60
                end
            end
        end
    end

    -- 6. HAREKET (SPEED & JUMP)
    local hum = GetHum()
    if hum then
        if Config.Movement.SpeedHack then
            hum.WalkSpeed = Clamp(Config.Movement.WalkSpeed, 16, Config.Movement.MaxWalkSpeed)
        end
        if Config.Movement.JumpPower then
            local h = Clamp(Config.Movement.JumpHeight, 7, 200)
            if hum.UseJumpPower then
                hum.JumpPower = math.sqrt(2 * workspace.Gravity * h)
            else
                hum.JumpHeight = h
            end
        end
    end
end))

-- B) SILENT AIM (SUT KONTROLU)
local function ApplySilentAim()
    local ball = FindBall()
    if not ball or not ball:IsA("BasePart") then return end
    local target = GetGoalCorner(Config.Ball.SilentAimCorner)
    if not target then return end

    local dir = (target - ball.Position).Unit
    local spd = math.max(ball.AssemblyLinearVelocity.Magnitude, 70)
    local s   = Clamp(Config.Ball.SilentAimStrength, 0.2, 1.0)
    ball.AssemblyLinearVelocity = Vector3.new(dir.X * spd * s, dir.Y * spd * s * 0.4 + 10, dir.Z * spd * s)
end

-- C) KAYMA BOOST (SLIDE VELOCITY BOOST)
-- DIKKAT: Ziplama (Freefall) kesinlikle KULLANILMIYOR!
-- Sadece zemin uzerinde gercek kayma aksiyonunda devreye girer
local function TriggerSlideBoost()
    local root = GetRoot()
    local hum  = GetHum()
    if not root or not hum then return end

    -- Sadece karakter yerdeyken calissin (Havada asla boost vermez!)
    if hum.FloorMaterial == Enum.Material.Air then return end

    local moveDir = hum.MoveDirection
    local dir = moveDir.Magnitude > 0.1 and moveDir.Unit or root.CFrame.LookVector
    local boostSpeed = (hum.WalkSpeed + 35) * Config.Movement.SlideMultiplier

    -- Anlik pürüzsüz CFrame + Lineer İvme
    root.AssemblyLinearVelocity = Vector3.new(dir.X * boostSpeed, root.AssemblyLinearVelocity.Y, dir.Z * boostSpeed)
end

-- Animasyon dinleyici ile kaymayi anla
local function HookSlideAnimation()
    local hum = GetHum()
    local anim = hum and hum:FindFirstChildOfClass("Animator")
    if not anim then return end

    AddConn(anim.AnimationPlayed:Connect(function(track)
        if not Config.Movement.SlideBoost then return end
        local n = track.Animation.Name:lower()
        local id = tostring(track.Animation.AnimationId):lower()
        if n:find("slide") or n:find("tackle") or n:find("kay") or n:find("dash")
           or id:find("slide") or id:find("tackle") then
            TriggerSlideBoost()
        end
    end))
end

HookSlideAnimation()
AddConn(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1.5)
    HookSlideAnimation()
end))

-- D) KUTU OTOMASYONU
task.spawn(function()
    while true do
        if Config.Items.BoxTeleport then
            pcall(function()
                local root = GetRoot()
                if not root then return end
                local boxes = FindAllBoxes()
                local nearest, minD = nil, math.huge
                for _, b in ipairs(boxes) do
                    local d = (root.Position - b.Position).Magnitude
                    if d < minD then minD = d; nearest = b end
                end
                if nearest then
                    if Config.Items.BoxPullMode == "Teleport" then
                        root.CFrame = CFrame.new(nearest.Position + Vector3.new(0, 3, 0))
                    else
                        nearest.CFrame = CFrame.new(root.Position + Vector3.new(0, 1, 0))
                    end
                end
            end)
        end
        task.wait(Config.Items.BoxScanInterval)
    end
end)

-- ===============================================================
-- 5. GERCEK CALISAN ESP SİSTEMİ (HIGHLIGHT + BILLBOARD)
-- ===============================================================

local ESPFolder = Instance.new("Folder")
ESPFolder.Name = "FU_ESP_Storage"
ESPFolder.Parent = GetSafeGuiParent()

local _espHighlights = {}
local _espBillboards = {}

-- 1. OYUNCU ESP (Duvar arkasi gorme + Isim/Mesafe)
local function UpdatePlayerESP()
    local myRoot = GetRoot()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            local head = char and char:FindFirstChild("Head")
            local root = char and char:FindFirstChild("HumanoidRootPart")

            if char and head and root and Config.ESP.PlayerESP and myRoot then
                local dist = (myRoot.Position - root.Position).Magnitude
                if dist <= Config.ESP.ESPMaxDistance then
                    -- Highlight (Karakterin etrafinda parlayan cizgi - DUVAR ARKASI)
                    local hl = _espHighlights[player.Name]
                    if not hl or hl.Parent ~= char then
                        if hl then hl:Destroy() end
                        hl = Instance.new("Highlight")
                        hl.Name = "FU_HL"
                        hl.FillColor = Color3.fromRGB(255, 60, 60)
                        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                        hl.FillTransparency = 0.5
                        hl.OutlineTransparency = 0.1
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.Adornee = char
                        hl.Parent = char
                        _espHighlights[player.Name] = hl
                    end
                    hl.Enabled = true

                    -- BillboardGui (Kafa ustu isim ve mesafe)
                    local bb = _espBillboards[player.Name]
                    if not bb or bb.Parent ~= head then
                        if bb then bb:Destroy() end
                        bb = Instance.new("BillboardGui")
                        bb.Name = "FU_Tag"
                        bb.Size = UDim2.new(0, 140, 0, 36)
                        bb.StudsOffset = Vector3.new(0, 2.5, 0)
                        bb.AlwaysOnTop = true
                        bb.Adornee = head
                        bb.Parent = head

                        local lbl = Instance.new("TextLabel", bb)
                        lbl.Name = "Txt"
                        lbl.Size = UDim2.fromScale(1, 1)
                        lbl.BackgroundTransparency = 1
                        lbl.TextColor3 = Color3.fromRGB(255, 240, 100)
                        lbl.TextStrokeTransparency = 0.3
                        lbl.Font = Enum.Font.GothamBold
                        lbl.TextSize = 12
                        lbl.TextWrapped = true
                        _espBillboards[player.Name] = bb
                    end
                    bb.Enabled = true
                    local txt = bb:FindFirstChild("Txt")
                    if txt then
                        txt.Text = string.format("%s\n[%.0f studs]", player.DisplayName or player.Name, dist)
                    end
                else
                    if _espHighlights[player.Name] then _espHighlights[player.Name].Enabled = false end
                    if _espBillboards[player.Name] then _espBillboards[player.Name].Enabled = false end
                end
            else
                if _espHighlights[player.Name] then _espHighlights[player.Name].Enabled = false end
                if _espBillboards[player.Name] then _espBillboards[player.Name].Enabled = false end
            end
        end
    end
end

-- 2. KUTU ESP (Sahadaki sandik/kutular)
local _boxBillboards = {}
local function UpdateBoxESP()
    local myRoot = GetRoot()
    if not Config.ESP.BoxESP or not myRoot then
        for _, b in pairs(_boxBillboards) do if b then b.Enabled = false end end
        return
    end

    local boxes = FindAllBoxes()
    for _, part in ipairs(boxes) do
        local dist = (myRoot.Position - part.Position).Magnitude
        if dist <= Config.ESP.ESPMaxDistance then
            local key = tostring(part)
            local bb = _boxBillboards[key]
            if not bb or bb.Parent ~= part then
                if bb then bb:Destroy() end
                bb = Instance.new("BillboardGui")
                bb.Name = "FU_BoxTag"
                bb.Size = UDim2.new(0, 120, 0, 30)
                bb.StudsOffset = Vector3.new(0, 2, 0)
                bb.AlwaysOnTop = true
                bb.Adornee = part
                bb.Parent = part

                local lbl = Instance.new("TextLabel", bb)
                lbl.Name = "Txt"
                lbl.Size = UDim2.fromScale(1, 1)
                lbl.BackgroundTransparency = 1
                lbl.TextColor3 = Color3.fromRGB(80, 255, 120)
                lbl.TextStrokeTransparency = 0.4
                lbl.Font = Enum.Font.GothamBold
                lbl.TextSize = 11
                _boxBillboards[key] = bb
            end
            bb.Enabled = true
            local txt = bb:FindFirstChild("Txt")
            if txt then
                txt.Text = string.format("📦 KUTU\n[%.0f st]", dist)
            end
        end
    end
end

-- 3. TOP YORUNGE TAHMINI (3D TRAJECTORY PREDICTOR)
local _trajFolder = Instance.new("Folder")
_trajFolder.Name = "FU_TrajPoints"
_trajFolder.Parent = workspace

local _trajPoints = {}
local function EnsureTrajPoints(count)
    while #_trajPoints < count do
        local p = Instance.new("Part")
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = false
        p.Material = Enum.Material.Neon
        p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(0.3, 0.3, 0.3)
        p.Color = Config.ESP.TrajectoryColor
        p.Parent = _trajFolder
        table.insert(_trajPoints, p)
    end
end

local function UpdateBallTrajectory()
    local ball = FindBall()
    if not Config.ESP.BallTrajectory or not ball or not ball:IsA("BasePart") then
        for _, p in ipairs(_trajPoints) do p.Transparency = 1 end
        return
    end

    local vel = ball.AssemblyLinearVelocity
    if vel.Magnitude < 4 then
        for _, p in ipairs(_trajPoints) do p.Transparency = 1 end
        return
    end

    local steps = Config.ESP.TrajectorySteps or 50
    EnsureTrajPoints(steps)

    local pos = ball.Position
    local g = -workspace.Gravity
    local dt = 1 / 45

    for i = 1, steps do
        vel = vel + Vector3.new(0, g, 0) * dt
        pos = pos + vel * dt

        local pt = _trajPoints[i]
        pt.CFrame = CFrame.new(pos)
        pt.Color = Config.ESP.TrajectoryColor
        pt.Transparency = 0.2 + (i / steps) * 0.7
    end
end

-- ESP Dongusu
AddConn(RunService.RenderStepped:Connect(function()
    pcall(UpdatePlayerESP)
    pcall(UpdateBoxESP)
    pcall(UpdateBallTrajectory)
end))

-- ===============================================================
-- 6. MOBIL GUI (TAM EKRAN UYUMLU, %100 GORUNUR)
-- ===============================================================

local THEME = {
    BG         = Color3.fromRGB(16, 16, 22),
    Surface    = Color3.fromRGB(24, 24, 34),
    SurfaceAlt = Color3.fromRGB(32, 32, 46),
    Accent     = Color3.fromRGB(70, 130, 255),
    AccentGlow = Color3.fromRGB(90, 160, 255),
    ON         = Color3.fromRGB(46, 204, 113),
    OFF        = Color3.fromRGB(70, 70, 85),
    TextMain   = Color3.fromRGB(245, 245, 255),
    TextSub    = Color3.fromRGB(160, 160, 190),
    Border     = Color3.fromRGB(55, 55, 75),
    Danger     = Color3.fromRGB(231, 76, 60),
}

local viewSize = (Camera and Camera.ViewportSize.X > 100) and Camera.ViewportSize or Vector2.new(800, 600)
local WIN_W = IS_MOBILE and math.clamp(viewSize.X - 30, 320, 520) or 540
local WIN_H = IS_MOBILE and math.clamp(viewSize.Y - 40, 280, 420) or 420
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

local guiRoot = MI("ScreenGui", {
    Name = "FU_GUI_V2",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
}, GetSafeGuiParent())

-- 📱 FLOATING MENU BUTONU (Mobilde her an acip kapatmak icin)
local floatBtn = MI("TextButton", {
    Name = "FloatToggle",
    Size = UDim2.new(0, 46, 0, 46),
    Position = UDim2.new(0, 14, 0.5, -23),
    BackgroundColor3 = THEME.Accent,
    Text = "⚽",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    BorderSizePixel = 0,
    ZIndex = 999,
}, guiRoot)
Corner(floatBtn, 23)
MI("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = 1.5, Transparency = 0.2 }, floatBtn)

-- Buton surukleme
do
    local drag, dragStart, startPos = false, nil, nil
    floatBtn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = true; dragStart = i.Position; startPos = floatBtn.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            floatBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    local function endDrag() drag = false end
    floatBtn.InputEnded:Connect(endDrag)
    UserInputService.InputEnded:Connect(endDrag)
end

-- Ana Cerceve
local mainFrame = MI("Frame", {
    Name = "MainFrame",
    Size = UDim2.new(0, WIN_W, 0, WIN_H),
    Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
    BackgroundColor3 = THEME.BG,
    BorderSizePixel = 0,
}, guiRoot)
Corner(mainFrame, 10)
MI("UIStroke", { Color = THEME.Border, Thickness = 1.2 }, mainFrame)

floatBtn.MouseButton1Click:Connect(function()
    mainFrame.Visible = not mainFrame.Visible
end)

-- Baslik
local titleBar = MI("Frame", {
    Size = UDim2.new(1, 0, 0, 44),
    BackgroundColor3 = THEME.Surface,
    BorderSizePixel = 0,
}, mainFrame)
Corner(titleBar, 10)
MI("Frame", { Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = THEME.Surface, BorderSizePixel = 0 }, titleBar)
MI("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), BackgroundColor3 = THEME.Accent, BorderSizePixel = 0 }, titleBar)

MI("TextLabel", {
    Size = UDim2.new(1, -90, 1, 0), Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1, Text = "⚽ FutbolUmsu v2.0 (Mobile Enhanced)",
    TextColor3 = THEME.TextMain, Font = Enum.Font.GothamBold, TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left,
}, titleBar)

local closeBtn = MI("TextButton", {
    Size = UDim2.new(0, 32, 0, 32), Position = UDim2.new(1, -38, 0.5, -16),
    BackgroundColor3 = THEME.Danger, Text = "✕", TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold, TextSize = 14, BorderSizePixel = 0,
}, titleBar)
Corner(closeBtn, 6)
closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

-- Sol Sekme Alani
local tabBar = MI("Frame", {
    Size = UDim2.new(0, TAB_W, 1, -44), Position = UDim2.new(0, 0, 0, 44),
    BackgroundColor3 = THEME.Surface, BorderSizePixel = 0,
}, mainFrame)
MI("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = THEME.Border, BorderSizePixel = 0 }, tabBar)

local tabList = MI("ScrollingFrame", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    BorderSizePixel = 0, ScrollBarThickness = 2,
    AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 260),
}, tabBar)
Padding(tabList, 8, 8, 6, 6)
MI("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 6) }, tabList)

-- Sag Icerik Alani
local contentArea = MI("Frame", {
    Size = UDim2.new(1, -TAB_W, 1, -44), Position = UDim2.new(0, TAB_W, 0, 44),
    BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
}, mainFrame)

-- Sekme Fonksiyonlari
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
        Size = UDim2.new(1, 0, 0, IS_MOBILE and 42 or 36),
        BackgroundColor3 = THEME.SurfaceAlt,
        Text = (icon and icon .. " " or "") .. name,
        TextColor3 = THEME.TextSub,
        Font = Enum.Font.GothamBold,
        TextSize = IS_MOBILE and 12 or 11,
        BorderSizePixel = 0, AutoButtonColor = false,
    }, tabList)
    Corner(btn, 6)

    local page = MI("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 5,
        ScrollBarImageColor3 = THEME.Accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(0, 0, 0, 650),
        Visible = false,
    }, contentArea)
    Padding(page, 10, 16, 10, 10)
    local pageLayout = MI("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 8) }, page)

    pageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0, 0, 0, pageLayout.AbsoluteContentSize.Y + 40)
    end)

    btn.MouseButton1Click:Connect(function() SelectTab(name) end)

    local tabObj = { name = name, btn = btn, page = page, totalH = 0 }

    function tabObj:AddSection(title)
        local sec = MI("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, self.page)
        MI("TextLabel", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
            Text = title, TextColor3 = THEME.AccentGlow,
            Font = Enum.Font.GothamBold, TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, sec)
        MI("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = THEME.Accent, BackgroundTransparency = 0.6, BorderSizePixel = 0 }, sec)
        self.totalH = self.totalH + 34
        self.page.CanvasSize = UDim2.new(0, 0, 0, self.totalH + 60)
    end

    function tabObj:AddToggle(title, defaultVal, callback, desc)
        local state = defaultVal or false
        local rowH = desc and (IS_MOBILE and 56 or 48) or (IS_MOBILE and 44 or 38)
        local row = MI("Frame", { Size = UDim2.new(1, 0, 0, rowH), BackgroundColor3 = THEME.SurfaceAlt, BorderSizePixel = 0 }, self.page)
        Corner(row, 6)
        Padding(row, 6, 6, 10, 10)

        MI("TextLabel", {
            Size = UDim2.new(1, -60, 0, 18), BackgroundTransparency = 1,
            Text = title, TextColor3 = THEME.TextMain,
            Font = Enum.Font.GothamBold, TextSize = IS_MOBILE and 13 or 12,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)

        if desc then
            MI("TextLabel", {
                Size = UDim2.new(1, -60, 0, 14), Position = UDim2.new(0, 0, 0, 20),
                BackgroundTransparency = 1, Text = desc, TextColor3 = THEME.TextSub,
                Font = Enum.Font.Gotham, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
            }, row)
        end

        local trackW, trackH = 46, 24
        local track = MI("Frame", {
            Size = UDim2.new(0, trackW, 0, trackH), Position = UDim2.new(1, -trackW, 0.5, -trackH / 2),
            BackgroundColor3 = state and THEME.ON or THEME.OFF, BorderSizePixel = 0,
        }, row)
        Corner(track, trackH / 2)

        local knobSize = trackH - 4
        local knob = MI("Frame", {
            Size = UDim2.new(0, knobSize, 0, knobSize),
            Position = state and UDim2.new(0, trackW - knobSize - 2, 0.5, -knobSize / 2) or UDim2.new(0, 2, 0.5, -knobSize / 2),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0,
        }, track)
        Corner(knob, knobSize / 2)

        local clickBtn = MI("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 10 }, row)
        local function Toggle(v)
            state = v
            TweenService:Create(track, TweenInfo.new(0.15), { BackgroundColor3 = state and THEME.ON or THEME.OFF }):Play()
            TweenService:Create(knob, TweenInfo.new(0.15), { Position = state and UDim2.new(0, trackW - knobSize - 2, 0.5, -knobSize / 2) or UDim2.new(0, 2, 0.5, -knobSize / 2) }):Play()
            pcall(callback, state)
        end
        clickBtn.MouseButton1Click:Connect(function() Toggle(not state) end)

        self.totalH = self.totalH + rowH + 8
        self.page.CanvasSize = UDim2.new(0, 0, 0, self.totalH + 60)
        return { Set = Toggle }
    end

    function tabObj:AddSlider(title, minVal, maxVal, defaultVal, callback, suffix)
        suffix = suffix or ""
        local val = math.clamp(defaultVal or minVal, minVal, maxVal)
        local rowH = IS_MOBILE and 58 or 52
        local row = MI("Frame", { Size = UDim2.new(1, 0, 0, rowH), BackgroundColor3 = THEME.SurfaceAlt, BorderSizePixel = 0 }, self.page)
        Corner(row, 6)
        Padding(row, 8, 8, 10, 10)

        local header = MI("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1 }, row)
        MI("TextLabel", {
            Size = UDim2.new(0.65, 0, 1, 0), BackgroundTransparency = 1,
            Text = title, TextColor3 = THEME.TextMain,
            Font = Enum.Font.GothamBold, TextSize = IS_MOBILE and 13 or 12,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, header)
        local valLbl = MI("TextLabel", {
            Size = UDim2.new(0.35, 0, 1, 0), Position = UDim2.new(0.65, 0, 0, 0),
            BackgroundTransparency = 1, Text = tostring(val) .. suffix,
            TextColor3 = THEME.AccentGlow, Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 13 or 12, TextXAlignment = Enum.TextXAlignment.Right,
        }, header)

        local track = MI("Frame", { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 0, 26), BackgroundColor3 = Color3.fromRGB(45, 45, 60), BorderSizePixel = 0 }, row)
        Corner(track, 4)
        local fill = MI("Frame", { Size = UDim2.new((val - minVal) / (maxVal - minVal), 0, 1, 0), BackgroundColor3 = THEME.Accent, BorderSizePixel = 0 }, track)
        Corner(fill, 4)

        local thumb = MI("Frame", {
            Size = UDim2.new(0, 16, 0, 16), AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new((val - minVal) / (maxVal - minVal), 0, 0.5, 0),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, ZIndex = 3,
        }, track)
        Corner(thumb, 8)

        local hitArea = MI("TextButton", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, -11), BackgroundTransparency = 1, Text = "", ZIndex = 10 }, track)
        local sliding = false
        local function Update(ix)
            local t = math.clamp((ix - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            local step = (maxVal - minVal) <= 10 and 0.1 or 1
            val = math.floor((minVal + (maxVal - minVal) * t) / step + 0.5) * step
            val = math.clamp(val, minVal, maxVal)
            fill.Size = UDim2.new(t, 0, 1, 0)
            thumb.Position = UDim2.new(t, 0, 0.5, 0)
            valLbl.Text = tostring(Round(val, 1)) .. suffix
            pcall(callback, val)
        end

        hitArea.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                sliding = true; Update(i.Position.X)
            end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                sliding = false
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                Update(i.Position.X)
            end
        end)

        self.totalH = self.totalH + rowH + 8
        self.page.CanvasSize = UDim2.new(0, 0, 0, self.totalH + 60)
    end

    function tabObj:AddButton(title, callback)
        local rowH = IS_MOBILE and 40 or 34
        local btn = MI("TextButton", {
            Size = UDim2.new(1, 0, 0, rowH), BackgroundColor3 = THEME.Accent,
            BackgroundTransparency = 0.25, Text = title, TextColor3 = THEME.TextMain,
            Font = Enum.Font.GothamBold, TextSize = IS_MOBILE and 13 or 12,
            BorderSizePixel = 0, AutoButtonColor = false,
        }, self.page)
        Corner(btn, 6)
        btn.MouseButton1Click:Connect(function() pcall(callback) end)
        self.totalH = self.totalH + rowH + 8
        self.page.CanvasSize = UDim2.new(0, 0, 0, self.totalH + 60)
    end

    function tabObj:AddDropdown(title, options, defaultVal, callback)
        local sel = defaultVal or options[1]
        local rowH = IS_MOBILE and 42 or 36
        local row = MI("Frame", { Size = UDim2.new(1, 0, 0, rowH), BackgroundColor3 = THEME.SurfaceAlt, BorderSizePixel = 0, ZIndex = 5 }, self.page)
        Corner(row, 6)
        Padding(row, 0, 0, 10, 10)

        MI("TextLabel", {
            Size = UDim2.new(0.55, 0, 1, 0), BackgroundTransparency = 1,
            Text = title, TextColor3 = THEME.TextMain, Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 13 or 12, TextXAlignment = Enum.TextXAlignment.Left,
        }, row)

        local curLbl = MI("TextLabel", {
            Size = UDim2.new(0.45, 0, 1, 0), Position = UDim2.new(0.55, 0, 0, 0),
            BackgroundTransparency = 1, Text = "▼ " .. tostring(sel),
            TextColor3 = THEME.AccentGlow, Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 12 or 11, TextXAlignment = Enum.TextXAlignment.Right,
        }, row)

        local dropPanel = MI("Frame", {
            Size = UDim2.new(1, 0, 0, #options * 30 + 8), Position = UDim2.new(0, 0, 1, 4),
            BackgroundColor3 = THEME.Surface, BorderSizePixel = 0, ZIndex = 20, Visible = false,
        }, row)
        Corner(dropPanel, 6)
        MI("UIStroke", { Color = THEME.Border, Thickness = 1 }, dropPanel)
        Padding(dropPanel, 4, 4, 4, 4)
        MI("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 2) }, dropPanel)

        for _, opt in ipairs(options) do
            local ob = MI("TextButton", {
                Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = THEME.SurfaceAlt,
                BackgroundTransparency = 0.5, Text = tostring(opt), TextColor3 = THEME.TextSub,
                Font = Enum.Font.GothamBold, TextSize = 11, BorderSizePixel = 0, ZIndex = 21,
            }, dropPanel)
            Corner(ob, 4)
            ob.MouseButton1Click:Connect(function()
                sel = opt; curLbl.Text = "▼ " .. tostring(opt)
                dropPanel.Visible = false; pcall(callback, opt)
            end)
        end

        local toggleDrop = MI("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 6 }, row)
        toggleDrop.MouseButton1Click:Connect(function() dropPanel.Visible = not dropPanel.Visible end)

        self.totalH = self.totalH + rowH + 8
        self.page.CanvasSize = UDim2.new(0, 0, 0, self.totalH + 60)
    end

    Tabs[name] = tabObj
    if not CurrentTab then SelectTab(name) end
    return tabObj
end

-- ===============================================================
-- 7. MENÜ ELEMANLARI
-- ===============================================================

-- 1. COMBAT
local tCombat = CreateTab("Combat", "⚔️")
tCombat:AddSection("🛡️ Top Koruma (Anti-Steal)")
tCombat:AddToggle("Anti-Steal Auto Feint", Config.Combat.AntiStealFeint, function(v) Config.Combat.AntiStealFeint = v end, "Top sendeyken rakip yaklasinca otomatik Feint")
tCombat:AddToggle("Auto Parry", Config.Combat.AutoParry, function(v) Config.Combat.AutoParry = v end, "Rakip vurus/kayma animasyonunda Feint")
tCombat:AddSlider("Parry Menzili", 4, 25, Config.Combat.AutoParryRadius, function(v) Config.Combat.AutoParryRadius = v end, " st")

tCombat:AddSection("🏃 Tackle & KO")
tCombat:AddToggle("Auto Tackle", Config.Combat.AutoTackle, function(v) Config.Combat.AutoTackle = v end, "Top rakipteyken otomatik kay")
tCombat:AddSlider("Tackle Menzili", 4, 25, Config.Combat.TackleRange, function(v) Config.Combat.TackleRange = v end, " st")
tCombat:AddToggle("Auto Knockout", Config.Combat.AutoKnockout, function(v) Config.Combat.AutoKnockout = v end, "Menzildeki rakibe yumruk spamla")
tCombat:AddSlider("KO Menzili", 3, 18, Config.Combat.KORange, function(v) Config.Combat.KORange = v end, " st")

-- 2. BALL / GOAL
local tBall = CreateTab("Ball", "⚽")
tBall:AddSection("🎯 Şut Yönlendirme (Silent Aim)")
tBall:AddToggle("Silent Aim", Config.Ball.SilentAim, function(v) Config.Ball.SilentAim = v end, "Sut cekince top kalenin kosesine gider")
tBall:AddDropdown("Hedef Köşe", { "BottomLeft", "BottomRight", "TopLeft", "TopRight", "Center" }, Config.Ball.SilentAimCorner, function(v) Config.Ball.SilentAimCorner = v end)
tBall:AddSlider("Aim Gücü", 0.2, 1.0, Config.Ball.SilentAimStrength, function(v) Config.Ball.SilentAimStrength = v end, "x")
tBall:AddButton("⚽ Manuel Aim Uygula", function() pcall(ApplySilentAim) end)

tBall:AddSection("🧲 Top Mıknatısı (Real Touch Reach)")
tBall:AddToggle("Magnet Reach", Config.Ball.MagnetReach, function(v) Config.Ball.MagnetReach = v end, "Menzildeki topu fiziksel olarak ayagina alir")
tBall:AddSlider("Reach Menzili", 5, 45, Config.Ball.ReachRadius, function(v) Config.Ball.ReachRadius = v end, " st")

-- 3. ESP
local tESP = CreateTab("ESP", "👁️")
tESP:AddSection("👁️ Görsel Analiz (ESP)")
tESP:AddToggle("Oyuncu ESP (Duvar Arkası)", Config.ESP.PlayerESP, function(v) Config.ESP.PlayerESP = v end, "Rakipleri duvar arkasindan parlatir ve mesafeyi yazar")
tESP:AddToggle("Kutu / Sandık ESP", Config.ESP.BoxESP, function(v) Config.ESP.BoxESP = v end, "Sahadaki esya kutularini gosterir")
tESP:AddToggle("Top Yörünge Çizgisi", Config.ESP.BallTrajectory, function(v) Config.ESP.BallTrajectory = v end, "Topun ucacagi ve dusecegi yeri 3D cizer")
tESP:AddSlider("ESP Görüş Menzili", 50, 400, Config.ESP.ESPMaxDistance, function(v) Config.ESP.ESPMaxDistance = v end, " st")

-- 4. ITEMS
local tItems = CreateTab("Items", "📦")
tItems:AddSection("📦 Kutu Mıknatısı / Teleport")
tItems:AddToggle("Kutu Auto-Collect", Config.Items.BoxTeleport, function(v) Config.Items.BoxTeleport = v end, "Sahadaki kutulara otomatik gider")
tItems:AddDropdown("Toplama Modu", { "Teleport", "Pull" }, Config.Items.BoxPullMode, function(v) Config.Items.BoxPullMode = v end)
tItems:AddSlider("Tarama Aralığı", 0.2, 3.0, Config.Items.BoxScanInterval, function(v) Config.Items.BoxScanInterval = v end, "s")

-- 5. MOVEMENT
local tMove = CreateTab("Move", "🏃")
tMove:AddSection("⚡ Hız & Zıplama")
tMove:AddToggle("Speed Hack", Config.Movement.SpeedHack, function(v) Config.Movement.SpeedHack = v end)
tMove:AddSlider("Yürüme Hızı", 16, 100, Config.Movement.WalkSpeed, function(v) Config.Movement.WalkSpeed = v end, " ws")
tMove:AddToggle("Jump Power", Config.Movement.JumpPower, function(v) Config.Movement.JumpPower = v end)
tMove:AddSlider("Zıplama Yüksekliği", 7, 150, Config.Movement.JumpHeight, function(v) Config.Movement.JumpHeight = v end, " st")

tMove:AddSection("💨 Kayma Boost (Slide Boost)")
tMove:AddToggle("Kayma Hızlandırma", Config.Movement.SlideBoost, function(v) Config.Movement.SlideBoost = v end, "Sadece kayarken ekstra ileri ivme verir")
tMove:AddSlider("Slide Çarpanı", 1.0, 6.0, Config.Movement.SlideMultiplier, function(v) Config.Movement.SlideMultiplier = v end, "x")
tMove:AddButton("💨 Anlık Slide Boost Bas", function() TriggerSlideBoost() end)

-- Varsayilan acilis22:46 7.09.2026
SelectTab("Combat")

-- Temizlik
local function FullCleanup()
    DisconnectAll()
    pcall(function() guiRoot:Destroy() end)
    pcall(function() ESPFolder:Destroy() end)
    pcall(function() _trajFolder:Destroy() end)
    local hum = GetHum()
    if hum then hum.WalkSpeed = 16; hum.JumpHeight = 7.2 end
    print("[FutbolUmsu v2.0] Kapatildi.")
end

if getgenv then
    getgenv()._FU_Loaded = true
    getgenv()._FU_Stop   = FullCleanup
    getgenv()._FU_Config = Config
end

print("=================================================")
print("  ⚽ FutbolUmsu v2.0 Başarıyla Yüklendi!")
print("  📱 Sol taraftaki ⚽ butonuna basarak aç/kapat!")
print("=================================================")
