local LayerService = {}

LayerService.__index = LayerService

--// Services
local HttpService = game:GetService('HttpService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local ServerScriptService = game:GetService('ServerScriptService')
local CollectionService = game:GetService('CollectionService')

--// Variables
local Terrain = workspace.Terrain
local Enemies = ReplicatedStorage.Assets.Enemies
local Events = ReplicatedStorage.Events

local CombatService = require(ServerScriptService.Combat.CombatService)
local LayerInfo = require(script.LayerInfo)

local Chunks = {}

--// Perlin noise/chunk generation factors
local cell_size = 3
local chunk_size = 64
local resolution = 20
local frequency = 2
local amplification = 2

local center_size = chunk_size * 6
local seed = Random.new()

local render_distance = 15

--// Made not local to make script responsible for environment be able to see this
LayerService.CurrentLayer = 1

function LayerService:SetLayer(NewLayer)
	LayerService.CurrentLayer = NewLayer
	Terrain:SetMaterialColor(Enum.Material.Grass, LayerInfo.Layers[LayerService.CurrentLayer].GrassColor)
end

function LayerService:CreateChunk(Offset_CFrame: CFrame?)
	
	for i = 1, 3, 1 do
		--// Very small chance of failing but it's better to make this a pcall in case it does
		local success, error = pcall(function()
			--// Gonna have to prepare these in advance since we're going to desync
			local Targets = {}
			local CenterCf = nil

			task.desynchronize()

			for x = -chunk_size, chunk_size do
				for z = -chunk_size, chunk_size do
					--// i mean this is just perlin noise math what do you want me to say
					local height = math.noise(x/resolution*frequency, z/resolution*frequency) * amplification * cell_size
					--// Multiply by cell_size to not have everything mashed into a mess
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

			--// Throttle to not delay generation too much but also keep fps fairly stable
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

			local CenterPart = Instance.new('Part')
			CenterPart.Name = self.Id
			CenterPart.Anchored = true
			CenterPart.Size = Vector3.new(center_size, 50, center_size)
			CenterPart.CFrame = CenterCf
			CenterPart.Transparency = 1
			CenterPart.CanCollide = false
			CenterPart.CastShadow = false
			CenterPart.Parent = workspace.Chunks
			self.CenterPart = CenterPart

			--// Store self via own GUID
			Chunks[self.Id] = self

			for _, v in pairs(LayerInfo.Layers[LayerService.CurrentLayer].LayerEvents) do
				--// RNG check for whether event related asset will spawn
				if seed:NextInteger(1, 100) <= v.Chance then
					local RandomPosition = Vector3.new(seed:NextInteger(-math.floor(CenterPart.Size.X), math.floor(CenterPart.Size.X)), 0, seed:NextInteger(-math.floor(CenterPart.Size.Z), math.floor(CenterPart.Size.Z)))
					local asset: Model = v.Asset:Clone()
					--// Move to a random position within chunk + up depending on how tall the asset is
					asset:PivotTo(CFrame.new(self.CenterPart.Position + RandomPosition + Vector3.new(0, asset:GetExtentsSize().Y, 0)))
					asset.Parent = self.CenterPart
					CollectionService:AddTag(asset, asset.Name)
				end
			end

			--// RNG check for whether enemies will spawn
			if seed:NextInteger(1, 4) == 1 then
				--// RNG check for how many enemies to spawn
				for i = 1, seed:NextInteger(1, 2), 1 do
					local RandomPosition = Vector3.new(seed:NextInteger(-math.floor(CenterPart.Size.X),math.floor(CenterPart.Size.X)),
						3,
						seed:NextInteger(-math.floor(CenterPart.Size.Z), math.floor(CenterPart.Size.Z)))
					--// Must fire event and not directly interfere with enemy spawning to track combat data properly, also spawn random enemy from enemy pool of current layer
					ReplicatedStorage.Events.Environment.SpawnEnemy:Fire(LayerService:GetLayerInfo(LayerService.CurrentLayer).Enemies[seed:NextInteger(1, #LayerInfo.Layers[LayerService.CurrentLayer].Enemies)], RandomPosition)
				end
			end
			
			print(`LayerService - finished preparing Chunk {self.Id}`)
			
			return self
		end)
		
		if success then
			break
		else
			task.wait(.2)
		end
	end
end

function LayerService:DeleteChunk(id: string)
	local Chunk = Chunks[id]
	
	if Chunk then
		LayerService:WipeChunkEnemies(Chunk.Id)
		Terrain:FillBlock(Chunk.CenterPart.CFrame, Chunk.CenterPart.Size + Vector3.new(4, 4, 4), Enum.Material.Air)
		Chunk.CenterPart:Destroy()
		Chunks[id] = nil
	end
	
	print(`LayerService - finished deleting Chunk {id}`)
end

function LayerService:GetAvailableAdjacentCFrames(id: string)
	local results = {}
	local Chunk = Chunks[id]
	
	--// Declare targets already to not make an unreadable mess in the for loop
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
	
	--// Check whether there is already a CenterPart in GetPartBoundsInBox
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
				--// Check available spots which are within distance of chunk_size and the render distance
				if (v.Position - Player.Character.HumanoidRootPart.Position).Magnitude < chunk_size * render_distance then
					LayerService:CreateChunk(v)
				end
			end
		end
	end
end

function LayerService:WipeIrrelevantChunks()
	for _, v in pairs(Chunks) do
		local Preserve = false

		--// Must confirm that EVERY player is not within range
		for _, Player in Players:GetPlayers() do
			if (v.CenterPart.CFrame.Position - Player.Character.HumanoidRootPart.Position).Magnitude < chunk_size * (render_distance * 1.3) then
				Preserve = true
				break
			end
		end

		if Preserve == false then
			LayerService:DeleteChunk(v.Id)
		end
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

	--// Look through chunks which one's CenterPart is in results
	for _, v in pairs(Chunks) do
		if table.find(result, v.CenterPart) then
			return v
		end
	end
end

function LayerService:GetChunkFromCFrame(Cf: CFrame)
	local result = workspace:GetPartBoundsInBox(Cf, Vector3.new(0.01, 0.01, 0.01))
	
	--// Look through chunks which one's CenterPart is in results
	for _, v in pairs(Chunks) do
		if table.find(result, v.CenterPart) then
			return v
		end
	end
end

function LayerService:GetChunkEnemies(id: string)
	local targets = workspace:GetPartBoundsInBox(Chunks[id].CenterPart.CFrame, Vector3.new(center_size, center_size, center_size))
	local results = {}

	for _, v in pairs(targets) do
		if v:GetAttribute('Enemy') then
			table.insert(results, v)
		end
	end
	
	return results
end

function LayerService:WipeChunkEnemies(id: string)
	for _, v in pairs(LayerService:GetChunkEnemies(id)) do
		v:Destroy()
	end
end

function LayerService:GetLayerInfo(index)
	return LayerInfo.Layers[index]
end

return LayerService
