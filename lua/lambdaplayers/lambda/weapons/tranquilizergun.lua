local random = math.random
local CurTime = CurTime
local IsValid = IsValid
local isvector = isvector
local Rand = math.Rand

table.Merge( _LAMBDAPLAYERSWEAPONS, {
    tranquilizergun = {
        model = "models/lambdaplayers/weapons/w_pist_m9_tranq.mdl",
        origin = "Misc",
        prettyname = "Tranquilizer Gun",
        holdtype = "revolver",
        killicon = "weapon_m9tranqgun",
        bonemerge = true,

        clip = 1,
        deploydelay = 0.5,
        islethal = true,
        keepdistance = 600,
        attackrange = 1000,

        OnDeploy = function( lambda, wepent )
            lambda:SimpleWeaponTimer( 0.56, function()
                wepent:EmitSound( "lambdaplayers/weapons/tranqgun/tranqgun_slide.mp3", 70, random( 98, 102 ), 1, CHAN_WEAPON ) 
                wepent:ResetSequence( wepent:LookupSequence( "pullslide" ) )
                
                local pullAnim = lambda:AddGesture( ACT_HL2MP_GESTURE_RELOAD_AR2 )
                lambda:SetLayerCycle( pullAnim, 0.66 )
                lambda:SetLayerPlaybackRate( pullAnim, 1.25 )
            end )
        end,

        OnThink = function( lambda, wepent )
            if CurTime() > lambda.l_WeaponUseCooldown and !lambda:InCombat() and !lambda:IsPanicking() and random( 4 ) == 1 then
                local tranqRags = lambda:FindInSphere( nil, 750, function( ent )
                    return ( IsValid( ent:GetNW2Entity( "lambda_tranqgun_owner" ) ) and lambda:CanSee( ent ) )
                end )
                if #tranqRags > 0 then
                    local rndTarget = tranqRags[ random( #tranqRags ) ]
                    lambda:LookTo( rndTarget, 1.5 )

                    lambda:SimpleWeaponTimer( 1.0, function()
                        if !IsValid( rndTarget ) or lambda:InCombat() or lambda:IsPanicking() then return end
                        lambda:UseWeapon( rndTarget:GetPos() )
                    end )
                end
            end

            return 2
        end,

        OnAttack = function( lambda, wepent, target )
            local muzzlePos = wepent:GetAttachment( wepent:LookupAttachment( "muzzle" ) ).Pos
            local shootPos = ( isvector( target ) and target or target:WorldSpaceCenter() )

            local shootAng = ( shootPos - muzzlePos ):Angle()
            shootPos = ( shootPos + shootAng:Right() * random( -8, 8 ) + ( shootAng:Up() * ( random( -8, 8 ) + ( muzzlePos:Distance( shootPos ) / 30 ) ) ) )

            lambda:RemoveGesture( ACT_HL2MP_GESTURE_RANGE_ATTACK_REVOLVER )
            lambda:AddGesture( ACT_HL2MP_GESTURE_RANGE_ATTACK_REVOLVER, true )

            lambda.l_WeaponUseCooldown = ( CurTime() + Rand( 1.33, 3 ) )
            wepent:EmitSound( "lambdaplayers/weapons/tranqgun/tranqgun_fire.mp3", 70, random( 98, 102 ), 1, CHAN_WEAPON ) 

            lambda:SimpleWeaponTimer( 0.56, function()
                if lambda:GetState( "Tranquilized" ) then return end

                local pullAnim = lambda:AddGesture( ACT_HL2MP_GESTURE_RELOAD_AR2 )
                lambda:SetLayerCycle( pullAnim, 0.66 )
                lambda:SetLayerPlaybackRate( pullAnim, 1.25 )

                lambda:HandleShellEject( "ShellEject", vector_up * 6 ) 
                wepent:ResetSequence( wepent:LookupSequence( "pullslide" ) )
                wepent:EmitSound( "lambdaplayers/weapons/tranqgun/tranqgun_slide.mp3", 70, random( 98, 102 ), 1, CHAN_WEAPON ) 
            end )

            M9TranqGun_FireDart( muzzlePos, ( shootPos - muzzlePos ):GetNormalized(), lambda )
            return true
        end
    }
} )