local IsValid = IsValid
local min = math.min
local random = math.random
local SimpleTimer = timer.Simple
local CurTime = CurTime

if ( CLIENT ) then
    SWEP.PrintName			= "Tranquilizer Gun"
    SWEP.Author			    = "YerSoMasher"
    SWEP.Instructions		= "Left mouse to fire a tranquilizer dart!"
    SWEP.Slot			    = 1
    SWEP.SlotPos			= 2
    SWEP.DrawAmmo			= true
    SWEP.DrawCrosshair		= true

    killicon.Add( "weapon_m9tranqgun", "lambdaplayers/killicons/icon_m9tranqgun", Color( 255, 80, 0, 255 ) )
end

SWEP.Spawnable              = true
SWEP.AdminOnly              = true
SWEP.Weight			        = 5
SWEP.AutoSwitchTo		    = false
SWEP.AutoSwitchFrom		    = false

SWEP.ViewModelFOV	        = 54
SWEP.ViewModel			    = "models/lambdaplayers/weapons/c_pist_m9_tranq.mdl"
SWEP.WorldModel			    = "models/lambdaplayers/weapons/w_pist_m9_tranq.mdl"
SWEP.UseHands               = true

SWEP.Primary.ClipSize		= -1
SWEP.Primary.DefaultClip	= 5
SWEP.Primary.Ammo		    = "XBowBolt"

SWEP.Secondary.ClipSize		= -1
SWEP.Secondary.DefaultClip	= -1
SWEP.Secondary.Ammo		    = "none"

SWEP.ShootSound             = Sound( "lambdaplayers/weapons/tranqgun/tranqgun_fire.mp3" )
SWEP.SlideSound             = Sound( "lambdaplayers/weapons/tranqgun/tranqgun_slide.mp3" )
SWEP.KillIconPath           = "lambdaplayers/killicons/icon_m9tranqgun"

function SWEP:Initialize()
	self:SetHoldType( "revolver" )
end

function SWEP:Deploy()
	self:SendWeaponAnim( ACT_VM_DRAW )
	self:SetNextPrimaryFire( CurTime() + 1.0 )
end

function SWEP:PrimaryAttack()
    if ( CLIENT ) then return end

    local owner = self:GetOwner()
    if !IsValid( owner ) then return end

    if owner:IsPlayer() and self:Ammo1() <= 0 then
		self:EmitSound( "Weapon_Pistol.Empty" )
		self:SetNextPrimaryFire( CurTime() + 0.2 )
        return
    end

    self:EmitSound( self.ShootSound, 70, random( 98, 102 ), 1, CHAN_WEAPON )
    self:SetNextPrimaryFire( CurTime() + 1.25 )
    self:SendWeaponAnim( ACT_VM_PRIMARYATTACK )

    local fireDir, firePos = owner:GetAimVector()
    if owner:IsPlayer() then
        owner:SetAnimation( PLAYER_ATTACK1 )
        self:TakePrimaryAmmo( 1 )

        local eyeTr = owner:GetEyeTrace()
        firePos = ( eyeTr.StartPos + fireDir * min( eyeTr.StartPos:Distance( eyeTr.HitPos ), 32 ) )
    else
        firePos = ( owner:GetShootPos() + fireDir * 32 )
    end

    M9TranqGun_FireDart( firePos, fireDir, owner, self )
end

function SWEP:SecondaryAttack()
end

function SWEP:Reload()
end

function SWEP:FireAnimationEvent( pos, ang, event, options )
    if options == "SlideRelease" then
        self:EmitSound( self.SlideSound, 70, random( 98, 102 ), 1, CHAN_WEAPON ) 
    end
end

function SWEP:CanBePickedUpByNPCs()
	return true
end

function SWEP:GetNPCBurstSettings()
	return 1, 1, 1.25
end

function SWEP:GetNPCRestTimes()
	return 1.25, 2.5
end

function SWEP:GetNPCBulletSpread()
	return 3
end

list.Add( "NPCUsableWeapons", { class = "weapon_m9tranqgun", title = "Tranquilizer Gun" } )