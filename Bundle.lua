--[[
==================================================================
        ⚽ FutbolUmsu · Script.lua (V2.5 - By Umut)
  Delta X · Arceus X · Hydrogen · Fluxus · Codex · KRNL Destekli
  Modern Cyber Dark UI · Mobil & PC Uyumlu · Full Standalone
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

-- Sahadaki Topu Bul (Gelistirilmis Akilli Arama)
local _cachedBall = nil
local _lastBallSearch = 0

local function FindBall()
    local now = tick()
    if _cachedBall and _cachedBall.Parent and _cachedBall:IsA("BasePart") and (now - _lastBallSearch < 0.4) then
        return _cachedBall
    end
    _lastBallSearch = now

    -- 1. Workspace direkt config ismi
    if Config.Ball.BallName and Config.Ball.BallName ~= "" then
        local b = workspace:FindFirstChild(Config.Ball.BallName, true)
        if b and b:IsA("BasePart") then
            _cachedBall = b
            return b
        end
    end

    -- 2. CollectionService Tag ile
    local tagged = CollectionService:GetTagged("Ball")
    if tagged and #tagged > 0 then
        for _, t in ipairs(tagged) do
            if t:IsA("BasePart") then _cachedBall = t; return t end
            local bp = t:FindFirstChildOfClass("BasePart")
            if bp then _cachedBall = bp; return bp end
        end
    end

    -- 3. Workspace altındaki yaygın futbol topu isimleri
    local commonNames = {"ball", "football", "soccerball", "soccer_ball", "tpsball", "gameball"}
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") then
            local n = v.Name:lower()
            for _, cname in ipairs(commonNames) do
                if n == cname or n:find(cname) then
                    -- Top boyut filtresi (çap 0.6 ile 10 studs arası)
                    local sz = v.Size.Magnitude
                    if sz > 0.6 and sz < 12 then
                        _cachedBall = v
                        return v
                    end
                end
            end
        end
    end

    return _cachedBall
end

-- Top Sende mi? (Cok Katmanli Hassas Algilama)
local function DoIHaveBall()
    local ball = FindBall()
    local root = GetRoot()
    local char = GetChar()
    if not ball or not root or not char then return false end

    -- 1. Karakter modeline bagli mi? (Weld, Motor6D, Parent)
    if ball:IsDescendantOf(char) then return true end
    for _, child in ipairs(char:GetDescendants()) do
        if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
            if child.Part0 == ball or child.Part1 == ball then
                return true
            end
        end
    end

    -- 2. Attribute / Value kontrolu (Oyunun sahiplik verisi)
    local ownerAttr = ball:GetAttribute("Owner") or ball:GetAttribute("Possession") or ball:GetAttribute("Holder") or ball:GetAttribute("Player")
    if ownerAttr then
        local attrStr = tostring(ownerAttr):lower()
        if attrStr == LocalPlayer.Name:lower() or attrStr == tostring(LocalPlayer.UserId) then
            return true
        end
    end
    local ownerVal = ball:FindFirstChild("Owner") or ball:FindFirstChild("Possession") or ball:FindFirstChild("Holder")
    if ownerVal and ownerVal:IsA("ValueBase") then
        if ownerVal.Value == LocalPlayer or ownerVal.Value == char or tostring(ownerVal.Value):lower() == LocalPlayer.Name:lower() then
            return true
        end
    end

    -- 3. Dinamik Mesafe & En Yakin Oyuncu Kontrolu
    local dist = (root.Position - ball.Position).Magnitude
    if dist <= 6.5 then
        -- Topa bizden daha yakin baska rakip var mi?
        local isClosest = true
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local pr = p.Character:FindFirstChild("HumanoidRootPart")
                if pr and (pr.Position - ball.Position).Magnitude < (dist - 0.7) then
                    isClosest = false
                    break
                end
            end
        end
        return isClosest
    end

    return false
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

-- Remote Bul ve Calistir (Gelistirilmis Coklu Arama)
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
    if r then
        if r:IsA("RemoteEvent") then
            pcall(r.FireServer, r, ...)
            return true
        elseif r:IsA("RemoteFunction") then
            pcall(r.InvokeServer, r, ...)
            return true
        end
    end
    return false
end

-- Birden fazla adayi sirayla dener
local function SafeFireAny(candidateNames, ...)
    for _, cname in ipairs(candidateNames) do
        if SafeFire(cname, ...) then
            return true
        end
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

-- A) OYUN MOTORU DÖNGÜSÜ (HEARTBEAT)
AddConn(RunService.Heartbeat:Connect(function()
    local now = tick()
    local myRoot = GetRoot()
    local char = GetChar()
    if not myRoot or not char then return end

    -- ─────────────────────────────────────────────────────────
    -- 1. TOP KAYBETMEME (ANTI-STEAL & BALL PROTECTION & SHIELDING)
    -- ─────────────────────────────────────────────────────────
    if Config.Combat.AntiStealFeint and DoIHaveBall() then
        pcall(function()
            local ball = FindBall()
            if not ball then return end

            -- Yere düşmeyi / sendelemeyi engelle (Anti-Ragdoll / Anti-Trip)
            local hum = GetHum()
            if hum then
                hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                if hum.PlatformStand then hum.PlatformStand = false end
                if hum.Sit then hum.Sit = false end
            end

            local enemy, dist = GetNearestEnemy(10)
            if enemy and enemy.Character then
                local er = enemy.Character:FindFirstChild("HumanoidRootPart")
                local ehum = enemy.Character:FindFirstChildOfClass("Humanoid")
                if er then
                    local isAttacking = false

                    -- Animasyon kontrolü (Pcall korumalı, nil hatası vermez)
                    local anim = ehum and ehum:FindFirstChildOfClass("Animator")
                    if anim then
                        for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                            pcall(function()
                                if track and track.Animation then
                                    local name = tostring(track.Animation.Name):lower()
                                    local id = tostring(track.Animation.AnimationId):lower()
                                    if name:find("tackle") or name:find("slide") or name:find("punch") or name:find("kick")
                                       or id:find("slide") or id:find("tackle") or id:find("punch") then
                                        isAttacking = true
                                    end
                                end
                            end)
                            if isAttacking then break end
                        end
                    end

                    -- Rakibin ani kayma hızı tespiti
                    if er.AssemblyLinearVelocity and er.AssemblyLinearVelocity.Magnitude > 28 then
                        isAttacking = true
                    end

                    -- A) TEHLİKE ANINDA ÇALIM / FEINT BAS
                    if (isAttacking or dist < 5.5) and (now - _lastFeint > 0.35) then
                        local feintList = { Config.Combat.FeintRemoteName, "Feint", "BodyFeint", "Dodge", "Evade", "Trick", "Skill" }
                        if SafeFireAny(feintList) then
                            _lastFeint = now
                        end
                    end

                    -- B) FİZİKSEL TOP KALKANI (BALL SHIELDING)
                    -- Topu rakibin erişemeyeceği TAM TERSİNE saklar! Rakip kayarsa boşa düşer.
                    local oppDir = (myRoot.Position - er.Position).Unit
                    local shieldPos = myRoot.Position + (oppDir * 1.9) - Vector3.new(0, 1.2, 0)
                    if ball:IsA("BasePart") then
                        ball.CFrame = CFrame.new(shieldPos)
                        ball.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                    end
                end
            else
                -- Rakip uzaktaysa topu ayağımızın hemen önünde güvenle tut
                if ball:IsA("BasePart") and ball.AssemblyLinearVelocity.Magnitude > 40 then
                    ball.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                end
            end
        end)
    end

    -- ─────────────────────────────────────────────────────────
    -- 2. AUTO PARRY (SAVUNMA)
    -- ─────────────────────────────────────────────────────────
    if Config.Combat.AutoParry and now - _lastParry > Config.Combat.AutoParryDelay then
        pcall(function()
            local enemy, dist = GetNearestEnemy(Config.Combat.AutoParryRadius)
            if enemy and dist <= Config.Combat.AutoParryRadius and enemy.Character then
                local hum = enemy.Character:FindFirstChildOfClass("Humanoid")
                local anim = hum and hum:FindFirstChildOfClass("Animator")
                if anim then
                    for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                        local triggered = false
                        pcall(function()
                            if track and track.Animation then
                                local n = tostring(track.Animation.Name):lower()
                                local id = tostring(track.Animation.AnimationId):lower()
                                if n:find("punch") or n:find("tackle") or n:find("slide") or n:find("hit") or id:find("slide") then
                                    local feintList = { Config.Combat.FeintRemoteName, "Feint", "BodyFeint", "Dodge", "Evade" }
                                    if SafeFireAny(feintList) then
                                        _lastParry = now
                                        triggered = true
                                    end
                                end
                            end
                        end)
                        if triggered then break end
                    end
                end
            end
        end)
    end

    -- ─────────────────────────────────────────────────────────
    -- 3. AUTO TACKLE
    -- ─────────────────────────────────────────────────────────
    if Config.Combat.AutoTackle and now - _lastTackle > Config.Combat.TackleDelay then
        pcall(function()
            local ball = FindBall()
            if ball and not DoIHaveBall() then
                local enemy, dist = GetNearestEnemy(Config.Combat.TackleRange)
                if enemy and enemy.Character then
                    local er = enemy.Character:FindFirstChild("HumanoidRootPart")
                    if er and (er.Position - ball.Position).Magnitude < 4.5 then
                        -- Top rakipte!
                        myRoot.CFrame = CFrame.new(myRoot.Position, Vector3.new(er.Position.X, myRoot.Position.Y, er.Position.Z))
                        local tackleList = { Config.Combat.TackleRemoteName, "Tackle", "Slide", "Steal" }
                        if SafeFireAny(tackleList, enemy) then
                            _lastTackle = now
                        end
                    end
                end
            end
        end)
    end

    -- ─────────────────────────────────────────────────────────
    -- 4. AUTO KNOCKOUT
    -- ─────────────────────────────────────────────────────────
    if Config.Combat.AutoKnockout and now - _lastKO > Config.Combat.KODelay then
        pcall(function()
            local enemy, dist = GetNearestEnemy(Config.Combat.KORange)
            if enemy and enemy.Character then
                local er = enemy.Character:FindFirstChild("HumanoidRootPart")
                if er then
                    myRoot.CFrame = CFrame.new(myRoot.Position, Vector3.new(er.Position.X, myRoot.Position.Y, er.Position.Z))
                    local punchList = { Config.Combat.PunchRemoteName, "Punch", "Hit", "Attack" }
                    if SafeFireAny(punchList, enemy) then
                        _lastKO = now
                    end
                end
            end
        end)
    end

    -- ─────────────────────────────────────────────────────────
    -- 5. GERÇEK TOP ÇEKME & AYAĞA ALMA (MAGNET REACH / AUTO PULL)
    -- ─────────────────────────────────────────────────────────
    -- DİKKAT: Karakter ASLA topa ışınlanmaz! Top doğrudan ayağımıza çekilir.
    if Config.Ball.MagnetReach then
        pcall(function()
            local ball = FindBall()
            if ball and not DoIHaveBall() then
                local dist = (myRoot.Position - ball.Position).Magnitude
                if dist <= Config.Ball.ReachRadius and dist > 1.2 then
                    -- Ayak seviyesinde hedef nokta (karakterin 2 stud önü)
                    local footTarget = myRoot.Position + (myRoot.CFrame.LookVector * 2.0) - Vector3.new(0, 1.2, 0)

                    -- 1. Fiziksel Çekim (Velocity & CFrame)
                    if ball:IsA("BasePart") then
                        local pullDir = (footTarget - ball.Position)
                        local pullSpeed = math.clamp(pullDir.Magnitude * 32, 45, 95)

                        -- Topu doğrudan ayağa doğru fırlat/çek
                        ball.AssemblyLinearVelocity = pullDir.Unit * pullSpeed
                        ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                        pcall(function() ball.Velocity = pullDir.Unit * pullSpeed end)

                        -- Top 3.5 stud yakına geldiğinde ayağın önüne sabitle
                        if dist < 3.8 then
                            ball.CFrame = CFrame.new(footTarget)
                        end
                    end

                    -- 2. Ayak ile Temas Tetikleme (firetouchinterest)
                    -- Oyunun top sahipliğini anında vermesi için ayaklarla temas simüle edilir
                    if firetouchinterest then
                        local touchParts = {
                            char:FindFirstChild("Right Leg") or char:FindFirstChild("RightFoot"),
                            char:FindFirstChild("Left Leg") or char:FindFirstChild("LeftFoot"),
                            myRoot
                        }
                        for _, leg in ipairs(touchParts) do
                            if leg then
                                pcall(firetouchinterest, leg, ball, 0)
                                pcall(firetouchinterest, leg, ball, 1)
                                pcall(firetouchinterest, ball, leg, 0)
                                pcall(firetouchinterest, ball, leg, 1)
                            end
                        end
                    end
                end
            end
        end)
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
-- 6. PROFESYONEL MOBİL & PC GUI (BY UMUT - MODERN CYBER DARK)
-- ===============================================================

local THEME = {
    BG          = Color3.fromRGB(12, 14, 20),
    Sidebar     = Color3.fromRGB(17, 20, 29),
    Surface     = Color3.fromRGB(22, 26, 38),
    SurfaceHover= Color3.fromRGB(28, 34, 50),
    Border      = Color3.fromRGB(38, 46, 68),
    BorderGlow  = Color3.fromRGB(0, 180, 255),
    Accent      = Color3.fromRGB(0, 175, 255),
    AccentAlt   = Color3.fromRGB(115, 80, 255),
    ON          = Color3.fromRGB(0, 230, 135),
    OFF         = Color3.fromRGB(48, 54, 72),
    TextMain    = Color3.fromRGB(248, 250, 255),
    TextSub     = Color3.fromRGB(145, 155, 178),
    Gold        = Color3.fromRGB(255, 205, 55),
    Danger      = Color3.fromRGB(255, 75, 95),
}

local viewSize = (Camera and Camera.ViewportSize.X > 100) and Camera.ViewportSize or Vector2.new(800, 600)
local WIN_W = IS_MOBILE and math.clamp(viewSize.X - 24, 320, 520) or 560
local WIN_H = IS_MOBILE and math.clamp(viewSize.Y - 32, 280, 390) or 410
local TAB_W = IS_MOBILE and 110 or 135

local function MI(cls, props, parent)
    local inst = Instance.new(cls)
    for k, v in pairs(props) do inst[k] = v end
    inst.Parent = parent
    return inst
end

local function Corner(p, r)
    return MI("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p)
end

local function Padding(p, t, b, l, r)
    return MI("UIPadding", {
        PaddingTop = UDim.new(0, t or 6),
        PaddingBottom = UDim.new(0, b or 6),
        PaddingLeft = UDim.new(0, l or 8),
        PaddingRight = UDim.new(0, r or 8)
    }, p)
end

local function Stroke(p, col, thick, trans)
    return MI("UIStroke", {
        Color = col or THEME.Border,
        Thickness = thick or 1,
        Transparency = trans or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, p)
end

local guiRoot = MI("ScreenGui", {
    Name = "FU_GUI_PRO_V3",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
}, GetSafeGuiParent())

-- ===============================================================
-- ✨ BY UMUT - SİNEMATİK AÇILIŞ EKRANI (SPLASH INTRO)
-- ===============================================================
task.spawn(function()
    local splashOverlay = MI("Frame", {
        Name = "SplashOverlay",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ZIndex = 2500,
    }, guiRoot)

    local splashCard = MI("Frame", {
        Name = "SplashCard",
        Size = UDim2.new(0, 320, 0, 165),
        Position = UDim2.new(0.5, -160, 0.5, -82),
        BackgroundColor3 = THEME.BG,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 2501,
    }, splashOverlay)
    Corner(splashCard, 14)
    Stroke(splashCard, THEME.Accent, 1.8, 0.1)

    -- Parlak Üst Gradient Çizgisi
    local topBar = MI("Frame", {
        Size = UDim2.new(1, 0, 0, 3),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        ZIndex = 2502,
    }, splashCard)
    local uig = MI("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, THEME.Accent),
            ColorSequenceKeypoint.new(0.5, THEME.Gold),
            ColorSequenceKeypoint.new(1, THEME.AccentAlt),
        })
    }, topBar)

    MI("TextLabel", {
        Size = UDim2.new(1, 0, 0, 38),
        Position = UDim2.new(0, 0, 0, 18),
        BackgroundTransparency = 1,
        Text = "⚽ FUTBOLUMSU",
        TextColor3 = THEME.TextMain,
        Font = Enum.Font.GothamBold,
        TextSize = 22,
        ZIndex = 2502,
    }, splashCard)

    -- BY UMUT ROZETİ
    local byBadge = MI("Frame", {
        Size = UDim2.new(0, 140, 0, 24),
        Position = UDim2.new(0.5, -70, 0, 58),
        BackgroundColor3 = Color3.fromRGB(32, 28, 16),
        BorderSizePixel = 0,
        ZIndex = 2502,
    }, splashCard)
    Corner(byBadge, 12)
    Stroke(byBadge, THEME.Gold, 1.2, 0.2)

    MI("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "✨ By Umut ✨",
        TextColor3 = THEME.Gold,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        ZIndex = 2503,
    }, byBadge)

    MI("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18),
        Position = UDim2.new(0, 0, 0, 88),
        BackgroundTransparency = 1,
        Text = "Mobil & PC En İyi Performans Yüklendi",
        TextColor3 = THEME.TextSub,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        ZIndex = 2502,
    }, splashCard)

    -- Progress Bar
    local loadTrack = MI("Frame", {
        Size = UDim2.new(0.85, 0, 0, 6),
        Position = UDim2.new(0.075, 0, 0, 125),
        BackgroundColor3 = THEME.Surface,
        BorderSizePixel = 0,
        ZIndex = 2502,
    }, splashCard)
    Corner(loadTrack, 3)

    local loadFill = MI("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        ZIndex = 2503,
    }, loadTrack)
    Corner(loadFill, 3)

    -- Dolum Animasyonu
    TweenService:Create(loadFill, TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Size = UDim2.new(1, 0, 1, 0)
    }):Play()

    task.wait(1.4)

    -- Fade Out & Kapanış
    TweenService:Create(splashCard, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
        Position = UDim2.new(0.5, -160, 0.4, -82),
        BackgroundTransparency = 1
    }):Play()
    local t = TweenService:Create(splashOverlay, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
    t:Play()
    t.Completed:Connect(function()
        splashOverlay:Destroy()
    end)
end)

-- ===============================================================
-- 📱 YÜZEN MOBİL BUTON (FLOAT BUTTON)
-- ===============================================================
local floatBtn = MI("TextButton", {
    Name = "FloatToggle",
    Size = UDim2.new(0, 50, 0, 50),
    Position = UDim2.new(0, 16, 0.5, -25),
    BackgroundColor3 = THEME.Sidebar,
    Text = "⚽",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 24,
    BorderSizePixel = 0,
    ZIndex = 1200,
    AutoButtonColor = false,
}, guiRoot)
Corner(floatBtn, 25)
Stroke(floatBtn, THEME.Accent, 1.8, 0.1)

-- Altında Mini By Umut Rozeti
local miniTag = MI("TextLabel", {
    Size = UDim2.new(0, 56, 0, 14),
    Position = UDim2.new(0.5, -28, 1, 2),
    BackgroundColor3 = Color3.fromRGB(15, 18, 26),
    Text = "By Umut",
    TextColor3 = THEME.Gold,
    Font = Enum.Font.GothamBold,
    TextSize = 9,
    BorderSizePixel = 0,
    ZIndex = 1201,
}, floatBtn)
Corner(miniTag, 4)
Stroke(miniTag, THEME.Gold, 1, 0.4)

-- Buton Dokunmatik & Fare ile Sürükleme
do
    local drag, dragStart, startPos = false, nil, nil
    floatBtn.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = true
            dragStart = i.Position
            startPos = floatBtn.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local delta = i.Position - dragStart
            floatBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    local function stopDrag() drag = false end
    floatBtn.InputEnded:Connect(stopDrag)
    UserInputService.InputEnded:Connect(stopDrag)
end

-- ===============================================================
-- 🖥️ ANA PENCERE (MAIN FRAME)
-- ===============================================================
local mainFrame = MI("Frame", {
    Name = "MainFrame",
    Size = UDim2.new(0, WIN_W, 0, WIN_H),
    Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
    BackgroundColor3 = THEME.BG,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Visible = true,
}, guiRoot)
Corner(mainFrame, 12)
Stroke(mainFrame, THEME.Border, 1.4)

floatBtn.MouseButton1Click:Connect(function()
    mainFrame.Visible = not mainFrame.Visible
end)

-- ─────────────────────────────────────────────────────────
-- BAŞLIK ÇUBUĞU (HEADER)
-- ─────────────────────────────────────────────────────────
local header = MI("Frame", {
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundColor3 = THEME.Sidebar,
    BorderSizePixel = 0,
}, mainFrame)
Corner(header, 12)
-- Alt köşelerin yuvarlaklığını düzeltmek için alt dolgu
MI("Frame", { Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10), BackgroundColor3 = THEME.Sidebar, BorderSizePixel = 0 }, header)
MI("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = THEME.Border, BorderSizePixel = 0 }, header)

-- Başlık Sürükleme
do
    local drag, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = true
            dragStart = i.Position
            startPos = mainFrame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local delta = i.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    local function endHeaderDrag() drag = false end
    header.InputEnded:Connect(endHeaderDrag)
    UserInputService.InputEnded:Connect(endHeaderDrag)
end

-- Sol Logo & Başlık
local titleTxt = MI("TextLabel", {
    Size = UDim2.new(0, 160, 1, 0),
    Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1,
    Text = "⚽ FutbolUmsu",
    TextColor3 = THEME.TextMain,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

-- Altın Sarısı BY UMUT Rozeti
local headerBadge = MI("Frame", {
    Size = UDim2.new(0, 80, 0, 20),
    Position = UDim2.new(0, 135, 0.5, -10),
    BackgroundColor3 = Color3.fromRGB(36, 32, 18),
    BorderSizePixel = 0,
}, header)
Corner(headerBadge, 6)
Stroke(headerBadge, THEME.Gold, 1, 0.3)

MI("TextLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "BY UMUT",
    TextColor3 = THEME.Gold,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
}, headerBadge)

-- Kapatma & Gizleme Butonları
local closeBtn = MI("TextButton", {
    Size = UDim2.new(0, 30, 0, 30),
    Position = UDim2.new(1, -38, 0.5, -15),
    BackgroundColor3 = Color3.fromRGB(35, 20, 25),
    Text = "✕",
    TextColor3 = THEME.Danger,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    BorderSizePixel = 0,
    AutoButtonColor = false,
}, header)
Corner(closeBtn, 6)
Stroke(closeBtn, THEME.Danger, 1, 0.5)
closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

local minBtn = MI("TextButton", {
    Size = UDim2.new(0, 30, 0, 30),
    Position = UDim2.new(1, -74, 0.5, -15),
    BackgroundColor3 = THEME.Surface,
    Text = "—",
    TextColor3 = THEME.TextSub,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    BorderSizePixel = 0,
    AutoButtonColor = false,
}, header)
Corner(minBtn, 6)
Stroke(minBtn, THEME.Border, 1)
minBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

-- ─────────────────────────────────────────────────────────
-- SOL SEKME MENÜSÜ (SIDEBAR)
-- ─────────────────────────────────────────────────────────
local sidebar = MI("Frame", {
    Size = UDim2.new(0, TAB_W, 1, -46),
    Position = UDim2.new(0, 0, 0, 46),
    BackgroundColor3 = THEME.Sidebar,
    BorderSizePixel = 0,
}, mainFrame)
MI("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = THEME.Border, BorderSizePixel = 0 }, sidebar)

local tabList = MI("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, -28),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, sidebar)
Padding(tabList, 10, 10, 8, 8)
MI("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 6) }, tabList)

-- Alt İmza
local footerSign = MI("TextLabel", {
    Size = UDim2.new(1, 0, 0, 24),
    Position = UDim2.new(0, 0, 1, -24),
    BackgroundTransparency = 1,
    Text = "v2.5 • By Umut",
    TextColor3 = Color3.fromRGB(100, 110, 135),
    Font = Enum.Font.Gotham,
    TextSize = 10,
}, sidebar)

-- ─────────────────────────────────────────────────────────
-- SAĞ İÇERİK ALANI (CONTENT AREA)
-- ─────────────────────────────────────────────────────────
local contentArea = MI("Frame", {
    Size = UDim2.new(1, -TAB_W, 1, -46),
    Position = UDim2.new(0, TAB_W, 0, 46),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, mainFrame)

local Tabs = {}
local CurrentTab = nil

local function SelectTab(name)
    if CurrentTab and Tabs[CurrentTab] then
        Tabs[CurrentTab].page.Visible = false
        Tabs[CurrentTab].btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        Tabs[CurrentTab].btn.BackgroundTransparency = 1
        Tabs[CurrentTab].btn.TextColor3 = THEME.TextSub
        if Tabs[CurrentTab].indicator then Tabs[CurrentTab].indicator.Visible = false end
    end
    CurrentTab = name
    if Tabs[name] then
        Tabs[name].page.Visible = true
        Tabs[name].btn.BackgroundColor3 = THEME.Surface
        Tabs[name].btn.BackgroundTransparency = 0
        Tabs[name].btn.TextColor3 = THEME.TextMain
        if Tabs[name].indicator then Tabs[name].indicator.Visible = true end
    end
end

local function CreateTab(name, icon)
    local btn = MI("TextButton", {
        Size = UDim2.new(1, 0, 0, IS_MOBILE and 40 or 36),
        BackgroundColor3 = THEME.Surface,
        BackgroundTransparency = 1,
        Text = (icon and icon .. "  " or "") .. name,
        TextColor3 = THEME.TextSub,
        Font = Enum.Font.GothamBold,
        TextSize = IS_MOBILE and 12 or 11,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, tabList)
    Corner(btn, 7)
    Padding(btn, 0, 0, 12, 6)

    -- Sol tarafındaki aktif mavi neon çizgi
    local indicator = MI("Frame", {
        Size = UDim2.new(0, 3, 0.6, 0),
        Position = UDim2.new(0, -6, 0.2, 0),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Visible = false,
    }, btn)
    Corner(indicator, 2)

    local page = MI("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.Accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, contentArea)
    Padding(page, 10, 16, 12, 12)
    local pageLayout = MI("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 8) }, page)

    btn.MouseButton1Click:Connect(function() SelectTab(name) end)

    local tabObj = { name = name, btn = btn, indicator = indicator, page = page }

    -- Başlık Bölümü (Section)
    function tabObj:AddSection(title)
        local sec = MI("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, self.page)
        MI("TextLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = string.upper(title),
            TextColor3 = THEME.Accent,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, sec)
        local line = MI("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            Position = UDim2.new(0, 0, 1, -2),
            BackgroundColor3 = THEME.Border,
            BorderSizePixel = 0,
        }, sec)
    end

    -- Modern Toggle (Aç/Kapa Switch)
    function tabObj:AddToggle(title, defaultVal, callback, desc)
        local state = defaultVal or false
        local cardH = desc and (IS_MOBILE and 54 or 48) or (IS_MOBILE and 42 or 38)
        local card = MI("Frame", {
            Size = UDim2.new(1, 0, 0, cardH),
            BackgroundColor3 = THEME.Surface,
            BorderSizePixel = 0,
        }, self.page)
        Corner(card, 8)
        Stroke(card, THEME.Border, 1)
        Padding(card, 6, 6, 12, 12)

        local labelH = desc and 18 or cardH - 12
        MI("TextLabel", {
            Size = UDim2.new(1, -55, 0, labelH),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = THEME.TextMain,
            Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 12 or 11,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, card)

        if desc then
            MI("TextLabel", {
                Size = UDim2.new(1, -55, 0, 14),
                Position = UDim2.new(0, 0, 0, 20),
                BackgroundTransparency = 1,
                Text = desc,
                TextColor3 = THEME.TextSub,
                Font = Enum.Font.Gotham,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
            }, card)
        end

        -- Switch Kutusu
        local swW, swH = 44, 22
        local sw = MI("Frame", {
            Size = UDim2.new(0, swW, 0, swH),
            Position = UDim2.new(1, -swW, 0.5, -swH / 2),
            BackgroundColor3 = state and THEME.ON or THEME.OFF,
            BorderSizePixel = 0,
        }, card)
        Corner(sw, swH / 2)

        local dotSize = swH - 4
        local dot = MI("Frame", {
            Size = UDim2.new(0, dotSize, 0, dotSize),
            Position = state and UDim2.new(0, swW - dotSize - 2, 0.5, -dotSize / 2) or UDim2.new(0, 2, 0.5, -dotSize / 2),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
        }, sw)
        Corner(dot, dotSize / 2)

        local clickBtn = MI("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 5 }, card)
        local function SetToggle(val)
            state = val
            TweenService:Create(sw, TweenInfo.new(0.18), { BackgroundColor3 = state and THEME.ON or THEME.OFF }):Play()
            TweenService:Create(dot, TweenInfo.new(0.18), {
                Position = state and UDim2.new(0, swW - dotSize - 2, 0.5, -dotSize / 2) or UDim2.new(0, 2, 0.5, -dotSize / 2)
            }):Play()
            pcall(callback, state)
        end
        clickBtn.MouseButton1Click:Connect(function() SetToggle(not state) end)

        return { Set = SetToggle }
    end

    -- Modern Slider (Hassas Kaydırıcı)
    function tabObj:AddSlider(title, minVal, maxVal, defaultVal, callback, suffix)
        suffix = suffix or ""
        local val = math.clamp(defaultVal or minVal, minVal, maxVal)
        local cardH = IS_MOBILE and 56 or 50
        local card = MI("Frame", {
            Size = UDim2.new(1, 0, 0, cardH),
            BackgroundColor3 = THEME.Surface,
            BorderSizePixel = 0,
        }, self.page)
        Corner(card, 8)
        Stroke(card, THEME.Border, 1)
        Padding(card, 8, 8, 12, 12)

        local topRow = MI("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1 }, card)
        MI("TextLabel", {
            Size = UDim2.new(0.7, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = THEME.TextMain,
            Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 12 or 11,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, topRow)

        local valBadge = MI("TextLabel", {
            Size = UDim2.new(0.3, 0, 1, 0),
            Position = UDim2.new(0.7, 0, 0, 0),
            BackgroundTransparency = 1,
            Text = tostring(val) .. suffix,
            TextColor3 = THEME.Accent,
            Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 12 or 11,
            TextXAlignment = Enum.TextXAlignment.Right,
        }, topRow)

        -- Ray
        local track = MI("Frame", {
            Size = UDim2.new(1, 0, 0, 6),
            Position = UDim2.new(0, 0, 0, 28),
            BackgroundColor3 = Color3.fromRGB(36, 42, 58),
            BorderSizePixel = 0,
        }, card)
        Corner(track, 3)

        local fill = MI("Frame", {
            Size = UDim2.new((val - minVal) / (maxVal - minVal), 0, 1, 0),
            BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0,
        }, track)
        Corner(fill, 3)

        local thumb = MI("Frame", {
            Size = UDim2.new(0, 14, 0, 14),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new((val - minVal) / (maxVal - minVal), 0, 0.5, 0),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
            ZIndex = 3,
        }, track)
        Corner(thumb, 7)
        Stroke(thumb, THEME.Accent, 1.5)

        local hitArea = MI("TextButton", {
            Size = UDim2.new(1, 0, 0, 26),
            Position = UDim2.new(0, 0, 0, -10),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 5,
        }, track)

        local sliding = false
        local function UpdateSlider(xPos)
            local t = math.clamp((xPos - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            local step = (maxVal - minVal) <= 10 and 0.1 or 1
            val = math.floor((minVal + (maxVal - minVal) * t) / step + 0.5) * step
            val = math.clamp(val, minVal, maxVal)
            fill.Size = UDim2.new(t, 0, 1, 0)
            thumb.Position = UDim2.new(t, 0, 0.5, 0)
            valBadge.Text = tostring(Round(val, 1)) .. suffix
            pcall(callback, val)
        end

        hitArea.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                sliding = true
                UpdateSlider(i.Position.X)
            end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                sliding = false
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                UpdateSlider(i.Position.X)
            end
        end)
    end

    -- Modern Buton (Aksiyon Butonu)
    function tabObj:AddButton(title, callback)
        local btn = MI("TextButton", {
            Size = UDim2.new(1, 0, 0, IS_MOBILE and 38 or 34),
            BackgroundColor3 = THEME.Surface,
            Text = title,
            TextColor3 = THEME.TextMain,
            Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 12 or 11,
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, self.page)
        Corner(btn, 8)
        Stroke(btn, THEME.Accent, 1, 0.4)

        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundColor3 = THEME.SurfaceHover }):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundColor3 = THEME.Surface }):Play()
        end)
        btn.MouseButton1Click:Connect(function()
            -- Tıklama efekti
            TweenService:Create(btn, TweenInfo.new(0.08), { TextColor3 = THEME.Accent }):Play()
            task.delay(0.12, function()
                TweenService:Create(btn, TweenInfo.new(0.1), { TextColor3 = THEME.TextMain }):Play()
            end)
            pcall(callback)
        end)
    end

    -- Modern Dropdown (Açılır Seçim)
    function tabObj:AddDropdown(title, options, defaultVal, callback)
        local sel = defaultVal or options[1]
        local cardH = IS_MOBILE and 40 or 36
        local card = MI("Frame", {
            Size = UDim2.new(1, 0, 0, cardH),
            BackgroundColor3 = THEME.Surface,
            BorderSizePixel = 0,
            ZIndex = 10,
        }, self.page)
        Corner(card, 8)
        Stroke(card, THEME.Border, 1)
        Padding(card, 0, 0, 12, 12)

        MI("TextLabel", {
            Size = UDim2.new(0.55, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = THEME.TextMain,
            Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 12 or 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 10,
        }, card)

        local curLbl = MI("TextLabel", {
            Size = UDim2.new(0.45, 0, 1, 0),
            Position = UDim2.new(0.55, 0, 0, 0),
            BackgroundTransparency = 1,
            Text = tostring(sel) .. " ▾",
            TextColor3 = THEME.Accent,
            Font = Enum.Font.GothamBold,
            TextSize = IS_MOBILE and 12 or 11,
            TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = 10,
        }, card)

        local dropPanel = MI("Frame", {
            Size = UDim2.new(1, 0, 0, #options * 28 + 6),
            Position = UDim2.new(0, 0, 1, 4),
            BackgroundColor3 = THEME.Sidebar,
            BorderSizePixel = 0,
            ZIndex = 30,
            Visible = false,
        }, card)
        Corner(dropPanel, 8)
        Stroke(dropPanel, THEME.Accent, 1, 0.2)
        Padding(dropPanel, 3, 3, 4, 4)
        MI("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 2) }, dropPanel)

        for _, opt in ipairs(options) do
            local ob = MI("TextButton", {
                Size = UDim2.new(1, 0, 0, 26),
                BackgroundColor3 = THEME.Surface,
                BackgroundTransparency = 0.6,
                Text = tostring(opt),
                TextColor3 = THEME.TextSub,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                BorderSizePixel = 0,
                ZIndex = 31,
            }, dropPanel)
            Corner(ob, 5)
            ob.MouseButton1Click:Connect(function()
                sel = opt
                curLbl.Text = tostring(opt) .. " ▾"
                dropPanel.Visible = false
                pcall(callback, opt)
            end)
        end

        local toggleBtn = MI("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 12 }, card)
        toggleBtn.MouseButton1Click:Connect(function()
            dropPanel.Visible = not dropPanel.Visible
        end)
    end

    Tabs[name] = tabObj
    if not CurrentTab then SelectTab(name) end
    return tabObj
end

-- ===============================================================
-- 7. MENÜ SEKMELERİ VE ÖZELLİKLER (BY UMUT)
-- ===============================================================

-- 1. COMBAT (TOP KORUMA & SAVUNMA)
local tCombat = CreateTab("Combat", "⚔️")
tCombat:AddSection("🛡️ Top Koruma & Kaybetmeme (By Umut)")
tCombat:AddToggle("Top Kaybetmeme (Anti-Steal)", Config.Combat.AntiStealFeint, function(v) Config.Combat.AntiStealFeint = v end, "Topu ters tarafa saklar, calim basar ve sendelemeyi engeller")
tCombat:AddToggle("Auto Parry", Config.Combat.AutoParry, function(v) Config.Combat.AutoParry = v end, "Rakip vurma/kayma baslatinca aninda karsilik verir")
tCombat:AddSlider("Parry Menzili", 4, 25, Config.Combat.AutoParryRadius, function(v) Config.Combat.AutoParryRadius = v end, " st")

tCombat:AddSection("🏃 Tackle & Knockout")
tCombat:AddToggle("Auto Tackle", Config.Combat.AutoTackle, function(v) Config.Combat.AutoTackle = v end, "Top rakipteyken hedefe otomatik kay")
tCombat:AddSlider("Tackle Menzili", 4, 25, Config.Combat.TackleRange, function(v) Config.Combat.TackleRange = v end, " st")
tCombat:AddToggle("Auto Knockout", Config.Combat.AutoKnockout, function(v) Config.Combat.AutoKnockout = v end, "Menzildeki rakibe araliksiz yumruk bas")
tCombat:AddSlider("KO Menzili", 3, 18, Config.Combat.KORange, function(v) Config.Combat.KORange = v end, " st")

-- 2. BALL (TOPU ÇEKME & ŞUT)
local tBall = CreateTab("Ball", "⚽")
tBall:AddSection("🧲 Topu Ayağa Çekme (Magnet Reach)")
tBall:AddToggle("Topu Ayağa Çek (Magnet)", Config.Ball.MagnetReach, function(v) Config.Ball.MagnetReach = v end, "Karakter isinlanmaz! Top dogrudan ayagina cekilir ve calinir")
tBall:AddSlider("Çekme Menzili", 5, 50, Config.Ball.ReachRadius, function(v) Config.Ball.ReachRadius = v end, " st")

tBall:AddSection("🎯 Şut Yönlendirme (Silent Aim)")
tBall:AddToggle("Silent Aim", Config.Ball.SilentAim, function(v) Config.Ball.SilentAim = v end, "Sut vurunca top dogrudan secilen kale kosesine gider")
tBall:AddDropdown("Hedef Köşe", { "BottomLeft", "BottomRight", "TopLeft", "TopRight", "Center" }, Config.Ball.SilentAimCorner, function(v) Config.Ball.SilentAimCorner = v end)
tBall:AddSlider("Aim Gücü", 0.2, 1.0, Config.Ball.SilentAimStrength, function(v) Config.Ball.SilentAimStrength = v end, "x")
tBall:AddButton("⚽ Manuel Aim Uygula", function() pcall(ApplySilentAim) end)

-- 3. ESP (GÖRSEL ANALİZ)
local tESP = CreateTab("ESP", "👁️")
tESP:AddSection("👁️ Görsel Analiz (ESP)")
tESP:AddToggle("Oyuncu ESP (Duvar Arkası)", Config.ESP.PlayerESP, function(v) Config.ESP.PlayerESP = v end, "Rakipleri duvar arkasindan parlatir ve mesafeyi gosterir")
tESP:AddToggle("Kutu / Sandık ESP", Config.ESP.BoxESP, function(v) Config.ESP.BoxESP = v end, "Sahadaki sans kutularini parlatir")
tESP:AddToggle("Top Yörünge Çizgisi", Config.ESP.BallTrajectory, function(v) Config.ESP.BallTrajectory = v end, "Topun gidecegi yolu 3D cizer")
tESP:AddSlider("ESP Görüş Menzili", 50, 400, Config.ESP.ESPMaxDistance, function(v) Config.ESP.ESPMaxDistance = v end, " st")

-- 4. ITEMS (EŞYA OTOMASYONU)
local tItems = CreateTab("Items", "📦")
tItems:AddSection("📦 Kutu Mıknatısı / Teleport")
tItems:AddToggle("Kutu Auto-Collect", Config.Items.BoxTeleport, function(v) Config.Items.BoxTeleport = v end, "Sahadaki kutulara otomatik ulasir")
tItems:AddDropdown("Toplama Modu", { "Teleport", "Pull" }, Config.Items.BoxPullMode, function(v) Config.Items.BoxPullMode = v end)
tItems:AddSlider("Tarama Aralığı", 0.2, 3.0, Config.Items.BoxScanInterval, function(v) Config.Items.BoxScanInterval = v end, "s")

-- 5. MOVEMENT (HAREKET & BOOST)
local tMove = CreateTab("Move", "🏃")
tMove:AddSection("⚡ Hız & Zıplama")
tMove:AddToggle("Speed Hack", Config.Movement.SpeedHack, function(v) Config.Movement.SpeedHack = v end)
tMove:AddSlider("Yürüme Hızı", 16, 120, Config.Movement.WalkSpeed, function(v) Config.Movement.WalkSpeed = v end, " ws")
tMove:AddToggle("Jump Power", Config.Movement.JumpPower, function(v) Config.Movement.JumpPower = v end)
tMove:AddSlider("Zıplama Yüksekliği", 7, 160, Config.Movement.JumpHeight, function(v) Config.Movement.JumpHeight = v end, " st")

tMove:AddSection("💨 Kayma Hızlandırma (Slide Boost)")
tMove:AddToggle("Kayma Boost", Config.Movement.SlideBoost, function(v) Config.Movement.SlideBoost = v end, "Sadece kayarken ileriye ekstra hiz patlamasi verir")
tMove:AddSlider("Slide Çarpanı", 1.0, 6.0, Config.Movement.SlideMultiplier, function(v) Config.Movement.SlideMultiplier = v end, "x")
tMove:AddButton("💨 Anlık Slide Boost Bas", function() TriggerSlideBoost() end)

-- Varsayılan Sekme
SelectTab("Combat")

-- Temizlik Fonksiyonu
local function FullCleanup()
    DisconnectAll()
    pcall(function() guiRoot:Destroy() end)
    pcall(function() ESPFolder:Destroy() end)
    pcall(function() _trajFolder:Destroy() end)
    local hum = GetHum()
    if hum then hum.WalkSpeed = 16; hum.JumpHeight = 7.2 end
    print("[FutbolUmsu • By Umut] Kapatildi.")
end

if getgenv then
    getgenv()._FU_Loaded = true
    getgenv()._FU_Stop   = FullCleanup
    getgenv()._FU_Config = Config
end

print("=================================================")
print("  ⚽ FutbolUmsu v2.5 (By Umut) Başarıyla Yüklendi!")
print("  📱 Sol taraftaki ⚽ butonuna basarak aç/kapat!")
print("=================================================")
