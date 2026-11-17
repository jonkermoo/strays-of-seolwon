--!strict
-- Plain debug UI helpers: default fonts, grey boxes, no styling. Replaced by the real menus
-- once the style bible is approved.

local DebugUi = {}

function DebugUi.screen(parent: Instance, name: string): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.Parent = parent
	return gui
end

-- A vertical list panel at a position (scale x, scale y) with a fixed width in pixels.
function DebugUi.panel(parent: Instance, x: number, y: number, width: number, height: number): Frame
	local f = Instance.new("Frame")
	f.Position = UDim2.new(x, 8, y, 8)
	f.Size = UDim2.fromOffset(width, height)
	f.BackgroundTransparency = 0.3
	f.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = f
	return f
end

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

function DebugUi.label(parent: Instance, text: string, height: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, height or 18)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.Text = text
	l.LayoutOrder = nextOrder()
	l.Parent = parent
	return l
end

function DebugUi.button(parent: Instance, text: string, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 22)
	b.Text = text
	b.LayoutOrder = nextOrder()
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

function DebugUi.clear(container: Instance)
	for _, c in container:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

-- A scrolling list area that keeps its own layout.
function DebugUi.scroll(parent: Instance, height: number): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Size = UDim2.new(1, 0, 0, height)
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	s.LayoutOrder = nextOrder()
	s.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = s
	return s
end

function DebugUi.rowText(row: any): string
	local where = if row.state == "frozen"
		then `frozen, ends in {math.floor((row.endsIn or 0) / 3600)} h`
		else `{row.players}/{row.max}`
	return `{if row.friend then "[friend] " else ""}Day {row.day} · {where}{if row.full
		then " · full"
		else ""}`
end

return DebugUi
