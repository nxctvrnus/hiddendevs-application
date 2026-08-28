--// made by: discord - sunrvtcxn, roblox - nxctvrnus
--// when you get into the game, you might need to get into the dungeon part, to do so please go to the hallway with elevators
--// for the record my alt is BigBotGuard (named after BigGuard20000 which is my past name) but my main account is nxctvrnus, i dont know why im verified under that in hiddendevs
--// context: this is a combat handler module that supports both players and enemies

local CombatService = {}

CombatService.__index = CombatService

--// Services
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local SoundService = game:GetService('SoundService')
local TweenService = game:GetService('TweenService')
local Players = game:GetService('Players')

local AnimationsService = require(ReplicatedStorage.Modules.AnimationsService)
local AudioService = require(ReplicatedStorage.Modules.AudioService)
local HitboxService = require(ReplicatedStorage.Modules.HitboxService)

--// Variables
local Animations = ReplicatedStorage.Assets.Animations
local Events = ReplicatedStorage.Events.Combat
local CachedWeaponData = {}
local CachedEnemyData = {}
local CombatData = {}

--// Store info from these modules for future reference
for _, v in ipairs(ReplicatedStorage.Assets.CombatInfo:GetChildren()) do
	CachedWeaponData[v.Name] = require(v)
end

for _, v in ipairs(script.EnemyData:GetChildren()) do
	CachedEnemyData[v.Name] = require(v)
end

--// Get the currently held weapon by Object, likely to be mostly used on players
local function LocateWeapon(Object: Model)
	for _, v in Object:GetChildren() do
		if v:GetAttribute('Weapon') then
			return v
		end
	end
end

function CombatService:Init(Object, SpawnPosition: Vector3?) --// SpawnPosition in case enemy is being initialised
	local self = setmetatable({}, CombatService)
	--// Declare stats
	self.Combo = 0
	self.Object = Object
	self.Posture = 0
	self.LastHit = 0
	self.Feinted = false
	self.Attacking = false
	self.Blocking = false
	self.Parrying = false
	
	local ParentDetector: RBXScriptConnection = nil
	local HuntTask: RBXScriptConnection = nil
	
	--// Check if an enemy is being registered
	if Object:GetAttribute('Enemy') then
		--// Store weapon which will be used in self for future reference
		self.Weapon = CachedEnemyData[Object.Name].Weapon
		if SpawnPosition then
			Object:PivotTo(CFrame.new(SpawnPosition))
		end
		Object.Parent = workspace
		--// Make enemy act on its own
		HuntTask = task.spawn(function()
			while task.wait(.5) do
				for _, v in Players:GetPlayers() do
					if (Object.HumanoidRootPart.Position - v.Character.HumanoidRootPart.Position).Magnitude < CachedEnemyData[Object.Name].DetectionRange then
						local Character = v.Character
						repeat
							if (Object.HumanoidRootPart.Position - Character.HumanoidRootPart.Position).Magnitude < CachedWeaponData[self.Weapon].Range + 2 then
								self:Attack()
							elseif (Object.HumanoidRootPart.Position - Character.HumanoidRootPart.Position).Magnitude < CachedEnemyData[Object.Name].DetectionRange - 2 then
								Object.Humanoid:MoveTo(Character.HumanoidRootPart.Position)
							else
								break
							end
							task.wait(.1)
						until Character.Humanoid.Health == 0
					end
				end
			end
		end)
	else
		--// Not enemy, instead store player in self for future reference
		self.Player = Players:GetPlayerFromCharacter(Object)
	end
	
	--// Wipe object from CombatData if destroyed unexpectedly
	ParentDetector = Object.AncestryChanged:Connect(function()
		if Object.Parent == nil then
			CombatData[Object] = nil
			ParentDetector:Disconnect()
		end
	end)
	
	--// Wipe object from CombatData upon death
	Object.Humanoid.Died:Once(function()
		CombatData[Object] = nil
		--// Disconnect ParentDetector connection to prevent memory leak
		ParentDetector:Disconnect()
		--// If is enemy then stop hunting players and create cool fading away effect
		if Object:GetAttribute('Enemy') then
			task.cancel(HuntTask)
			for _, v in Object:GetChildren() do
				if v:IsA('BasePart') then
					local tween = TweenService:Create(v, TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {Transparency = 1})
					tween:Play()
				end
			end
			task.wait(5)
			Object:Destroy()
		end
	end)
	
	--// Passively decrease posture 
	task.spawn(function()
		if self.Posture > 0 then
			--// math.clamp to keep strictly within 0 - 100 range, wouldn't want it to go into negative numbers
			self.Posture = math.clamp(self.Posture - 5, 0, 100)
		end
		task.wait(1)
	end)
	
	--// Store self in CombatData to be able to retrieve state
	CombatData[Object] = self

	return self
end

function CombatService:Attack(HitObjects)
	
	local function Reject(Reason: string)
		warn(`CombatService rejected attack request from {self.Object:GetFullName()} {self.Player and self.Player.UserId or '(Enemy)'}: {Reason}`)
		self.Attacking = false
	end
	
	--// Get weapon from the attacker
	local Weapon = LocateWeapon(self.Object) or self.Weapon
	
	--// Check if actually capable of attacking and everything is as should be
	if Weapon and not self.Attacking and not self.Blocking and not self.Parrying and self.Posture < 100 then
		
		self.Attacking = true
		
		--// Declare relevant info here in simpler terms to not make this a mess
		local RelevantWeapon = CachedWeaponData[Weapon.Name] or CachedWeaponData[self.Weapon]
		local WeaponTotalSwing = RelevantWeapon.SwingTime + RelevantWeapon.Endlag
		local RelevantAnimations = require(ReplicatedStorage.Assets.CombatInfo[RelevantWeapon.Name])
		
		--// Check if combo should've reset due to having attacked again too late
		if tick() - self.LastHit > RelevantWeapon.ComboWaitPeriod then
			self.Combo = 0
		end
		
		--// Add addtional wait time for finishing a combo
		if self.Combo == 4 then
			WeaponTotalSwing += RelevantWeapon.ComboWaitPeriod
		end
		
		--// +.15 for leniency
		if (tick() - self.LastHit + .15) < WeaponTotalSwing then
			Reject('would attack too fast')
			return
		end
		
		--// Allow for combo to increase if is smaller than or equal to 4
		if self.Combo <= 4 then
			self.Combo += 1
		end
		
		--// If attacker is enemy then make the server do animations for enemy as it can't play animations for itself unlike the player
		if self.Object:GetAttribute('Enemy') then
			if self.Combo == 1 then
				AnimationsService:PlayAnimation(self.Object, RelevantAnimations.Animations.Swing1, 'Swing1')
			elseif self.Combo == 2 then
				AnimationsService:StopAnimation(self.Object, 'Swing1')
				AnimationsService:PlayAnimation(self.Object, RelevantAnimations.Animations.Swing2, 'Swing2')
			elseif self.Combo == 3 then
				AnimationsService:StopAnimation(self.Object, 'Swing2')
				AnimationsService:PlayAnimation(self.Object, RelevantAnimations.Animations.Swing3, 'Swing3')
			elseif self.Combo == 4 then
				AnimationsService:StopAnimation(self.Object, 'Swing3')
				AnimationsService:PlayAnimation(self.Object,RelevantAnimations.Animations.Swing4, 'Swing4')
			end
		end
		
		--// Wait before actually checking hits
		task.wait(RelevantWeapon.SwingTime / 2)
		
		--// If enemy then get hitboxes, as there are none yet
		if not HitObjects then
			HitObjects = HitboxService:Hitbox(Vector3.new(RelevantWeapon.Range, RelevantWeapon.Range, RelevantWeapon.Range), self.Object.HumanoidRootPart.CFrame * CFrame.new(0, 0, -4), self.Object)
		end
		
		--// For each model that was in the hitbox check its status and continue accordingly
		for _, v in ipairs(HitObjects) do
			--// Sanity check
			if not self.Feinted and (self.Object:GetPivot().Position - v.HumanoidRootPart.Position).Magnitude < RelevantWeapon.Range + 2.8 and CombatData[v] then
				if CombatData[v].Parrying then
					AudioService:CreateSound(SoundService.Weapons.Combat.Parry, v)
					--// If attacker is player then let player know that they were parried, let them handle animation. Otherwise play animation for enemy
					if self.Player then
						Events.Parried:FireClient(self.Player)
					else
						AnimationsService:PlayAnimation(v, Animations.Combat.Parried, 'Parried')
					end
					--// Attacker was parried, reset combo and wait 1.2s before being able to do anything as punishment
					self.Combo = 0
					task.wait(1.2)
				elseif CombatData[v].Blocking then
					AudioService:CreateSound(SoundService.Weapons.Combat.Block, v)
					CombatData[v].Posture += RelevantWeapon.PostureDamage
					if CombatData[v].Posture >= 100 then
						v.Humanoid:TakeDamage(RelevantWeapon.Damage)
						AudioService:CreateSound(SoundService.Weapons.Combat.Guardbreak, v)
						--// If v is a player then let them know they were guardbroken, let them handle animation. Otherwise play animation for enemy
						if CombatData[v].Player then
							Events.GuardbrokenEvent:FireClient(Players:GetPlayerFromCharacter(v))
						else
							AnimationsService:PlayAnimation(v, Animations.Combat.Guardbroken, 'Guardbroken')
						end
						CombatData[v].Blocking = false
						task.wait(1.3)
						AnimationsService:StopAnimation(v, 'Guardbroken')
						CombatData[v].Posture = 0
					end
				else
					v.Humanoid:TakeDamage(RelevantWeapon.Damage)
					AudioService:CreateSound(game.SoundService.Weapons[RelevantWeapon.Name].Hit, v)
					local RandomNumber = math.random(1, 2)
					if RandomNumber == 1 then
						AnimationsService:StopAnimation(v, 'Damaged2')
						AnimationsService:PlayAnimation(v,Animations.Combat.Damaged1, 'Damaged1')
					else
						AnimationsService:StopAnimation(v, 'Damaged1')
						AnimationsService:PlayAnimation(v, Animations.Combat.Damaged2, 'Damaged2')
					end
				end
			elseif self.Feinted then
				AudioService:CreateSound(SoundService.Weapons.Combat.Feint, self.Object)
				return
			else
				Reject('Feinted or too far or target not found in CombatData')
				return
			end
		end
			
		self.LastHit = tick()
		self.Attacking = false
		
		if self.Combo >= 5 then
			self.Combo = 0
		end
	else
		Reject('Not holding weapon or occupied or staggered')
		return
	end
end

function CombatService:Block(state: 'Start' | 'End')
	
	local function Reject(Reason: string)
		warn(`CombatService rejected block request from {self.Object:GetFullName()} {self.Player and self.Player.UserId or '(Enemy)'}: {Reason}`)
		self.Attacking = false
	end
	
	--// Get weapon from the attacker
	local Weapon = LocateWeapon(self.Object) or self.Weapon
	
	--// Declare relevant info here in simpler terms to not make this a mess
	local RelevantWeapon = CachedWeaponData[Weapon.Name] or CachedWeaponData[self.Weapon]
	
	if state == 'Start' then
		--// Check if actually capable of blocking and everything is as should be
		if Weapon and not self.Attacking and not self.Blocking and not self.Parrying and self.Posture < 100 then
			self.Parrying = true
			task.wait(RelevantWeapon.ParryWindow)
			--// Check if still blocking, if so turn state into blocking
			if self.Parrying then
				self.Blocking = true
				self.Parrying = false
			end
		else
			Reject('Not holding weapon or occupied or guardbroken')
			return
		end
		
	elseif state == 'End' then
		self.Parrying = false
		self.Blocking = false
	end
end

function CombatService:Feint()
	--// Check if actually capable of feinting and everything is as should be
	if self.Attacking == true and not self.Feinted and not self.Blocking and not self.Parrying then
		self.Feinted = true
		self.Attacking = false
		task.wait(.3)
		self.Feinted = false
	end
end

return CombatService
