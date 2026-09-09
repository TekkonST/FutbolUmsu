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
    GK = {
        AutoDive         = true,    -- Otomatik kaleci atlayisi (varsayilan acik)
        SmartThreatOnly  = true,    -- Sadece kaleye/bize gelen gercek sutlara atla (paslari ve autu eler)
        PerfectCatch     = true,    -- Kesin top tutma / kacirmama (Touch & Catch kilidi)
        DiveRange        = 55,      -- Algilama menzili (studs)
        MinShotSpeed     = 8,       -- Sut hiz esigi (yavas yuvarlanan toplara atlamaz, sut ve asirtmalara atlar)
        TimeToGoalMax    = 2.2,     -- En fazla kac saniye kala atlasin
        TimeToGoalMin    = 0.02,    -- Cok gec kalmamak icin alt sinir
        BoostPhysical    = true,    -- Sıçramaya ek ivme desteği
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

-- Sahadaki Topu Bul (Oyunun Kendi ClientBall Mimarisine Tam Uyumlu)
local _cachedBall = nil
local _lastBallSearch = 0
local _lastBallPos = nil
local _lastBallPosTime = 0
local _ballCalculatedVel = Vector3.new(0, 0, 0)

local function FindBall()
    local now = tick()
    if _cachedBall and _cachedBall.Parent and _cachedBall:IsA("BasePart") and (now - _lastBallSearch < 0.2) then
        return _cachedBall
    end
    _lastBallSearch = now

    -- 1. [KESİN BULUCU - BİRİNCİL] Oyunun ClientBall part'ı (workspace.Misc.Visuals altında)
    local misc = workspace:FindFirstChild("Misc")
    if misc then
        local visuals = misc:FindFirstChild("Visuals")
        if visuals then
            local mainBall = visuals:FindFirstChild("ClientBall_MainMatch")
            if mainBall and mainBall:IsA("BasePart") then
                _cachedBall = mainBall
                return mainBall
            end
            for _, child in ipairs(visuals:GetChildren()) do
                if child:IsA("BasePart") and child.Name:find("ClientBall") then
                    _cachedBall = child
                    return child
                end
            end
        end
    end

    -- 2. Workspace genelinde ClientBall_ ile başlayan partlar
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("BasePart") and child.Name:find("ClientBall") then
            _cachedBall = child
            return child
        end
    end

    -- 3. Workspace.Balls veya Workspace.Ball klasörü / partı
    local ballsFolder = workspace:FindFirstChild("Balls") or workspace:FindFirstChild("Ball")
    if ballsFolder then
        if ballsFolder:IsA("BasePart") then
            _cachedBall = ballsFolder
            return ballsFolder
        end
        local firstBall = ballsFolder:FindFirstChildWhichIsA("BasePart")
        if firstBall then
            _cachedBall = firstBall
            return firstBall
        end
    end

    -- 4. CollectionService Tag
    local tagged = CollectionService:GetTagged("Ball")
    if tagged and #tagged > 0 then
        for _, t in ipairs(tagged) do
            if t:IsA("BasePart") then _cachedBall = t; return t end
            local bp = t:FindFirstChildOfClass("BasePart")
            if bp then _cachedBall = bp; return bp end
        end
    end

    -- 5. Fallback: Workspace içi gerçek futbol topu partı (Karakter parçalarını eler)
    for _, v in ipairs(workspace:GetChildren()) do
        local n = v.Name:lower()
        if (n == "ball" or n == "football" or n == "soccerball" or n:find("matchball")) and v:IsA("BasePart") then
            _cachedBall = v
            return v
        end
    end

    return _cachedBall
end

-- Top Hızı ve Yönü Hesaplayıcı (ClientBall Anchored olduğu için frame delta ile hesaplar)
local function GetBallVelocity(ball)
    if not ball or not ball:IsA("BasePart") then return Vector3.new(0, 0, 0) end
    -- Fizik motoru AssemblyLinearVelocity veriyorsa öncelik ver
    local pVel = ball.AssemblyLinearVelocity
    if pVel and pVel.Magnitude > 2.0 then
        return pVel
    end
    -- ClientBall Anchored olduğunda frame-by-frame delta hızı kullanılır
    return _ballCalculatedVel
end

-- Top Pozisyonu ve Hızını Her Karede Kesintisiz Hesaplayan Dinleyici
RunService.Heartbeat:Connect(function(dt)
    local ball = FindBall()
    if ball and ball:IsA("BasePart") then
        local pos = ball.Position
        if _lastBallPos and dt > 0.001 then
            local instantVel = (pos - _lastBallPos) / dt
            if instantVel.Magnitude > 0.05 then
                _ballCalculatedVel = instantVel
            else
                _ballCalculatedVel = Vector3.new(0, 0, 0)
            end
        end
        _lastBallPos = pos
    else
        _lastBallPos = nil
        _ballCalculatedVel = Vector3.new(0, 0, 0)
    end
end)

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

    -- 2. Attribute / Value kontrolu (Oyunun sahiplik verisi: OwnerUserId, Owner, Possession)
    local ownerUserId = ball:GetAttribute("OwnerUserId") or ball:GetAttribute("Owner") or ball:GetAttribute("Possession") or ball:GetAttribute("Holder") or ball:GetAttribute("Player")
    if ownerUserId then
        local attrStr = tostring(ownerUserId):lower()
        if attrStr == tostring(LocalPlayer.UserId) or attrStr == LocalPlayer.Name:lower() then
            return true
        end
    end
    -- Karakter bazında attribute kontrolü
    local charHolding = char:GetAttribute("HoldingBall") or char:GetAttribute("HasBall")
    if charHolding == true then return true end

    local ownerVal = ball:FindFirstChild("Owner") or ball:FindFirstChild("Possession") or ball:FindFirstChild("Holder")
    if ownerVal and ownerVal:IsA("ValueBase") then
        if ownerVal.Value == LocalPlayer or ownerVal.Value == char or tostring(ownerVal.Value):lower() == LocalPlayer.Name:lower() then
            return true
        end
    end

    -- 3. Dinamik Mesafe & En Yakin Oyuncu Kontrolu
    -- KRİTİK: Top hızla uçuyorsa (şut veya pas), kimsenin ayağında olamaz!
    local bVel = ball.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
    if bVel.Magnitude > 11 then
        return false
    end

    local dist = (root.Position - ball.Position).Magnitude
    if dist <= 4.2 then
        -- Topa bizden daha yakin baska rakip var mi?
        local isClosest = true
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local pr = p.Character:FindFirstChild("HumanoidRootPart")
                if pr and (pr.Position - ball.Position).Magnitude < (dist - 0.5) then
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

-- Sahadaki Kutulari Bul (GameplayItemBox & Hitbox Parçası Taraması)
local function FindAllBoxes()
    local found = {}
    
    -- 1. [ÖZEL] Oyundaki GameplayItemBox etiketli modeller (Hitbox parçası aranır)
    local tagBoxes = CollectionService:GetTagged("GameplayItemBox")
    for _, b in ipairs(tagBoxes) do
        local hb = b:FindFirstChild("Hitbox") or b:FindFirstChild("Box") or (b:IsA("BasePart") and b)
        if hb and hb:IsA("BasePart") and hb.CanTouch ~= false and not table.find(found, hb) then
            table.insert(found, hb)
        end
    end

    local tagBoxes2 = CollectionService:GetTagged(Config.Items.BoxTag)
    for _, b in ipairs(tagBoxes2) do
        local hb = b:FindFirstChild("Hitbox") or b:FindFirstChild("Box") or (b:IsA("BasePart") and b)
        if hb and hb:IsA("BasePart") and hb.CanTouch ~= false and not table.find(found, hb) then
            table.insert(found, hb)
        end
    end

    -- 2. Isim taramasi (GameplayItemBox, SkillBox, ItemBox, LuckyBlock)
    for _, v in ipairs(workspace:GetDescendants()) do
        local n = v.Name:lower()
        if n == "gameplayitembox" or n:find("itembox") or n == Config.Items.BoxTag:lower() or n:find("skillbox") or n:find("luckyblock") then
            local hb = v:FindFirstChild("Hitbox") or v:FindFirstChild("Box") or (v:IsA("BasePart") and v)
            if hb and hb:IsA("BasePart") and hb.CanTouch ~= false and not table.find(found, hb) then
                table.insert(found, hb)
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

-- Kale Koseleri (Rakip Kaleyi Bulur)
local function GetGoalCorner(cornerName)
    local root = GetRoot()
    if not root then return nil end
    local goals = {}

    -- 1. [ÖZEL] Oyundaki Map.Data klasoru
    local mapFolder = workspace:FindFirstChild("Map")
    if mapFolder then
        local dataFolder = mapFolder:FindFirstChild("Data")
        if dataFolder then
            for _, child in ipairs(dataFolder:GetDescendants()) do
                if child:IsA("BasePart") and child.Name:lower():find("goal") then
                    table.insert(goals, child)
                end
            end
        end
    end

    -- 2. Workspace genelinde
    if #goals == 0 then
        for _, v in ipairs(workspace:GetDescendants()) do
            local n = v.Name:lower()
            if n:find("goal") or n:find("kale") or n:find("post") then
                local bp = v:IsA("BasePart") and v or v:FindFirstChildOfClass("BasePart")
                if bp and bp.Size.X > 4 then
                    table.insert(goals, bp)
                end
            end
        end
    end
    if #goals == 0 then return nil end

    -- Rakip kale = Karakterin baktığı yöndeki veya en uzaktaki kale
    local best, bestD = nil, -math.huge
    for _, g in ipairs(goals) do
        local d = (root.Position - g.Position).Magnitude
        -- Baktığımız yöne doğru mu?
        local dot = root.CFrame.LookVector:Dot((g.Position - root.Position).Unit)
        local score = d + (dot * 60)
        if score > bestD then bestD = score; best = g end
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

-- Korudugumuz Kaleyi Bul (Kaleciye En Yakin Kale veya Bulunamazsa Kalecinin Mevcut Konumu)
local function GetMyGoal()
    local root = GetRoot()
    if not root then return nil, math.huge end
    local goals = {}

    -- 1. [ÖZEL] Oyundaki Map.Data veya Goals klasoru
    local mapFolder = workspace:FindFirstChild("Map")
    if mapFolder then
        local dataFolder = mapFolder:FindFirstChild("Data")
        if dataFolder then
            for _, child in ipairs(dataFolder:GetDescendants()) do
                if child:IsA("BasePart") and child.Name:lower():find("goal") then
                    table.insert(goals, child)
                end
            end
        end
    end

    -- 2. Workspace genelinde kale parçaları
    if #goals == 0 then
        for _, v in ipairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") and (v.Size.X > 4 or v.Size.Z > 4) then
                local n = v.Name:lower()
                if n:find("goal") or n:find("kale") or n:find("net") or n:find("post") or n:find("direk") then
                    table.insert(goals, v)
                end
            end
        end
    end

    if #goals > 0 then
        local closest, minD = nil, math.huge
        for _, g in ipairs(goals) do
            local d = (root.Position - g.Position).Magnitude
            if d < minD then
                minD = d
                closest = g
            end
        end
        return closest, minD
    end

    -- Eger sahadaki kale bulunamazsa, kalecinin mevcut konumunu referans al
    return root, 0
end

-- Bildirim Gönderme Yardımcısı
local function GKNotify(title, text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "🧤 " .. title,
            Text = text,
            Duration = 3,
        })
    end)
    print("[FutbolUmsu GK] " .. title .. ": " .. text)
end

-- Oyundaki Planjon Butonu Referansi (Onbellek)
local _customPlanjonBtn = nil
local _isPickingPlanjon = false

-- Planjon Butonu Adayı mı? (Genişletilmiş Filtre)
local function IsPlanjonCandidate(obj)
    if not obj or not obj:IsA("GuiObject") then return false end
    if guiRoot and obj:IsDescendantOf(guiRoot) then return false end

    local name = obj.Name:lower()
    local parentName = (obj.Parent and obj.Parent.Name or ""):lower()
    local text = ""

    if obj:IsA("TextButton") or obj:IsA("TextLabel") then
        text = text .. " " .. obj.Text:lower()
    end
    for _, ch in ipairs(obj:GetDescendants()) do
        if ch:IsA("TextLabel") or ch:IsA("TextButton") then
            text = text .. " " .. ch.Text:lower()
        end
    end

    -- 1. Kesin Eşleşmeler (Türkçe & İngilizce)
    if text:find("planjon") or name:find("planjon") or parentName:find("planjon") then
        return true, 100, "Planjon"
    end
    if text:find("plongeon") or name:find("plongeon") then
        return true, 95, "Plongeon"
    end
    if text:find("dive") or name:find("dive") or parentName:find("dive") then
        return true, 90, "Dive"
    end
    if text:find("kurtar") or name:find("kurtar") then
        return true, 85, "Kurtar"
    end
    if (text:find("uç") or text:find("uc") or text:find("atla")) and not text:find("kay") then
        return true, 80, "Uç/Atla"
    end
    if name:find("gkdive") or name:find("keeperdive") or text:find("keeper") or text:find("goalie") then
        return true, 75, "GK Dive"
    end

    return false, 0, ""
end

-- Otomatik Planjon Butonu Bulucu (deneme.rbxl Oyun Mimarisine Tam Uyumlu)
local function FindPlanjonButton()
    if _customPlanjonBtn and _customPlanjonBtn.Parent then
        return _customPlanjonBtn
    end

    local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pgui then return nil end

    -- 1. [ÖZEL] Oyundaki Mobile UI hiyerarşisi: PlayerGui.Mobile.Frame.Button1.Dive
    local mobileGui = pgui:FindFirstChild("Mobile")
    if mobileGui then
        local frame = mobileGui:FindFirstChild("Frame")
        if frame then
            local b1 = frame:FindFirstChild("Button1")
            if b1 then
                local diveBtn = b1:FindFirstChild("Dive") or b1:FindFirstChildWhichIsA("GuiButton") or b1
                _customPlanjonBtn = diveBtn
                return diveBtn
            end
        end
        -- Alternatif: Mobile altındaki Dive veya Button1
        local directDive = mobileGui:FindFirstChild("Dive", true) or mobileGui:FindFirstChild("Button1", true)
        if directDive then
            _customPlanjonBtn = directDive
            return directDive
        end
    end

    -- 2. ContextActionGui kontrolu
    local casGui = pgui:FindFirstChild("ContextActionGui")
    if casGui then
        for _, d in ipairs(casGui:GetDescendants()) do
            local isMatch = IsPlanjonCandidate(d)
            if isMatch then
                _customPlanjonBtn = d
                return d
            end
        end
    end

    -- 3. PlayerGui icindeki tum GUI objelerinde genel tarama
    local candidates = {}
    for _, obj in ipairs(pgui:GetDescendants()) do
        if obj:IsA("GuiObject") and obj.Visible ~= false then
            local isMatch, score, matchName = IsPlanjonCandidate(obj)
            if isMatch then
                table.insert(candidates, { score = score, elem = obj, matchName = matchName })
            end
        end
    end

    if #candidates > 0 then
        table.sort(candidates, function(a, b) return a.score > b.score end)
        _customPlanjonBtn = candidates[1].elem
        return candidates[1].elem
    end

    return nil
end

-- Buton Tetikleme (Multi-Method: getconnections + firesignal + VirtualInputManager + Touch)
local function TriggerPlanjonElement(elem)
    if not elem or not elem:IsA("GuiObject") then return false end
    local triggered = false
    local vim = game:GetService("VirtualInputManager")

    -- 1. getconnections ile oyundaki bagli tum event fonksiyonlarini dogrudan calistir
    if getconnections then
        local signals = { "MouseButton1Down", "MouseButton1Click", "MouseButton1Up", "Activated", "TouchTap", "InputBegan" }
        for _, sigName in ipairs(signals) do
            local sig = elem[sigName]
            if sig then
                for _, conn in ipairs(getconnections(sig)) do
                    pcall(function()
                        if sigName == "InputBegan" then
                            conn:Fire({
                                UserInputType = Enum.UserInputType.Touch,
                                UserInputState = Enum.UserInputState.Begin,
                                Position = Vector3.new(elem.AbsolutePosition.X + elem.AbsoluteSize.X / 2, elem.AbsolutePosition.Y + elem.AbsoluteSize.Y / 2, 0)
                            })
                        else
                            conn:Fire()
                        end
                        triggered = true
                    end)
                end
            end
        end
    end

    -- 2. firesignal cagrilari
    if firesignal then
        pcall(function()
            if elem.MouseButton1Down then firesignal(elem.MouseButton1Down) end
            if elem.MouseButton1Click then firesignal(elem.MouseButton1Click) end
            if elem.Activated then firesignal(elem.Activated) end
            if elem.TouchTap then firesignal(elem.TouchTap) end
            if elem.MouseButton1Up then firesignal(elem.MouseButton1Up) end
            if elem.InputBegan then
                firesignal(elem.InputBegan, {
                    UserInputType = Enum.UserInputType.Touch,
                    UserInputState = Enum.UserInputState.Begin,
                    Position = Vector3.new(elem.AbsolutePosition.X + elem.AbsoluteSize.X / 2, elem.AbsolutePosition.Y + elem.AbsoluteSize.Y / 2, 0)
                })
            end
            triggered = true
        end)
    end

    -- 3. GuiButton :Activate()
    if elem:IsA("GuiButton") and elem.Activate then
        pcall(function() elem:Activate(); triggered = true end)
    end

    -- 4. VirtualInputManager (Fare & Mobil Dokunma)
    if vim and elem.AbsoluteSize.X > 2 and elem.AbsoluteSize.Y > 2 then
        local cx = elem.AbsolutePosition.X + elem.AbsoluteSize.X / 2
        local cy = elem.AbsolutePosition.Y + elem.AbsoluteSize.Y / 2
        pcall(function()
            vim:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
            task.delay(0.02, function()
                pcall(function() vim:SendMouseButtonEvent(cx, cy, 0, false, game, 1) end)
            end)
        end)
        pcall(function()
            vim:SendTouchEvent(1, 0, cx, cy)
            task.delay(0.02, function()
                pcall(function() vim:SendTouchEvent(1, 2, cx, cy) end)
            end)
        end)
        triggered = true
    end

    return triggered
end

-- Oyundaki Kaleci Planjon Butonunu Bul ve Eksiksiz Tetikle
local function PressInGameDiveButton(showNotification, overrideDir)
    local triggered = false
    local targetBtn = FindPlanjonButton()

    if targetBtn then
        TriggerPlanjonElement(targetBtn)
        triggered = true
        if showNotification then
            GKNotify("Planjon Basıldı", "Hedef: " .. targetBtn.Name .. " (" .. targetBtn:GetFullName() .. ")")
        end
    elseif showNotification then
        GKNotify("Buton Aranıyor", "Planjon butonu taranıyor... 'Butona Dokunarak Tanıt' da kullanabilirsiniz.")
    end

    local root = GetRoot()
    local char = GetChar()
    local hum = GetHum()
    local dir = overrideDir or (root and root.CFrame.LookVector or Vector3.new(0, 0, 1))

    -- A) [DOĞRUDAN OYUN PROTOKOLÜ] ActionRemoteProtocol ve ReplicatedStorage.Remotes.Ball.Tackle
    pcall(function()
        local arp = require(ReplicatedStorage.Modules.Actions.ActionRemoteProtocol)
        local ac = require(ReplicatedStorage.Modules.Actions.ActionCommands)
        if arp and ac and arp.Send and ac.GoalkeeperDive then
            arp.Send(ac.GoalkeeperDive({
                AimDirection = dir,
                DirectionName = "Dive",
                ShotTime = workspace:GetServerTimeNow()
            }))
            triggered = true
        end
    end)

    pcall(function()
        local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
        local ballFolder = remotesFolder and remotesFolder:FindFirstChild("Ball")
        local tackleRemote = ballFolder and ballFolder:FindFirstChild("Tackle")
        if tackleRemote and tackleRemote:IsA("RemoteEvent") and root then
            local vel = root.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
            tackleRemote:FireServer({
                Protocol = "ActionCommand",
                Command = {
                    Kind = "Tackle",
                    Mode = "GoalkeeperDive",
                    Direction = dir,
                    AimDirection = dir,
                    ClientPosition = root.Position,
                    UseClientPosition = true,
                    PlayerVelocity = Vector3.new(vel.X, 0, vel.Z),
                    ShotTime = workspace:GetServerTimeNow(),
                    ActionId = math.random(1000, 99999) * 2 + 1
                }
            })
            triggered = true
        end
    end)

    -- B) [İSTEMCİ MODÜLÜ] GoalkeeperDive presentation & fiziksel hareket
    pcall(function()
        local gkd = require(ReplicatedStorage.Modules.Actions.GoalkeeperDive)
        if gkd and char and hum then
            gkd.Run(char, hum, dir, function()
                return Camera and Camera.CFrame or (root and root.CFrame or CFrame.new())
            end)
            triggered = true
        end
    end)

    -- C) ContextActionService Action'larini tetikle
    pcall(function()
        local cas = game:GetService("ContextActionService")
        local actionNames = {
            "Dive", "dive", "DIVE", "Planjon", "planjon", "PLANJON",
            "GoalkeeperDive", "Tackle", "Jump", "MobileDive"
        }
        for _, act in ipairs(actionNames) do
            pcall(cas.CallFunction, cas, act, Enum.UserInputState.Begin, nil)
            task.delay(0.02, function()
                pcall(cas.CallFunction, cas, act, Enum.UserInputState.End, nil)
            end)
        end
    end)

    -- D) Virtual Klavye & Fare Tuşları (E tuşu ve MouseButton2 - PC Keybinds)
    local vim = game:GetService("VirtualInputManager")
    if vim then
        pcall(function()
            vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.delay(0.03, function()
                pcall(function() vim:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
            end)
        end)
        pcall(function()
            vim:SendMouseButtonEvent(0, 0, 1, true, game, 0)
            task.delay(0.03, function()
                pcall(function() vim:SendMouseButtonEvent(0, 0, 1, false, game, 0) end)
            end)
        end)
    end

    -- E) Remote Event / Remote Function fallback
    local diveRemotes = {
        "GoalkeeperDive", "Dive", "dive", "Planjon", "planjon", "PlanjonAction",
        "GKPlanjon", "GKDive", "KeeperDive", "GK_Dive", "Save", "save", "GoalieDive"
    }
    if SafeFireAny(diveRemotes) then
        triggered = true
    end

    return triggered
end

-- ===============================================================
-- 🧤 GELİŞMİŞ AKILLI KALECİ YAPAY ZEKASI (PLANJON AUTO-DIVE)
-- ===============================================================
local _lastDiveTime = 0

local function RunGoalkeeperAI()
    if not Config.GK.AutoDive then return end

    local now = tick()
    if now - _lastDiveTime < 0.8 then return end -- Cooldown (Spam engeli)

    local ball = FindBall()
    local myRoot = GetRoot()
    local char = GetChar()
    local hum = GetHum()
    if not ball or not myRoot or not char or not hum then return end

    -- Top zaten bizdeyse atlama
    if DoIHaveBall() then return end

    -- Korudugumuz kaleyi bul
    local myGoal, distToGoal = GetMyGoal()
    if not myGoal then myGoal = myRoot; distToGoal = 0 end

    local ballPos = ball.Position
    local ballVel = GetBallVelocity(ball)
    local ballSpeed = ballVel.Magnitude

    -- 1. DURAN TOP FILTRESI (Sadece tamamen duran ve uzaktaki toplara atlamaz)
    if Config.GK.SmartThreatOnly and ballSpeed < Config.GK.MinShotSpeed and distToMe > 14 and distToGoal > 15 then
        return
    end

    local myPos = myRoot.Position
    local distToMe = (myPos - ballPos).Magnitude
    if distToMe > Config.GK.DiveRange then return end

    -- 2. ACI VE YON FILTRESI (Top kaleciye veya kaleye doğru mu geliyor?)
    local toMe = (myPos - ballPos).Unit
    local toGoal = (myGoal.Position - ballPos).Unit
    local dotMe, dotGoal = 1, 1
    if ballSpeed > 0.5 then
        dotMe = ballVel.Unit:Dot(toMe)
        dotGoal = ballVel.Unit:Dot(toGoal)
    end

    -- Top kaleciden veya kaleden tamamen ters yöne uzaklaşıyorsa atlama (14 stud'dan uzaktaysa)
    if distToMe > 14.0 and Config.GK.SmartThreatOnly and ballSpeed > 0.5 then
        if dotMe < -0.25 and dotGoal < -0.25 then
            return
        end
    end

    -- 3. ZAMANLAMA VE TAHMİNİ VARIŞ NOKTASI
    local closingSpeed = math.max(ballSpeed, 18)
    local timeToArrive = math.clamp(distToMe / closingSpeed, 0.05, 1.8)

    local g = -workspace.Gravity * 0.5
    local predictedBallPos = ballPos + (ballVel * timeToArrive) + Vector3.new(0, g * (timeToArrive ^ 2), 0)

    -- ═══════════════════════════════════════════════════════════
    -- 🚀 HEDEF ŞUT ONAYLANDI: PLANJON & KESIN TUTUS BASLATILIYOR!
    -- ═══════════════════════════════════════════════════════════
    _lastDiveTime = now

    -- Kaleci ile topun bulusacagi ideal kurtaris noktasi
    local interceptPos = myPos:Lerp(predictedBallPos, 0.65)
    local diveVec = (interceptPos - myPos)
    local diveDir2D = Vector3.new(diveVec.X, 0, diveVec.Z)
    if diveDir2D.Magnitude > 0.05 then
        diveDir2D = diveDir2D.Unit
    else
        diveDir2D = myRoot.CFrame.LookVector
    end

    -- A) Karakteri topun gelis yonune aninda cevir
    pcall(function()
        myRoot.CFrame = CFrame.lookAt(myPos, myPos + Vector3.new(diveDir2D.X, 0, diveDir2D.Z))
    end)

    -- B) YÜRÜME YÖNÜNÜ KESİNTİSİZ TOPA DOĞRU TUT (Oyun yürüdüğün yöne doğru planjon yaptığı için!)
    task.spawn(function()
        local walkStart = tick()
        while tick() - walkStart < 0.35 do
            if not hum or not myRoot then break end
            hum:Move(diveDir2D, false)
            task.wait(0.02)
        end
    end)

    -- C) PLANJON BUTONUNU VE PROTOKOLÜNÜ HEDEF YÖNÜYLE TETİKLE
    task.spawn(function()
        PressInGameDiveButton(false, diveDir2D)
        task.wait(0.03)
        PressInGameDiveButton(false, diveDir2D)
        task.wait(0.05)
        PressInGameDiveButton(false, diveDir2D)
    end)

    -- D) Fiziksel sıçrama ve ivme desteği (Topu havada kesin karşılamak için)
    if Config.GK.BoostPhysical then
        hum.Jump = true
        local verticalImpulse = math.clamp((interceptPos.Y - myPos.Y) * 11 + 16, 14, 38)
        local leapSpeed = math.clamp(diveVec.Magnitude * 20, 28, 55)
        myRoot.AssemblyLinearVelocity = (diveDir2D * leapSpeed) + Vector3.new(0, verticalImpulse, 0)
    end

    -- E) KESİN TUTUŞ / TOPU YAKALAMA (100% Catch & Retention)
    if Config.GK.PerfectCatch then
        task.spawn(function()
            local saveStart = tick()
            while tick() - saveStart < 0.85 do
                task.wait(0.02)
                if not ball or not myRoot then break end

                local curDist = (myRoot.Position - ball.Position).Magnitude
                if curDist <= 8.0 then
                    -- Tum vucut ve kollar ile temas kur
                    local touchParts = {
                        char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"),
                        char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm"),
                        char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"),
                        char:FindFirstChild("Head"),
                        myRoot
                    }
                    for _, p in ipairs(touchParts) do
                        if p and firetouchinterest then
                            pcall(firetouchinterest, p, ball, 0)
                            pcall(firetouchinterest, p, ball, 1)
                            pcall(firetouchinterest, ball, p, 0)
                            pcall(firetouchinterest, ball, p, 1)
                        end
                    end

                    -- Topu kalecinin onunde kitle / ellerin arasina al
                    if curDist <= 4.5 then
                        local handsPos = myRoot.Position + (myRoot.CFrame.LookVector * 1.5) + Vector3.new(0, 0.4, 0)
                        ball.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                        ball.CFrame = CFrame.new(handsPos)
                        break
                    end
                end
            end
        end)
    end
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

                    -- A) TEHLİKE ANINDA GERÇEK ÇALIM / DODGE BAS
                    if (isAttacking or dist < 5.5) and (now - _lastFeint > 0.35) then
                        pcall(function()
                            local arp = require(ReplicatedStorage.Modules.Actions.ActionRemoteProtocol)
                            local ac = require(ReplicatedStorage.Modules.Actions.ActionCommands)
                            if arp and ac and arp.Send and ac.Dodge then
                                arp.Send(ac.Dodge({
                                    AimDirection = myRoot.CFrame.LookVector,
                                    ShotTime = workspace:GetServerTimeNow()
                                }))
                            end
                        end)
                        pcall(function()
                            local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
                            local ballFolder = remotesFolder and remotesFolder:FindFirstChild("Ball")
                            local tackleRemote = ballFolder and ballFolder:FindFirstChild("Tackle")
                            if tackleRemote and tackleRemote:IsA("RemoteEvent") then
                                local vel = myRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
                                tackleRemote:FireServer({
                                    Protocol = "ActionCommand",
                                    Command = {
                                        Kind = "Tackle",
                                        Mode = "Dodge",
                                        AimDirection = myRoot.CFrame.LookVector,
                                        PlayerVelocity = Vector3.new(vel.X, 0, vel.Z),
                                        ShotTime = workspace:GetServerTimeNow(),
                                        ActionId = math.random(1000, 99999) * 2 + 1
                                    }
                                })
                            end
                        end)
                        local vim = game:GetService("VirtualInputManager")
                        if vim then
                            pcall(function()
                                vim:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
                                task.delay(0.04, function()
                                    pcall(function() vim:SendKeyEvent(false, Enum.KeyCode.Q, false, game) end)
                                end)
                            end)
                        end
                        _lastFeint = now
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
    -- 2. AUTO PARRY (SAVUNMA - DODGE İLE RAKİP MÜDAHALESİNİ ATLATMA)
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
                                    local arp = require(ReplicatedStorage.Modules.Actions.ActionRemoteProtocol)
                                    local ac = require(ReplicatedStorage.Modules.Actions.ActionCommands)
                                    if arp and ac and arp.Send and ac.Dodge then
                                        arp.Send(ac.Dodge({
                                            AimDirection = myRoot.CFrame.LookVector,
                                            ShotTime = workspace:GetServerTimeNow()
                                        }))
                                    end
                                    _lastParry = now
                                    triggered = true
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
    -- 3. AUTO TACKLE (OYUNUN SLIDE TACKLE MEKANİĞİ İLE BİREBİR UYUMLU)
    -- ─────────────────────────────────────────────────────────
    if Config.Combat.AutoTackle and now - _lastTackle > Config.Combat.TackleDelay then
        pcall(function()
            local ball = FindBall()
            if ball and not DoIHaveBall() then
                local enemy, dist = GetNearestEnemy(Config.Combat.TackleRange)
                if enemy and enemy.Character then
                    local er = enemy.Character:FindFirstChild("HumanoidRootPart")
                    if er and (er.Position - ball.Position).Magnitude < 4.5 then
                        -- Top rakipte! Karakteri rakibe dön
                        local tackleDir = (er.Position - myRoot.Position).Unit
                        myRoot.CFrame = CFrame.new(myRoot.Position, Vector3.new(er.Position.X, myRoot.Position.Y, er.Position.Z))
                        
                        -- A) [DOĞRUDAN OYUN PROTOKOLÜ] ActionRemoteProtocol ve ReplicatedStorage.Remotes.Ball.Tackle
                        pcall(function()
                            local arp = require(ReplicatedStorage.Modules.Actions.ActionRemoteProtocol)
                            local ac = require(ReplicatedStorage.Modules.Actions.ActionCommands)
                            if arp and ac and arp.Send and ac.SlideTackle then
                                arp.Send(ac.SlideTackle({
                                    AimDirection = tackleDir,
                                    ShotTime = workspace:GetServerTimeNow()
                                }))
                            end
                        end)
                        pcall(function()
                            local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
                            local ballFolder = remotesFolder and remotesFolder:FindFirstChild("Ball")
                            local tackleRemote = ballFolder and ballFolder:FindFirstChild("Tackle")
                            if tackleRemote and tackleRemote:IsA("RemoteEvent") then
                                local vel = myRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
                                tackleRemote:FireServer({
                                    Protocol = "ActionCommand",
                                    Command = {
                                        Kind = "Tackle",
                                        Mode = "Slide",
                                        Direction = tackleDir,
                                        AimDirection = tackleDir,
                                        ClientPosition = myRoot.Position,
                                        UseClientPosition = true,
                                        PlayerVelocity = Vector3.new(vel.X, 0, vel.Z),
                                        ShotTime = workspace:GetServerTimeNow(),
                                        ActionId = math.random(1000, 99999) * 2 + 1
                                    }
                                })
                            end
                        end)

                        -- B) Mobil Button1 (Tackle) butonunu tetikle
                        local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
                        if pgui then
                            local mob = pgui:FindFirstChild("Mobile")
                            local tBtn = mob and mob:FindFirstChild("Button1", true)
                            if tBtn then
                                TriggerPlanjonElement(tBtn)
                            end
                        end

                        -- C) PC Tuşu E (Tackle Keybind)
                        local vim = game:GetService("VirtualInputManager")
                        if vim then
                            pcall(function()
                                vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                task.delay(0.04, function()
                                    pcall(function() vim:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
                                end)
                            end)
                        end

                        local tackleList = { Config.Combat.TackleRemoteName, "Tackle", "SlideTackle", "Slide", "Steal" }
                        SafeFireAny(tackleList, enemy)
                        _lastTackle = now
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

    -- 7. GELİŞMİŞ KALECİ OTOMASYONU (SMART GK AUTO-DIVE)
    pcall(RunGoalkeeperAI)
end))

-- B) GERÇEK NETWORK HOOK SILENT AIM (ŞUT YÖNÜNÜ DOĞRUDAN KALEYE KİLİTLER)
local function GetGoalAimDirection()
    local target = GetGoalCorner(Config.Ball.SilentAimCorner)
    local ball = FindBall()
    local root = GetRoot()
    local origin = (ball and ball.Position) or (root and root.Position)
    if target and origin then
        return (target - origin).Unit
    end
    return nil
end

-- 1. Metamethod Hook (__namecall FireServer Interception)
if hookmetamethod then
    pcall(function()
        local _oldNamecall
        _oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            if (method == "FireServer" or method == "fireServer") and Config.Ball.SilentAim then
                local isKick = false
                pcall(function()
                    if self.Name == "Kick" or (self.Parent and self.Parent.Name == "Ball" and self.Name == "Kick") then
                        isKick = true
                    end
                end)
                if isKick and type(args[1]) == "table" then
                    local packet = args[1]
                    local cmd = packet.Command
                    if type(cmd) == "table" and (cmd.Kind == "Kick" or cmd.Kind == "Tackle") then
                        local goalDir = GetGoalAimDirection()
                        if goalDir then
                            cmd.AimDirection = goalDir
                            cmd.KickDirection = goalDir
                            if cmd.Direction then cmd.Direction = goalDir end
                        end
                    end
                end
            end
            return _oldNamecall(self, table.unpack(args))
        end)
    end)
end

-- 2. ActionRemoteProtocol.Send Hook (İstemci içi şut fonksiyonuna doğrudan kanca)
pcall(function()
    local arp = require(ReplicatedStorage.Modules.Actions.ActionRemoteProtocol)
    if arp and arp.Send then
        local oldSend = arp.Send
        arp.Send = function(cmd)
            if Config.Ball.SilentAim and type(cmd) == "table" and (cmd.Kind == "Kick" or cmd.Kind == "Tackle") then
                local goalDir = GetGoalAimDirection()
                if goalDir then
                    cmd.AimDirection = goalDir
                    cmd.KickDirection = goalDir
                    if cmd.Direction then cmd.Direction = goalDir end
                end
            end
            return oldSend(cmd)
        end
    end
end)

-- C) KAYMA BOOST (SLIDE VELOCITY BOOST - SÜREKLİ VE AKICI İVME)
-- DIKKAT: Ziplama (Freefall) kesinlikle KULLANILMIYOR!
-- Sadece zemin uzerinde gercek kayma aksiyonunda devreye girer
local _isSlidingBoostActive = false
local function TriggerSlideBoost()
    if _isSlidingBoostActive then return end
    local root = GetRoot()
    local hum  = GetHum()
    local char = GetChar()
    if not root or not hum or not char then return end

    -- Sadece karakter yerdeyken calissin (Havada asla boost vermez!)
    if hum.FloorMaterial == Enum.Material.Air then return end

    _isSlidingBoostActive = true
    task.spawn(function()
        local moveDir = hum.MoveDirection
        local dir = moveDir.Magnitude > 0.1 and moveDir.Unit or root.CFrame.LookVector
        local mult = math.clamp(Config.Movement.SlideMultiplier or 3.5, 1.2, 8.0)
        local boostSpeed = math.max((hum.WalkSpeed + 35) * mult, 60)

        -- Oyun SlidingUntil süresini belirler (genelde 0.65 - 0.85 saniye)
        local slidingUntil = char:GetAttribute("SlidingUntil")
        local startTime = tick()
        local maxDuration = 0.85

        while Config.Movement.SlideBoost and (tick() - startTime < maxDuration) do
            if not root or not hum or hum.Health <= 0 then break end
            -- SlidingUntil bittiyse veya havadaysa durdur
            if slidingUntil and workspace:GetServerTimeNow() > (slidingUntil + 0.05) then
                break
            end
            if hum.FloorMaterial == Enum.Material.Air then
                break
            end

            -- Sürekli ve akıcı kayma ivmesi uygula
            local currentDir = hum.MoveDirection.Magnitude > 0.1 and hum.MoveDirection.Unit or dir
            root.AssemblyLinearVelocity = Vector3.new(currentDir.X * boostSpeed, root.AssemblyLinearVelocity.Y, currentDir.Z * boostSpeed)

            RunService.Heartbeat:Wait()
        end
        _isSlidingBoostActive = false
    end)
end

-- Animasyon ve Attribute dinleyici ile kaymayi anla
local function HookSlideAnimation()
    local char = GetChar()
    local hum = GetHum()
    local anim = hum and hum:FindFirstChildOfClass("Animator")

    if char then
        AddConn(char:GetAttributeChangedSignal("SlidingUntil"):Connect(function()
            if not Config.Movement.SlideBoost then return end
            if char:GetAttribute("SlidingUntil") then
                TriggerSlideBoost()
            end
        end))
    end

    if anim then
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
end

HookSlideAnimation()
AddConn(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1.5)
    HookSlideAnimation()
end))

-- D) KUTU OTOMASYONU (Stabil ve Kesin Kutu Toplayıcı)
task.spawn(function()
    while true do
        if Config.Items.BoxTeleport then
            pcall(function()
                local root = GetRoot()
                local char = GetChar()
                local hum = GetHum()
                if not root or not char then return end
                local boxes = FindAllBoxes()
                local nearest, minD = nil, math.huge
                for _, b in ipairs(boxes) do
                    if b and b:IsA("BasePart") and b.CanTouch ~= false and b.Parent then
                        local d = (root.Position - b.Position).Magnitude
                        if d < minD then minD = d; nearest = b end
                    end
                end

                if nearest and nearest:IsA("BasePart") and nearest.CanTouch ~= false then
                    -- 1. Karakteri Hitbox'ın hemen üstüne konumlandır ve ivmesini sıfırla
                    local targetCFrame = nearest.CFrame + Vector3.new(0, 0.6, 0)
                    root.CFrame = targetCFrame
                    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                    if hum then hum:MoveTo(nearest.Position) end

                    -- 2. Çoklu uzuvlarla dokunma BAŞLAT (touch 0)
                    local touchParts = {
                        root,
                        char:FindFirstChild("RightFoot") or char:FindFirstChild("Right Leg") or char:FindFirstChild("RightLowerLeg"),
                        char:FindFirstChild("LeftFoot") or char:FindFirstChild("Left Leg") or char:FindFirstChild("LeftLowerLeg"),
                        char:FindFirstChild("LowerTorso") or char:FindFirstChild("Torso"),
                        char:FindFirstChild("UpperTorso")
                    }

                    if firetouchinterest then
                        for _, tp in ipairs(touchParts) do
                            if tp and tp:IsA("BasePart") then
                                pcall(firetouchinterest, tp, nearest, 0)
                            end
                        end
                    end

                    -- 3. Sunucunun pozisyon replikasyonunu ve dokunmayı işlemesi için 0.16s bekle (karakteri kutuda tut)
                    local waitStart = tick()
                    while tick() - waitStart < 0.18 do
                        if nearest.CanTouch == false or not nearest.Parent then break end
                        root.CFrame = targetCFrame
                        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        task.wait(0.03)
                    end

                    -- 4. Dokunmayı BİTİR (touch 1)
                    if firetouchinterest then
                        for _, tp in ipairs(touchParts) do
                            if tp and tp:IsA("BasePart") then
                                pcall(firetouchinterest, tp, nearest, 1)
                            end
                        end
                    end

                    -- 5. Kutu tamamen CanTouch == false olana kadar kısa bir kontrol beklemesi
                    local finishWait = tick()
                    while tick() - finishWait < 0.15 do
                        if nearest.CanTouch == false or not nearest.Parent then break end
                        task.wait(0.03)
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

-- 3. GK (AKILLI KALECİ SİSTEMİ)
local tGK = CreateTab("GK", "🧤")
tGK:AddSection("🧤 Akıllı Kaleci Sıçraması (By Umut)")
tGK:AddToggle("Otomatik Kaleci Atlama (Auto Dive)", Config.GK.AutoDive, function(v) Config.GK.AutoDive = v end, "Gelen tehlikeli sutlara dogru yonelerek kesin sicrar")
tGK:AddToggle("Sadece Şutlara Atla (Pas Filtresi)", Config.GK.SmartThreatOnly, function(v) Config.GK.SmartThreatOnly = v end, "Paslara, yavas toplara veya auta gidenlere kesinlikle atlamaz")
tGK:AddToggle("Kesin Top Tutma (100% Catch)", Config.GK.PerfectCatch, function(v) Config.GK.PerfectCatch = v end, "Top temas aninda ellerin arasinda kilitlenir, sekip gol olmaz")
tGK:AddToggle("Fiziksel İvme Desteği", Config.GK.BoostPhysical, function(v) Config.GK.BoostPhysical = v end, "Topu havada yetisip cikarmak icin ekstra sicrama ivmesi verir")

tGK:AddSection("🎮 Planjon Buton Kontrolleri & Test")
tGK:AddButton("🧤 Planjon Test Et (Şimdi Bas)", function()
    PressInGameDiveButton(true)
end)

tGK:AddButton("🎯 Butona Dokunarak Tanıt (Seçici)", function()
    _isPickingPlanjon = true
    GKNotify("Seçici Aktif", "Lütfen oyundaki Planjon/Atlama butonuna EKRANDAN DOKUNUN!")
    local pickerConn
    pickerConn = UserInputService.InputBegan:Connect(function(input)
        if not _isPickingPlanjon then
            if pickerConn then pickerConn:Disconnect() end
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            _isPickingPlanjon = false
            if pickerConn then pickerConn:Disconnect() end

            local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if not pgui then return end
            local objs = pgui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
            local selected = nil
            for _, o in ipairs(objs) do
                if guiRoot and not o:IsDescendantOf(guiRoot) then
                    selected = o
                    break
                end
            end
            if selected then
                _customPlanjonBtn = selected
                GKNotify("Başarılı!", "Planjon butonu bağlandı: " .. selected.Name)
                pcall(function()
                    local s = Instance.new("UIStroke")
                    s.Color = Color3.fromRGB(0, 255, 128)
                    s.Thickness = 3
                    s.Parent = selected
                    task.delay(2, function() pcall(function() s:Destroy() end) end)
                end)
            else
                GKNotify("Uyarı", "Geçerli buton bulunamadı, tekrar deneyin.")
            end
        end
    end)
end)

tGK:AddButton("🔍 Ekrandaki Butonları Tara & Listele", function()
    local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pgui then return end
    local count = 0
    print("================ [FUTBOLUMSU BUTON TARAMASI] ================")
    for _, obj in ipairs(pgui:GetDescendants()) do
        if obj:IsA("GuiObject") and (not guiRoot or not obj:IsDescendantOf(guiRoot)) and obj.Visible ~= false then
            local txt = ""
            if obj:IsA("TextButton") or obj:IsA("TextLabel") then txt = obj.Text end
            for _, c in ipairs(obj:GetChildren()) do
                if c:IsA("TextLabel") then txt = txt .. " " .. c.Text end
            end
            if txt ~= "" or obj:IsA("GuiButton") then
                count = count + 1
                print(string.format("[%d] İsim: %s | Metin: '%s' | Sınıf: %s", count, obj.Name, txt, obj.ClassName))
            end
        end
    end
    print("=============================================================")
    GKNotify("Tarama Tamamlandı", count .. " adet buton konsola yazdırıldı (F9).")
end)

tGK:AddButton("⚽ Manuel Topa Doğru Sıçra", function()
    local oldThreat = Config.GK.SmartThreatOnly
    Config.GK.SmartThreatOnly = false
    _lastDiveTime = 0
    pcall(RunGoalkeeperAI)
    Config.GK.SmartThreatOnly = oldThreat
end)

tGK:AddSection("⚙️ Kaleci İnce Ayarları")
tGK:AddSlider("Şut Hız Eşiği (Pas Limiti)", 10, 50, Config.GK.MinShotSpeed, function(v) Config.GK.MinShotSpeed = v end, " spd")
tGK:AddSlider("Kaleci Algılama Menzili", 15, 80, Config.GK.DiveRange, function(v) Config.GK.DiveRange = v end, " st")
tGK:AddSlider("Atlama Zamanlaması", 0.3, 1.8, Config.GK.TimeToGoalMax, function(v) Config.GK.TimeToGoalMax = v end, " sn")

-- 4. ESP (GÖRSEL ANALİZ)
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
