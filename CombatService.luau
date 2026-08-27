--// 27 08 2026 made by nxctvrnus all rights not reserved
--// when you get into the game, you might need to get into the dungeon part, to do so please go to the hallway with elevators
--// for the record my alt is BigBotGuard (named after BigGuard20000 which is my past name) but my main account is nxctvrnus, i dont know why im verified under that in hiddendevs

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

--// Get weapon
local function LocateWeapon(Object: Model)
	for _, v in Object:GetChildren() do
		if v:GetAttribute('Weapon') then
			return v
		end
	end
end

function CombatService:Init(Object, SpawnPosition: Vector3?)
	local self = setmetatable({}, CombatService)
	self.Combo = 0
	self.Object = Object
	self.Posture = 0
	self.LastHit = 0
	self.Feinted = false
	self.Attacking = false
	self.Blocking = false
	self.Parrying = false
	
	if Object:GetAttribute('Enemy') then
		self.Weapon = CachedEnemyData[Object.Name].Weapon
		if SpawnPosition then
			Object:PivotTo(CFrame.new(SpawnPosition.X, SpawnPosition.Y, SpawnPosition.Z))
		end
		Object.Parent = workspace
		--// Make enemy act on its own
		self.HuntTask = task.spawn(function()
			while task.wait(.5) do
				for _, v in Players:GetPlayers() do
					if (Object.HumanoidRootPart.Position - v.Character.HumanoidRootPart.Position).Magnitude < CachedEnemyData[Object.Name].DetectionRange then
						local Character = v.Character
						repeat
							if (Object.HumanoidRootPart.Position - Character.HumanoidRootPart.Position).Magnitude < CachedWeaponData[self.Weapon].Range + 2 then
								self:Attack()
							elseif (Object.HumanoidRootPart.Position - Character.HumanoidRootPart.Position).Magnitude < CachedEnemyData[Object.Name].DetectionRange then
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
		self.Player = Players:GetPlayerFromCharacter(Object)
	end
	
	Object.Humanoid.Died:Once(function()
		CombatData[Object] = nil
		if Object:GetAttribute('Enemy') then
			task.cancel(self.HuntTask)
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
	
	task.spawn(function()
		if self.Posture > 0 then
			--// Math clamp to keep it strictly within 0-100 range
			self.Posture = math.clamp(self.Posture - 5, 0, 100)
		end
		task.wait(1)
	end)
	
	CombatData[Object] = self

	return self
end

function CombatService:Attack(HitObjects)
	
	local function Reject(Reason: string)
		warn(`CombatService rejected attack request from {self.Object:GetFullName()} {self.Player and self.Player.UserId or '(Enemy)'}: {Reason}`)
		self.Attacking = false
	end

	--// Get weapon depending whether is player or enemy
	local Weapon = LocateWeapon(self.Object) or self.Weapon
	
	if Weapon and not self.Attacking and not self.Blocking and not self.Parrying and self.Posture < 100 then
		
		self.Attacking = true
		
		local RelevantWeapon = CachedWeaponData[Weapon.Name] or CachedWeaponData[self.Weapon]
		local WeaponTotalSwing = RelevantWeapon.SwingTime + RelevantWeapon.Endlag
		local RelevantAnimations = require(ReplicatedStorage.Assets.CombatInfo[RelevantWeapon.Name])
		
		if tick() - self.LastHit > RelevantWeapon.ComboWaitPeriod then
			self.Combo = 0
		end
		
		if self.Combo == 4 then
			WeaponTotalSwing += RelevantWeapon.ComboWaitPeriod
		end
		
		if (tick() - self.LastHit + .15) < WeaponTotalSwing then
			Reject('would attack too fast')
			return
		end
		
		if self.Combo <= 4 then
			self.Combo += 1
		end

		--// Need to play animation for enemy if enemy is attacking
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

		--// Must use task.wait() to ensure proper timing
		task.wait(RelevantWeapon.SwingTime / 2)
		
		if not self.Feinted then
			--// Make sure we scan everything in range as enemy can't do the homework beforehand
			if not HitObjects then
				HitObjects = HitboxService:Hitbox(Vector3.new(RelevantWeapon.Range, RelevantWeapon.Range, RelevantWeapon.Range), self.Object.HumanoidRootPart.CFrame * CFrame.new(0, 0, -4), self.Object)
			end

			for _, v in pairs(HitObjects) do
				--// Add 2.8 for leniency
				if (self.Object:GetPivot().Position - v.HumanoidRootPart.Position).Magnitude < RelevantWeapon.Range + 2.8 then
					if CombatData[v] then
						if CombatData[v].Parrying then
							AudioService:CreateSound(SoundService.Weapons.Combat.Parry, v)
							AnimationsService:PlayAnimation(self.Object, Animations.Combat.Parried, 'Parried')
							if self.Player then
								Events.Parried:FireClient(self.Player)
							end
							self.Combo = 0
							task.wait(1.2)
						elseif CombatData[v].Blocking then
							AudioService:CreateSound(SoundService.Weapons.Combat.Block, v)
							CombatData[v].Posture += RelevantWeapon.PostureDamage
							if CombatData[v].Posture >= 100 then
								task.spawn(function()
									AudioService:CreateSound(SoundService.Weapons.Combat.Guardbreak, v)
									AnimationsService:PlayAnimation(v, Animations.Combat.Guardbroken, 'Guardbroken')
									if CombatData[v].Player then
										Events.GuardbrokenEvent:FireClient(Players:GetPlayerFromCharacter(v))
									end
									CombatData[v].Blocking = false
									task.wait(1.3)
									if CombatData[v] then
										AnimationsService:StopAnimation(v, 'Guardbroken')
										CombatData[v].Posture = 0
									end
								end)
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
					else
						Reject('target isnt registered')
						return
					end
				else
					Reject('too far from target')
					return
				end
			end
			
			self.LastHit = tick()
			self.Attacking = false
		end
		
		if self.Combo >= 5 then
			self.Combo = 0
		end
		
	else
		Reject('not holding weapon or occupied or staggered')
		return
	end
end

function CombatService:Block(state: 'Start' | 'End')
	
	local function Reject(Reason: string)
		warn(`CombatService rejected block request from {self.Object:GetFullName()} {self.Player and self.Player.UserId or '(Enemy)'}: {Reason}`)
		self.Attacking = false
	end
	
	local Weapon = LocateWeapon(self.Object) or self.Weapon
	
	local RelevantWeapon = CachedWeaponData[Weapon.Name] or CachedWeaponData[self.Weapon]
	
	if state == 'Start' then
		if Weapon and not self.Attacking and not self.Blocking and not self.Parrying and self.Posture < 100 then
			self.Parrying = true
			task.wait(RelevantWeapon.ParryWindow)
			if self.Parrying then
				self.Blocking = true
				self.Parrying = false
			end
		else
			Reject('not holding weapon or occupied or staggered')
			return
		end
		
	elseif state == 'End' then
		self.Parrying = false
		self.Blocking = false
	end
end

function CombatService:Feint()
	if self.Attacking == true and not self.Feinted and not self.Blocking and not self.Parrying then
		self.Feinted = true
		task.wait(.3)
		self.Feinted = false
		self.Attacking = false
	end
end

return CombatService
