--[[
	Mobile UI Checker - by Doom Studio
	Finds UI problems that hurt phone and tablet players:
	  - buttons that overlap each other (or Roblox's thumbstick / jump button)
	  - buttons too small for a thumb
	  - things off the screen
	  - things under the notch / camera hole (outside the device safe area)
	  - things under Roblox's own top-left buttons
	  - text too small to read

	Use it in Play (Test > Play) with the Device Emulator for the real picture,
	or in Edit mode to check your StarterGui.
	Free to use. https://github.com/myflxr/mobile-ui-checker
]]

local CoreGui = game:GetService("CoreGui")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local StarterGui = game:GetService("StarterGui")

local VERSION = "1.0.0"
local SETTINGS_KEY = "DoomMobileUIChecker_v1"

-- Server side of a playtest has no screen: stay quiet there.
if RunService:IsRunning() and RunService:IsServer() and not RunService:IsClient() then
	return
end

local saved = plugin:GetSetting(SETTINGS_KEY) or {}
local config = {
	minTap = saved.minTap or 44, -- Apple / Google guideline: about 44 points
	minText = saved.minText or 12,
	showBoxes = saved.showBoxes ~= false,
}
local function saveConfig()
	plugin:SetSetting(SETTINGS_KEY, config)
end

------------------------------------------------------------------------------------------------
-- Geometry helpers. A rect is {x0, y0, x1, y1} in screen pixels (top-left of the whole window).
------------------------------------------------------------------------------------------------
local function rectOf(pos: Vector2, size: Vector2)
	return { pos.X, pos.Y, pos.X + size.X, pos.Y + size.Y }
end

local function intersect(a, b)
	local r = { math.max(a[1], b[1]), math.max(a[2], b[2]), math.min(a[3], b[3]), math.min(a[4], b[4]) }
	if r[3] <= r[1] or r[4] <= r[2] then
		return nil
	end
	return r
end

local function area(r)
	return (r[3] - r[1]) * (r[4] - r[2])
end

local function fmt(r)
	return string.format("%d×%d", math.floor(r[3] - r[1] + 0.5), math.floor(r[4] - r[2] + 0.5))
end

------------------------------------------------------------------------------------------------
-- Probes: tiny invisible ScreenGuis in CoreGui that tell us where the screen, the inset
-- origin and the device safe area are, in the same pixel space as the scanned UI.
------------------------------------------------------------------------------------------------
local probeFolder = Instance.new("Folder")
probeFolder.Name = "DoomMobileUIChecker"
probeFolder.Archivable = false

local function makeProbe(name, setup)
	local sg = Instance.new("ScreenGui")
	sg.Name = name
	sg.Archivable = false
	sg.ResetOnSpawn = false
	setup(sg)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.Parent = sg
	sg.Parent = probeFolder
	return f
end

local probeFull = makeProbe("ProbeFull", function(sg)
	sg.IgnoreGuiInset = true
	pcall(function()
		sg.ScreenInsets = Enum.ScreenInsets.None
	end)
end)
local probeSafe = makeProbe("ProbeSafe", function(sg)
	sg.IgnoreGuiInset = true
	pcall(function()
		sg.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
end)

local overlay = Instance.new("ScreenGui")
overlay.Name = "Boxes"
overlay.Archivable = false
overlay.IgnoreGuiInset = true
overlay.DisplayOrder = 1e6
overlay.ResetOnSpawn = false
pcall(function()
	overlay.ScreenInsets = Enum.ScreenInsets.None
end)
overlay.Parent = probeFolder

local okParent = pcall(function()
	probeFolder.Parent = CoreGui
end)

------------------------------------------------------------------------------------------------
-- Collecting the UI
------------------------------------------------------------------------------------------------
local function rootContainer()
	if RunService:IsRunning() then
		local lp = Players.LocalPlayer
		return lp and lp:FindFirstChildOfClass("PlayerGui"), "PlayerGui (Play)"
	end
	return StarterGui, "StarterGui (Edit)"
end

local function pathOf(inst: Instance)
	local parts = {}
	local cur = inst
	while cur and cur ~= game and not cur:IsA("PlayerGui") and cur ~= StarterGui do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(parts, ".")
end

-- Visible on screen? Checks Visible / Enabled up the chain and clips by ClipsDescendants parents.
local function visibleRect(obj: GuiObject)
	local r = rectOf(obj.AbsolutePosition, obj.AbsoluteSize)
	if r[3] - r[1] < 1 or r[4] - r[2] < 1 then
		return nil
	end
	local cur: Instance? = obj
	local uiScale = 1
	while cur do
		if cur:IsA("GuiObject") then
			if not cur.Visible then
				return nil
			end
			if cur ~= obj and cur.ClipsDescendants then
				r = intersect(r, rectOf(cur.AbsolutePosition, cur.AbsoluteSize))
				if not r then
					return nil
				end
			end
		elseif cur:IsA("LayerCollector") then
			if not cur.Enabled then
				return nil
			end
			return r, cur, uiScale
		end
		local scale = cur:FindFirstChildOfClass("UIScale")
		if scale then
			uiScale *= scale.Scale
		end
		cur = cur.Parent
	end
	return nil
end

local function isTappable(obj: GuiObject)
	if obj:IsA("GuiButton") then
		return obj.Active ~= false or obj:IsA("TextButton") or obj:IsA("ImageButton")
	end
	return obj:IsA("TextBox")
end

local function textPixels(obj, uiScale)
	if obj.Text == "" then
		return nil
	end
	if obj.TextScaled then
		local lines = 1
		if not obj.TextWrapped then
			local _, n = obj.Text:gsub("\n", "")
			lines += n
		end
		local h = obj.TextBounds.Y / lines
		if h <= 0 then
			return nil
		end
		return h
	end
	return obj.TextSize * uiScale
end

local function collect()
	local root, label = rootContainer()
	local items = {}
	if not root then
		return items, label
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiObject") then
			local r, layer, uiScale = visibleRect(d)
			if r then
				table.insert(items, {
					obj = d,
					rect = r,
					layer = layer,
					order = layer:IsA("ScreenGui") and layer.DisplayOrder or 0,
					tappable = isTappable(d),
					text = (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and textPixels(d, uiScale) or nil,
					roblox = layer.Name == "TouchGui", -- Roblox's thumbstick / jump live here
				})
			end
		end
	end
	return items, label
end

------------------------------------------------------------------------------------------------
-- The checks
------------------------------------------------------------------------------------------------
local function isAncestorOf(a: Instance, b: Instance)
	return b:IsDescendantOf(a)
end

-- Is the centre of item covered by an opaque window from a ScreenGui drawn on top?
local function coveredByWindow(item, items)
	local cx = (item.rect[1] + item.rect[3]) / 2
	local cy = (item.rect[2] + item.rect[4]) / 2
	for _, other in ipairs(items) do
		if other.layer ~= item.layer and other.order > item.order and not other.tappable
			and other.obj.BackgroundTransparency < 0.5
			and other.rect[1] <= cx and cx <= other.rect[3] and other.rect[2] <= cy and cy <= other.rect[4]
			and area(other.rect) > area(item.rect) * 4 then
			return true
		end
	end
	return false
end

local function scan()
	local items, label = collect()
	local issues = {}
	local function add(kind, obj, detail, rect, other)
		table.insert(issues, { kind = kind, obj = obj, detail = detail, rect = rect, other = other })
	end

	local full = rectOf(probeFull.AbsolutePosition, probeFull.AbsoluteSize)
	local safe = rectOf(probeSafe.AbsolutePosition, probeSafe.AbsoluteSize)
	if not okParent or area(full) < 1 then
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
		local inset = GuiService:GetGuiInset()
		full = { 0, -inset.Y, vp.X, vp.Y - inset.Y }
		safe = full
	end
	local robloxButtons
	pcall(function()
		local tb = GuiService.TopbarInset -- area to the right of Roblox's buttons
		if tb and tb.Height > 0 then
			robloxButtons = { full[1], full[2], full[1] + tb.Min.X, full[2] + tb.Height }
		end
	end)

	local taps = {}
	for _, it in ipairs(items) do
		if it.tappable then
			table.insert(taps, it)
		end
	end

	for _, it in ipairs(items) do
		local o = it.obj
		local hidden = coveredByWindow(it, items)
		local suffix = hidden and "  (under a window)" or ""
		if it.tappable and not it.roblox then
			local w, h = it.rect[3] - it.rect[1], it.rect[4] - it.rect[2]
			if math.min(w, h) < config.minTap then
				add("Small", o, string.format("%s, needs %d%s", fmt(it.rect), config.minTap, suffix), it.rect)
			end
		end
		if it.tappable or it.text then
			if not intersect(it.rect, full) then
				add("Off-screen", o, "completely outside the screen" .. suffix, it.rect)
			elseif area(intersect(it.rect, full)) < area(it.rect) - 1 then
				add("Off-screen", o, "partly outside the screen" .. suffix, it.rect)
			elseif it.tappable and area(intersect(it.rect, safe) or { 0, 0, 0, 0 }) < area(it.rect) - 1 and not it.roblox then
				add("Notch", o, "outside the device safe area (notch / camera hole)" .. suffix, it.rect)
			end
			if robloxButtons and it.tappable and not it.roblox and intersect(it.rect, robloxButtons) then
				add("Roblox buttons", o, "under Roblox's top-left buttons" .. suffix, it.rect)
			end
		end
		if it.text and it.text < config.minText then
			add("Tiny text", o, string.format("%.0f px, needs %d%s", it.text, config.minText, suffix), it.rect)
		end
	end

	for i = 1, #taps do
		for j = i + 1, #taps do
			local a, b = taps[i], taps[j]
			if not (a.roblox and b.roblox) and not isAncestorOf(a.obj, b.obj) and not isAncestorOf(b.obj, a.obj) then
				local r = intersect(a.rect, b.rect)
				if r and (r[3] - r[1]) >= 2 and (r[4] - r[2]) >= 2 then
					local first, second = a, b
					if a.roblox then
						first, second = b, a
					end
					local hidden = coveredByWindow(first, items) or coveredByWindow(second, items)
					add("Overlap", first.obj, "overlaps " .. (second.roblox and ("Roblox's " .. second.obj.Name) or pathOf(second.obj))
						.. " (" .. fmt(r) .. ")" .. (hidden and "  (under a window)" or ""), r, second.obj)
				end
			end
		end
	end
	return issues, label, #items
end

------------------------------------------------------------------------------------------------
-- Boxes on screen
------------------------------------------------------------------------------------------------
local COLORS = {
	Overlap = Color3.fromRGB(229, 64, 42),
	Small = Color3.fromRGB(255, 170, 0),
	["Off-screen"] = Color3.fromRGB(190, 80, 255),
	Notch = Color3.fromRGB(0, 170, 255),
	["Roblox buttons"] = Color3.fromRGB(0, 200, 140),
	["Tiny text"] = Color3.fromRGB(255, 230, 0),
}

local function drawBoxes(issues)
	overlay:ClearAllChildren()
	if not config.showBoxes then
		return
	end
	local origin = probeFull.AbsolutePosition
	for _, issue in ipairs(issues) do
		local r = issue.rect
		local box = Instance.new("Frame")
		box.Name = issue.kind
		box.BackgroundColor3 = COLORS[issue.kind]
		box.BackgroundTransparency = 0.8
		box.BorderSizePixel = 0
		box.Position = UDim2.fromOffset(r[1] - origin.X, r[2] - origin.Y)
		box.Size = UDim2.fromOffset(math.max(2, r[3] - r[1]), math.max(2, r[4] - r[2]))
		box.Active = false
		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS[issue.kind]
		stroke.Thickness = 2
		stroke.Parent = box
		box.Parent = overlay
	end
end

------------------------------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("Doom Studio")
local button = toolbar:CreateButton("Mobile UI Check", "Find UI problems for phone and tablet players", "rbxasset://textures/ui/GuiImagePlaceholder.png")
button.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui("DoomMobileUIChecker",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 360, 520, 300, 300))
widget.Title = "Mobile UI Checker"
widget.Name = "DoomMobileUIChecker"

local THEME = settings().Studio.Theme
local function col(c, fallback)
	local ok, v = pcall(function()
		return THEME:GetColor(c)
	end)
	return ok and v or fallback
end
local BG = col(Enum.StudioStyleGuideColor.MainBackground, Color3.fromRGB(46, 46, 46))
local FG = col(Enum.StudioStyleGuideColor.MainText, Color3.fromRGB(230, 230, 230))
local DIM = col(Enum.StudioStyleGuideColor.DimmedText, Color3.fromRGB(150, 150, 150))
local INPUT = col(Enum.StudioStyleGuideColor.InputFieldBackground, Color3.fromRGB(37, 37, 37))
local ACCENT = Color3.fromRGB(229, 64, 42)

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = BG
root.BorderSizePixel = 0
root.Parent = widget

local pad = Instance.new("UIPadding")
pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight =
	UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)
pad.Parent = root

local function label(text, size, color, parent, h)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.BuilderSans
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Size = UDim2.new(1, 0, 0, h or size + 6)
	l.Parent = parent
	return l
end

local function btn(text, parent, w, accent)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w, 0, 30)
	b.BackgroundColor3 = accent and ACCENT or INPUT
	b.TextColor3 = accent and Color3.new(1, 1, 1) or FG
	b.Font = Enum.Font.BuilderSansBold
	b.TextSize = 15
	b.Text = text
	b.AutoButtonColor = true
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	b.Parent = parent
	return b
end

local header = label("MOBILE UI CHECKER", 18, FG, root, 22)
header.Font = Enum.Font.BuilderSansBold
local sub = label("by Doom Studio · v" .. VERSION .. " · best in Play with the Device Emulator", 12, DIM, root, 16)
sub.Position = UDim2.fromOffset(0, 22)

local row = Instance.new("Frame")
row.BackgroundTransparency = 1
row.Position = UDim2.fromOffset(0, 46)
row.Size = UDim2.new(1, 0, 0, 30)
row.Parent = root
local rl = Instance.new("UIListLayout")
rl.FillDirection = Enum.FillDirection.Horizontal
rl.Padding = UDim.new(0, 6)
rl.Parent = row
local scanBtn = btn("SCAN", row, 80, true)
local watchBtn = btn("WATCH: OFF", row, 110)
local boxBtn = btn(config.showBoxes and "BOXES: ON" or "BOXES: OFF", row, 100)

local opts = Instance.new("Frame")
opts.BackgroundTransparency = 1
opts.Position = UDim2.fromOffset(0, 82)
opts.Size = UDim2.new(1, 0, 0, 26)
opts.Parent = root
local ol = Instance.new("UIListLayout")
ol.FillDirection = Enum.FillDirection.Horizontal
ol.VerticalAlignment = Enum.VerticalAlignment.Center
ol.Padding = UDim.new(0, 6)
ol.Parent = opts

local function numField(caption, key)
	local l = label(caption, 13, DIM, opts, 26)
	l.Size = UDim2.new(0, 70, 0, 26)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0, 46, 0, 24)
	box.BackgroundColor3 = INPUT
	box.TextColor3 = FG
	box.Font = Enum.Font.BuilderSans
	box.TextSize = 14
	box.Text = tostring(config[key])
	box.ClearTextOnFocus = false
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = box
	box.Parent = opts
	box.FocusLost:Connect(function()
		local n = tonumber(box.Text)
		if n and n > 0 and n < 400 then
			config[key] = math.floor(n)
			saveConfig()
		end
		box.Text = tostring(config[key])
	end)
end
numField("Min tap (px)", "minTap")
numField("Min text (px)", "minText")

local summary = label("Press SCAN.", 14, FG, root, 40)
summary.Position = UDim2.fromOffset(0, 114)
summary.RichText = true

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(0, 158)
list.Size = UDim2.new(1, 0, 1, -158)
list.BackgroundColor3 = INPUT
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = root
local ll = Instance.new("UIListLayout")
ll.Padding = UDim.new(0, 2)
ll.SortOrder = Enum.SortOrder.LayoutOrder
ll.Parent = list
local lp = Instance.new("UIPadding")
lp.PaddingLeft, lp.PaddingRight, lp.PaddingTop = UDim.new(0, 6), UDim.new(0, 6), UDim.new(0, 4)
lp.Parent = list

local ORDER = { "Overlap", "Small", "Off-screen", "Notch", "Roblox buttons", "Tiny text" }

local function show(issues, where, count, recorded)
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local counts = {}
	for _, i in ipairs(issues) do
		counts[i.kind] = (counts[i.kind] or 0) + 1
	end
	local parts = {}
	for _, k in ipairs(ORDER) do
		if counts[k] then
			table.insert(parts, string.format('<font color="#%s">%d %s</font>', COLORS[k]:ToHex(), counts[k], k:lower()))
		end
	end
	summary.Text = (#issues == 0 and '<font color="#3ccf6e"><b>No problems found ✓</b></font>' or ("<b>" .. #issues .. " problems</b>: " .. table.concat(parts, ", ")))
		.. string.format('\n<font color="#%s">%s · %d UI items%s</font>', DIM:ToHex(), where, count, recorded and " · watching (all screens so far)" or "")
	table.sort(issues, function(a, b)
		local ia, ib = table.find(ORDER, a.kind), table.find(ORDER, b.kind)
		if ia ~= ib then
			return ia < ib
		end
		return pathOf(a.obj) < pathOf(b.obj)
	end)
	for n, issue in ipairs(issues) do
		local r = Instance.new("TextButton")
		r.LayoutOrder = n
		r.Size = UDim2.new(1, 0, 0, 0)
		r.AutomaticSize = Enum.AutomaticSize.Y
		r.BackgroundTransparency = 1
		r.Font = Enum.Font.BuilderSans
		r.TextSize = 13
		r.TextWrapped = true
		r.RichText = true
		r.TextXAlignment = Enum.TextXAlignment.Left
		r.TextColor3 = FG
		r.Text = string.format('<font color="#%s"><b>%s</b></font>  %s\n<font color="#%s">%s</font>',
			COLORS[issue.kind]:ToHex(), issue.kind, pathOf(issue.obj), DIM:ToHex(), issue.detail)
		r.Parent = list
		r.MouseButton1Click:Connect(function()
			if issue.obj.Parent then
				Selection:Set(issue.other and issue.other.Parent and { issue.obj, issue.other } or { issue.obj })
			end
		end)
	end
end

-- Watch mode: keep scanning while you click through your menus; keep every problem seen.
local watching = false
local seen = {}
local seenList = {}

local function runOnce()
	local ok, issues, where, count = pcall(scan)
	if not ok then
		summary.Text = "Scan failed: " .. tostring(issues)
		return
	end
	if watching then
		for _, i in ipairs(issues) do
			local key = i.kind .. "|" .. i.obj:GetFullName() .. "|" .. (i.other and i.other:GetFullName() or "")
			if not seen[key] then
				seen[key] = true
				table.insert(seenList, i)
			end
		end
		drawBoxes(issues)
		show(table.clone(seenList), where, count, true)
	else
		drawBoxes(issues)
		show(issues, where, count, false)
	end
end

scanBtn.MouseButton1Click:Connect(runOnce)

boxBtn.MouseButton1Click:Connect(function()
	config.showBoxes = not config.showBoxes
	saveConfig()
	boxBtn.Text = config.showBoxes and "BOXES: ON" or "BOXES: OFF"
	if not config.showBoxes then
		overlay:ClearAllChildren()
	end
end)

watchBtn.MouseButton1Click:Connect(function()
	watching = not watching
	watchBtn.Text = watching and "WATCH: ON" or "WATCH: OFF"
	watchBtn.BackgroundColor3 = watching and ACCENT or INPUT
	if watching then
		seen, seenList = {}, {}
		task.spawn(function()
			while watching do
				runOnce()
				task.wait(1)
			end
		end)
	end
end)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
	if not widget.Enabled then
		watching = false
		watchBtn.Text = "WATCH: OFF"
		watchBtn.BackgroundColor3 = INPUT
		overlay:ClearAllChildren()
	end
end)

-- For automated tests / other tools: CoreGui.DoomMobileUIChecker.Scan:Invoke() returns plain results.
local hook = Instance.new("BindableFunction")
hook.Name = "Scan"
hook.Archivable = false
hook.OnInvoke = function(drawOnScreen)
	local issues, where, count = scan()
	if drawOnScreen then
		drawBoxes(issues)
	end
	local out = { where = where, items = count, issues = {} }
	for _, i in ipairs(issues) do
		table.insert(out.issues, { kind = i.kind, path = pathOf(i.obj), detail = i.detail })
	end
	return out
end
hook.Parent = probeFolder

plugin.Unloading:Connect(function()
	watching = false
	probeFolder:Destroy()
end)
