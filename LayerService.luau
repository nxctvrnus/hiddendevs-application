--// made by: discord - sunrvtcxn 1136228276172501043, roblox - nxctvrnus 446408914
--// when you get into the game, you might need to get into the dungeon part, to do so please go to the hallway with elevators
local LayerService = {}

LayerService.__index = LayerService

--// Services
local HttpService = game:GetService('HttpService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local ServerScriptService = game:GetService('ServerScriptService')

--// Variables
local Terrain = workspace.Terrain
local Enemies = ReplicatedStorage.Assets.Enemies
local Events = ReplicatedStorage.Events

local CombatService = require(ServerScriptService.Combat.CombatService)
local LayerInfo = require(script.LayerInfo)

local Chunks = {}

local cell_size = 3
local chunk_size = 64
local resolution = 20
local frequency = 2
local amplification = 2
local center_size = chunk_size * 6
local seed = Random.new()

local render_distance = 15

LayerService.CurrentLayer = 1

function LayerService:SetLayer(NewLayer)
	LayerService.CurrentLayer = NewLayer
	Terrain:SetMaterialColor(Enum.Material.Grass, LayerInfo.Layers[LayerService.CurrentLayer].GrassColor)
end

function LayerService:CreateChunk(Offset_CFrame: CFrame?)
	
	local Targets = {}
	local CenterCf = nil
	
	task.desynchronize()

	for x = -chunk_size, chunk_size do
		for z = -chunk_size, chunk_size do
			local height = math.noise(x/resolution*frequency, z/resolution*frequency) * amplification * cell_size
			local Cf = CFrame.new(x * cell_size, height, z * cell_size)

			if Offset_CFrame then
				Cf *= Offset_CFrame
			end
			
			table.insert(Targets, Cf)
			
			if x == 0 and z == 0 then
				CenterCf = Cf
			end
		end
	end
	
	task.synchronize()
	
	local LastTick = tick()
	for _, v in pairs(Targets) do
		Terrain:FillBlock(v, Vector3.new(cell_size, cell_size, cell_size), Enum.Material.Grass)
		if tick() - LastTick > 0.02 then
			task.wait()
			LastTick = tick()
		end
	end
	
	local self = setmetatable({}, LayerService)
	self.Id = HttpService:GenerateGUID(false)
	self.PresentPlayers = {}
	self.Enemies = {}
	
	local CenterPart = Instance.new('Part')
	CenterPart.Name = self.Id
	CenterPart.Anchored = true
	CenterPart.Size = Vector3.new(center_size, 50, chunk_size * center_size)
	CenterPart.CFrame = CenterCf
	CenterPart.Transparency = 1
	CenterPart.CanCollide = false
	CenterPart.CastShadow = false
	CenterPart.Parent = workspace.Chunks
	self.CenterPart = CenterPart
	
	task.synchronize()
	
	print('created chunk '..self.Id)

	Chunks[self.Id] = self

	for _, v in pairs(LayerInfo.Layers[LayerService.CurrentLayer].LayerEvents) do
		--// RNG check for event
		if seed:NextInteger(1, 100) <= v.Chance then
			local RandomPosition = Vector3.new(math.random(-math.floor(CenterPart.Size.X), math.floor(CenterPart.Size.X)), 0, math.random(-math.floor(CenterPart.Size.Z), math.floor(CenterPart.Size.Z)))
			local asset: Model = v.Asset:Clone()
			asset:PivotTo(CFrame.new(self.CenterPart.Position + RandomPosition + Vector3.new(0, asset:GetExtentsSize().Y, 0)))
			asset.Parent = workspace
		end
	end
	
	--// RNG check for enemies
	if seed:NextInteger(1, 4) == 1 then
		--// RNG check for how many enemies to spawn
		for i = 1, seed:NextInteger(1, 2), 1 do
			local RandomPosition = Vector3.new(math.random(-math.floor(CenterPart.Size.X),math.floor(CenterPart.Size.X)),
				3,
				math.random(-math.floor(CenterPart.Size.Z), math.floor(CenterPart.Size.Z)))
			ReplicatedStorage.Events.Environment.SpawnEnemy:Fire(LayerInfo.Layers[LayerService.CurrentLayer].Enemies[seed:NextInteger(1, #LayerInfo.Layers[LayerService.CurrentLayer].Enemies)], RandomPosition)
		end
	end
	
	return self
end

function LayerService:DeleteChunk(id: string)
	local Chunk = Chunks[id]
	if Chunk then
		for _, v in pairs(workspace:GetPartsInPart(Chunk.CenterPart)) do
			if v.Parent and v.Parent.Name ~= 'Workspace' then
				v.Parent:Destroy()
			end
		end
		Terrain:FillBlock(Chunk.CenterPart.CFrame, Chunk.CenterPart.Size + Vector3.new(4, 4, 4), Enum.Material.Air)
		Chunk.CenterPart:Destroy()
		Chunks[id] = nil
		print('deleted chunk '..id)
	end
end

function LayerService:GetAvailableAdjacentCFrames(id: string)
	local results = {}
	local Chunk = Chunks[id]
	
	local targets = {
		left = Chunk.CenterPart.CFrame * CFrame.new(0, 0, -center_size * 6),
		front = Chunk.CenterPart.CFrame * CFrame.new(center_size, 0, 0),
		right = Chunk.CenterPart.CFrame * CFrame.new(0, 0, center_size),
		back = Chunk.CenterPart.CFrame * CFrame.new(-center_size, 0, 0),
		back_left = Chunk.CenterPart.CFrame * CFrame.new(-center_size, 0, -center_size),
		back_right = Chunk.CenterPart.CFrame * CFrame.new(-center_size, 0, center_size),
		front_left = Chunk.CenterPart.CFrame * CFrame.new(center_size, 0, -center_size),
		front_right = Chunk.CenterPart.CFrame * CFrame.new(center_size, 0, center_size)
	}
	
	for _, v in pairs(targets) do
		local overlaps = workspace:GetPartBoundsInBox(v, Vector3.one)
		if #overlaps == 0 then
			table.insert(results, v)
		end
	end
	
	return results
end

function LayerService:CreateEligibleAdjacentChunks()
	for _, Chunk in pairs(Chunks) do
		
		for _, Player in Players:GetPlayers() do
			for _, v in pairs(LayerService:GetAvailableAdjacentCFrames(Chunk.Id)) do
				if (v.Position - Player.Character.HumanoidRootPart.Position).Magnitude < chunk_size * render_distance then
					LayerService:CreateChunk(v)
				end
			end
		end
	end
end

function LayerService:WipeIrrelevantChunks()
	local IrrelevantChunks = {}
	
	task.desynchronize()
	
	for _, v in pairs(Chunks) do
		local Preserve = false

		for _, Player in Players:GetPlayers() do
			if (v.CenterPart.CFrame.Position - Player.Character.HumanoidRootPart.Position).Magnitude < chunk_size * (render_distance * 1.3) then
				Preserve = true
				break
			end
		end

		if Preserve == false then
			table.insert(IrrelevantChunks, v.Id)
		end
	end
	
	task.synchronize()
	
	for _, v in pairs(IrrelevantChunks) do
		LayerService:DeleteChunk(v)
	end
end

function LayerService:WipeAllChunks()
	for _, v in pairs(Chunks) do
		LayerService:DeleteChunk(v.Id)
	end
end

function LayerService:GetAmountOfChunks()
	local amount = 0
	
	for _, v in pairs(Chunks) do
		amount += 1
	end
	
	return amount
end

function LayerService:GetChunkFromPosition(Position: Vector3)
	local result = workspace:GetPartBoundsInBox(CFrame.new(Position), Vector3.new(0.01, 0.01, 0.01))

	for _, v in pairs(Chunks) do
		if table.find(result, v.CenterPart) then
			return v
		end
	end
end

function LayerService:GetChunkFromCFrame(Cf: CFrame)
	local result = workspace:GetPartBoundsInBox(Cf, Vector3.new(0.01, 0.01, 0.01))
	
	for _, v in pairs(Chunks) do
		if table.find(result, v.CenterPart) then
			return v
		end
	end
end

function WipeChunkEnemies(id: string)
	local result = workspace:GetPartBoundsInBox(Chunks[id].CenterPart.CFrame, Vector3.new(center_size, center_size, center_size))
	
	for _, v in pairs(result) do
		if v:GetAttribute('Enemy') then
			v:Destroy()
		end
	end
end

function GetLayerInfo(index)
	return LayerInfo.Layers[index]
end

return LayerService
