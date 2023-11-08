local Rand = math.Rand
local Remap = math.Remap
local CurTime = CurTime
local ents_Create = ents.Create
local ipairs = ipairs
local CurTime = CurTime
local IsValid = IsValid
local util_Effect = util.Effect
local SpriteTrail = util.SpriteTrail
local EffectData = EffectData
local DamageInfo = DamageInfo
local IsFirstTimePredicted = IsFirstTimePredicted
local SafeRemoveEntityDelayed = SafeRemoveEntityDelayed
local random = math.random
local TraceLine = util.TraceLine
local isnumber = isnumber
local isvector = isvector
local SimpleTimer = timer.Simple
local CreateTimer = timer.Create
local TimerExists = timer.Exists
local TimerTimeLeft = timer.TimeLeft
local AdjustTimer = timer.Adjust
local IsValidProp = util.IsValidProp
local IsValidRagdoll = util.IsValidRagdoll
local IsValidModel = util.IsValidModel
local ents_GetAll = ents.GetAll
local max = math.max
local min = math.min
local ismatrix = ismatrix
local hook_Remove = hook.Remove

local traceTbl = {}
local trailClr = Color( 255, 255, 255, 125 )
local dartScale = Vector( 0.4, 0.8, 0.4 )

local livingBeingMat = {
    [ MAT_ALIENFLESH ] = true,
    [ MAT_BLOODYFLESH ] = true,
    [ MAT_ANTLION ] = true,
    [ MAT_FLESH ] = true
}

local sv_npctranqgun_hitdamage = CreateConVar( "sv_npctranqgun_hitdamage", "0", ( FCVAR_REPLICATED + FCVAR_ARCHIVE ), "How much damage does the tranquilizer's darts deal? Scales depending on how close the hit were from the target's head.", 0, 100 )
local sv_npctranqgun_sleeptime = CreateConVar( "sv_npctranqgun_sleeptime", "30", ( FCVAR_REPLICATED + FCVAR_ARCHIVE ), "For how long the target that are put down can sleep until they finally wake up. Scales depending on how close the hit were from the target's head.", 0, 600 )
local sv_npctranqgun_knockouttime = CreateConVar( "sv_npctranqgun_knockouttime", "3", ( FCVAR_REPLICATED + FCVAR_ARCHIVE ), "For how long the target that's been shot with dart can stand on foot until passing out. Scales depending on how close the hit were from the target's head.", 0, 60 )
local sv_npctranqgun_physdmgthreshold = CreateConVar( "sv_npctranqgun_physdmgthreshold", "10", ( FCVAR_REPLICATED + FCVAR_ARCHIVE ), "How big should the physical damage dealt to a ragdoll to be in order for it to count for the entity?", 0, 1000 )
local sv_npctranqgun_dropweapon = CreateConVar( "sv_npctranqgun_dropweapon", "0", ( FCVAR_REPLICATED + FCVAR_ARCHIVE ), "If the NPC should drop their weapon instead of still holding it when knocked out.", 0, 1 )

local function GetHeadPosition( ent )
    local bone = ent:LookupBone( "ValveBiped.Bip01_Head1" )
    if !bone then
        local setCount = ent:GetHitboxSetCount()
        if isnumber( setCount ) then
            for hboxSet = 0, ( setCount - 1 ) do
                for hitbox = 0, ( ent:GetHitBoxCount( hboxSet ) - 1 ) do
                    if ent:GetHitBoxHitGroup( hitbox, hboxSet ) != HITGROUP_HEAD then continue end
                    bone = ent:GetHitBoxBone( hitbox, hboxSet ); break
                end
            end
        end
    end

    if !bone then
        local eyePos = ent:EyePos()
        return ( eyePos == ent:GetPos() and ent:WorldSpaceCenter() or eyePos )
    end

    local matrix = ent:GetBoneMatrix( bone )
    return ( ismatrix( matrix ) and matrix:GetTranslation() or ( ent:GetBonePosition( bone ) or ent:EyePos() ) )
end

local function GetBurnEndTime( ent )
    for _, child in ipairs( ent:GetChildren() ) do
        if !IsValid( child ) or child:GetClass() != "entityflame" then continue end
        local lifeTime = child:GetInternalVariable( "lifetime" )
        if lifeTime and isnumber( lifeTime ) then return lifeTime end
    end

    return 5
end

if ( SERVER ) then
    local coroutine_yield = coroutine.yield
    local coroutine_wait = coroutine.wait
    local NormalizeAngle = math.NormalizeAngle
    local abs = math.abs
    local CreateSound = CreateSound
    local LerpVector = LerpVector
    local LerpAngle = LerpAngle

    traceTbl.filter = {}

    if LambdaIsForked then
        local function OnLambdaInitialize( lambda, weapon )
            lambda.l_TranqGun_HitTime = false
            lambda.l_TranqGun_State = 0
            lambda.l_TranqGun_Ragdoll = nil

            function lambda:Tranquilized()
                lambda.l_isfrozen = true
                lambda.l_UpdateAnimations = false
                lambda:RemoveAllGestures()
                lambda:EmitSound( "lambdaplayers/weapons/tranqgun/vo_presleep" .. random( 7 ) .. ".mp3", 70, lambda:GetVoicePitch(), 1, CHAN_VOICE )
                lambda:SimpleTimer( 0.1, function() lambda:StopCurrentVoiceLine() end )

                if lambda.l_TranqGun_State == 0 then
                    lambda:DropWeapon()
                    lambda.l_TranqGun_State = 1

                    local wepent = lambda.WeaponEnt
                    lambda:ClientSideNoDraw( wepent, true )
                    wepent:SetNoDraw( true )
                    wepent:DrawShadow( false )

                    lambda.l_Clip = lambda.l_MaxClip
                    lambda.l_WeaponUseCooldown = ( CurTime() + 5 )

                    local preVel = lambda.loco:GetVelocity()
                    lambda.loco:SetVelocity( vector_origin )

                    if lambda:IsOnGround() and preVel:Length() <= 300 then
                        local downTime = lambda:SetSequence( "death_0" .. random( 4 ) )
                        lambda:ResetSequenceInfo()
                        lambda:SetCycle( 0 )

                        local speed = Rand( 1.1, 1.33 )
                        lambda:SetPlaybackRate( speed )

                        downTime = ( CurTime() + ( ( downTime / speed ) * Rand( 0.66, 1 ) ) )
                        while ( CurTime() < downTime and lambda.l_TranqGun_State == 1 ) do
                            coroutine_yield()
                        end
                    end
                end
                lambda:PreventWeaponSwitch( true )

                for _, v in ipairs( GetLambdaPlayers() ) do
                    if v:GetEnemy() != lambda then continue end
                    v:SetEnemy( NULL )
                    if v:GetState( "Combat" ) then v:SetState( "Idle" ) end
                    v:CancelMovement()
                end

                lambda:ClientSideNoDraw( lambda, true )
                lambda:SetNoDraw( true )
                lambda:DrawShadow( false )

                lambda.l_TranqGun_State = 3
                lambda:SwitchWeapon( "none", true )

                local lastColl = lambda:GetCollisionGroup()
                lambda:SetCollisionGroup( COLLISION_GROUP_IN_VEHICLE )
                lambda:GetPhysicsObject():EnableCollisions( false )

                local ragdoll = lambda:CreateServersideRagdoll( lambda.l_TranqGun_PreRagdollDmg, nil, true )
                ragdoll:SetNW2Entity( "lambda_tranqgun_owner", lambda )
                ragdoll:SetCollisionGroup( COLLISION_GROUP_WEAPON )
                lambda.l_TranqGun_PreRagdollDmg = nil

                local blinkFlex = ragdoll:GetFlexIDByName( "blink" )
                if blinkFlex then ragdoll:SetFlexWeight( blinkFlex, 1 ) end

                if lambda:IsOnFire() then
                    ragdoll:Ignite( GetBurnEndTime( lambda ) )
                    lambda:Extinguish()
                end

                local snoreSnd = CreateSound( ragdoll, "lambdaplayers/weapons/tranqgun/vo_snoring" .. random( 3 ) .. ".wav" )
                if snoreSnd then
                    snoreSnd:PlayEx( 1, lambda:GetVoicePitch() )
                    snoreSnd:SetSoundLevel( 65 )
                    ragdoll.l_TranqGun_SnoreSnd = snoreSnd
                end

                lambda.l_TranqGun_Ragdoll = ragdoll
                if RDReagdollMaster then 
                    SimpleTimer( 0.1, function() RDReagdollMaster.Kill( ragdoll, true ) end )
                end

                local hiddenChildren = {}
                for _, child in ipairs( lambda:GetChildren() ) do
                    if !IsValid( child ) or child == lambda.WeaponEnt or child:GetNoDraw() then continue end

                    local mdl = child:GetModel()
                    if !mdl or !IsValidModel( mdl ) then continue end

                    lambda:ClientSideNoDraw( child, true )
                    child:SetRenderMode( RENDERMODE_NONE )
                    child:DrawShadow( false )

                    local fakeChild = ents_Create( "base_gmodentity" )
                    fakeChild:SetModel( mdl )
                    fakeChild:SetPos( ragdoll:GetPos() )
                    fakeChild:SetAngles( ragdoll:GetAngles() )
                    fakeChild:Spawn()
                    fakeChild:SetParent( ragdoll )
                    fakeChild:AddEffects( EF_BONEMERGE )
                    ragdoll:DeleteOnRemove( fakeChild )

                    hiddenChildren[ #hiddenChildren + 1 ] = child
                end
                

                ragdoll.l_TranqGun_DropTime = CurTime()
                while ( IsValid( ragdoll ) and ( CurTime() - ragdoll.l_TranqGun_DropTime ) < sv_npctranqgun_sleeptime:GetFloat() ) do
                    coroutine_yield()
                end

                --

                local function UnHideLambda()
                    for _, child in ipairs( hiddenChildren ) do
                        if !IsValid( child ) then continue end
                        lambda:ClientSideNoDraw( child, false )
                        child:SetRenderMode( RENDERMODE_NORMAL )
                        child:DrawShadow( true )
                    end
        
                    lambda:ClientSideNoDraw( lambda, false )
                    lambda:SetNoDraw( false )
                    lambda:DrawShadow( true )
                end

                lambda:SetCollisionGroup( lastColl )
                lambda:GetPhysicsObject():EnableCollisions( true )

                lambda:PreventWeaponSwitch( false )
                lambda.l_TranqGun_State = 4

                if IsValid( ragdoll ) then
                    local ragPos = ragdoll:GetPos()
                    lambda:SetPos( ragPos )

                    local phys = ragdoll:GetPhysicsObject()
                    local ragAng = ( IsValid( phys ) and phys or ragdoll ):GetAngles()
                    local ragZ = ragAng.z

                    ragAng.x = 0
                    ragAng.y = NormalizeAngle( ragAng.y + 270 )
                    ragAng.z = 0
                    lambda:SetAngles( ragAng )

                    if ragdoll:IsOnFire() then
                        lambda:Ignite( GetBurnEndTime( ragdoll ) )
                    end

                    traceTbl.start = ( ragPos + vector_up * 6 )
                    traceTbl.endpos = ( ragPos - vector_up * 32 )
                    traceTbl.filter[ 1 ] = ragdoll
                    traceTbl.filter[ 2 ] = lambda

                    if TraceLine( traceTbl ).Hit then
                        local ragMoveData = {}
                        local ragRemoveTime = ( CurTime() + 0.4 )
                        
                        for i = 0, ( ragdoll:GetPhysicsObjectCount() - 1 ) do
                            local phys = ragdoll:GetPhysicsObjectNum( i )
                            if !IsValid( phys ) then continue end

                            local physBone = ragdoll:TranslatePhysBoneToBone( i )
                            if !physBone then continue end

                            phys:EnableCollisions( false )

                            ragMoveData[ #ragMoveData + 1 ] = { 
                                phys, 
                                physBone,
                                phys:GetPos(), 
                                phys:GetAngles() 
                            }
                        end

                        local faceDown = ( abs( NormalizeAngle( ragZ ) ) > 70 )
                        local wakeTime = lambda:SetSequence( "zombie_slump_rise_0" .. ( faceDown and "1" or "2_fast" ) )

                        lambda:ResetSequenceInfo()
                        lambda:SetCycle( 0 )
        
                        local speed = ( faceDown and Rand( 1.2, 1.33 ) or Rand( 0.7, 0.85 ) )
                        lambda:SetPlaybackRate( speed )

                        wakeTime = ( CurTime() + ( ( wakeTime / speed ) * ( faceDown and 0.7 or 0.55 ) ) )
                        while ( CurTime() < wakeTime ) do
                            if lambda.l_TranqGun_State == 5 then
                                lambda.l_isfrozen = false
                                return 
                            end

                            if ragRemoveTime then 
                                local lerpVal = ( 1 - ( ragRemoveTime - CurTime() ) / 0.4 )
                                if lerpVal > 1 then lerpVal = 1 end

                                for _, data in ipairs( ragMoveData ) do
                                    local phys = data[ 1 ]
                                    local pos, ang = lambda:GetBonePosition( data[ 2 ] )

                                    phys:SetPos( LerpVector( lerpVal, data[ 3 ], pos ) )
                                    phys:SetAngles( LerpAngle( lerpVal, data[ 4 ], ang ) )
                                end

                                if CurTime() >= ragRemoveTime then
                                    UnHideLambda()
                                    ragRemoveTime = nil 
                                    ragdoll:Remove()
                                end
                            end

                            coroutine_yield()
                        end

                        local anims = lambda:GetWeaponHoldType()
                        if anims then lambda:StartActivity( anims.idle ) end
                    else
                        UnHideLambda()
                        lambda.loco:SetVelocity( ragdoll:GetVelocity() )
                        ragdoll:Remove()
                    end
                else
                    UnHideLambda()
                end

                lambda.l_UpdateAnimations = true
                lambda.l_isfrozen = false
                lambda.l_TranqGun_State = 0

                return true
            end
        end

        local function OnLambdaRemoved( lambda )
            local ragdoll = lambda.l_TranqGun_Ragdoll
            if IsValid( ragdoll ) then ragdoll:Remove() end
        end

        local function OnLambdaCanTarget( lambda, target )
            if lambda:GetState( "Tranquilized" ) then return true end
            if target.IsLambdaPlayer and target:GetState( "Tranquilized" ) and target.l_TranqGun_State == 3 then return true end
        end

        local function OnLambdaChangeState( lambda, curState )
            if curState == "Tranquilized" and lambda.l_isfrozen then return true end
        end

        local function OnLambdaPreKilled( lambda, dmginfo )
            if !lambda:GetState( "Tranquilized" ) then return end
            lambda.l_isfrozen = false
            lambda.l_TranqGun_State = 0

            local ragdoll = lambda.l_TranqGun_Ragdoll
            if IsValid( ragdoll ) then
                lambda:SetPos( ragdoll:GetPos() )
                lambda.l_BecomeRagdollEntity = ragdoll
                lambda:SimpleTimer( 0, function() if IsValid( ragdoll ) then ragdoll:Remove() end end, true )
                
                local fallDmg = lambda:GetFallDamage( ragdoll:GetVelocity():Length(), true )
                if fallDmg > 0 and lambda.l_PreDeathDamage >= fallDmg and dmginfo:IsDamageType( DMG_CRUSH ) then
                    dmginfo:SetDamageType( dmginfo:GetDamageType() + DMG_FALL )
                end
            end
        end

        local function OnLambdaInjured( lambda, dmginfo )
            if lambda:GetState( "Tranquilized" ) then
                local state = lambda.l_TranqGun_State
                if state == 3 and dmginfo:GetDamageCustom() != 33554432 then return true end
        
                if state == 1 then
                    lambda.l_TranqGun_State = 2
                    lambda.l_TranqGun_PreRagdollDmg = dmginfo
                end
            end
        end

        local function OnLambdaPlaySound( lambda, snd, voiceType )
            if voiceType != "death" and lambda:GetState( "Tranquilized" ) and ( lambda.l_TranqGun_State == 1 or lambda.l_TranqGun_State == 3 ) then return true end
        end

        local function OnLambdaThink( lambda, wepent, isDead )
            if isDead then return end

            if lambda:GetState( "Tranquilized" ) then 
                lambda.l_TranqGun_HitTime = false

                if lambda.l_TranqGun_State == 3 then 
                    local ragdoll = lambda.l_TranqGun_Ragdoll
                    if !IsValid( ragdoll ) then
                        lambda:SetState()
                        lambda:KillSilent()
                        return
                    end

                    lambda:SetPos( ragdoll:GetPos() )
                    lambda.loco:SetVelocity( vector_origin )
                    lambda.l_FallVelocity = 0
                end
            elseif lambda.l_TranqGun_HitTime and CurTime() >= lambda.l_TranqGun_HitTime then
                lambda.l_TranqGun_HitTime = false

                if lambda:GetIsTyping() then 
                    lambda.l_queuedtext = nil
                    lambda.l_typedtext = ""
                end

                lambda:LookTo()
                lambda:ResetAI()
                lambda:CancelMovement()
                lambda:SetState( "Tranquilized" )
            end
        end

        hook.Add( "LambdaOnInitialize", "LambdaTranq_OnLambdaInitialize", OnLambdaInitialize )
        hook.Add( "LambdaCanTarget", "LambdaTranq_OnLambdaCanTarget", OnLambdaCanTarget )
        hook.Add( "LambdaOnChangeState", "LambdaTranq_OnLambdaChangeState", OnLambdaChangeState )
        hook.Add( "LambdaOnPreKilled", "LambdaTranq_OnLambdaPreKilled", OnLambdaPreKilled )
        hook.Add( "LambdaOnPlaySound", "LambdaTranq_OnLambdaPlaySound", OnLambdaPlaySound )
        hook.Add( "LambdaOnInjured", "LambdaTranq_OnLambdaInjured", OnLambdaInjured )
        hook.Add( "LambdaOnThink", "LambdaTranq_OnLambdaThink", OnLambdaThink )
        hook.Add( "LambdaOnRemove", "LambdaTranq_OnLambdaRemoved", OnLambdaRemoved )
    end

    ---

    local function OnEntityRemoved( ent )
        local snoreSnd = ent.l_TranqGun_SnoreSnd
        if snoreSnd then
            snoreSnd:Stop()
            snoreSnd = nil
        end
        
        local ragdoll = ent.l_TranqGun_Ragdoll
        if IsValid( ragdoll ) then 
            snoreSnd = ragdoll.l_TranqGun_SnoreSnd
            if snoreSnd then
                snoreSnd:Stop()
                snoreSnd = nil
            end

            ragdoll:Remove() 
        end
    end

    local function OnEntityEmitSound( data )
        local ent = data.Entity
        
        if IsValid( ent ) then 
            if ent.l_TranqGun_IsTranquilized then return false end

            if ent:IsNPC() and ( IsValidRagdoll( ent:GetModel() ) or IsValidProp( ent:GetModel() ) ) then
                local sndTbl = ent.l_TranqGun_EmitedSounds
                if !sndTbl then
                    ent.l_TranqGun_EmitedSounds = {}
                    sndTbl = ent.l_TranqGun_EmitedSounds
                end
                sndTbl[ #sndTbl + 1 ] = data.SoundName
            end
        end
    end

    local function OnEntityTakeDamage( ent, dmginfo )
        if ent.l_TranqGun_IsTranquilized and dmginfo:GetDamageCustom() != 33554432 then return true end
    end

    local function OnEntityPostTakeDamage( ent, dmginfo, tookDmg )
        if !tookDmg then return end

        local owner = ent:GetNW2Entity( "lambda_tranqgun_owner" )
        if dmginfo:GetAttacker() == owner or dmginfo:GetInflictor() == owner or !IsValid( owner ) or owner.l_TranqGun_IsWakingUp then return end

        if dmginfo:IsDamageType( DMG_CRUSH ) then
            local dmg = ( dmginfo:GetDamage() * 0.5 )
            if dmg < sv_npctranqgun_physdmgthreshold:GetInt() then return end
            dmginfo:SetDamage( dmg )

            if livingBeingMat[ ent:GetMaterialType() ] and dmg > ( owner:GetMaxHealth() * 0.8 ) then
                ent:EmitSound( "Player.FallGib" )
            end
        end

        dmginfo:SetDamageCustom( 33554432 )
        owner:TakeDamageInfo( dmginfo )
    end

    local function OnCreateEntityRagdoll( owner, ragdoll )
        if owner.IsLambdaPlayer then return end

        local tranqRag = owner.l_TranqGun_Ragdoll
        if !IsValid( tranqRag ) then return end

        ragdoll:SetNoDraw( false )
        ragdoll:DrawShadow( true )

        for i = 0, ( ragdoll:GetPhysicsObjectCount() - 1 ) do
            local phys = ragdoll:GetPhysicsObjectNum( i )
            if !IsValid( phys ) then continue end

            local phys2 = tranqRag:GetPhysicsObjectNum( i )
            if !IsValid( phys2 ) then continue end

            phys:SetPos( phys2:GetPos() )
            phys:SetAngles( phys2:GetAngles() )
            phys:SetVelocity( phys2:GetVelocity() )
        end

        OnEntityRemoved( tranqRag )
        tranqRag:Remove()
    end

    local function OnServerThink()
        local wakeTime = sv_npctranqgun_sleeptime:GetFloat()
        for _, ent in ipairs( ents_GetAll() ) do
            if !IsValid( ent ) or !ent.l_TranqGun_IsTranquilized then continue end

            local ragdoll = ent.l_TranqGun_Ragdoll
            if !IsValid( ragdoll ) then
                ent:Remove()
                continue 
            end

            local ragPos = ragdoll:GetPos()
            local wakingTime = ent.l_TranqGun_IsWakingUp
            if !wakingTime then
                ent:SetPos( ragPos )
                if ent.l_TranqGun_IsProp then ent:SetAngles( ragdoll:GetAngles() ) end

                local enemy = ent:GetEnemy()
                if IsValid( enemy ) then
                    ent:SetEnemy( NULL )
                    ent:ClearEnemyMemory( enemy )
                end

                if ent.invdelay then ent.invdelay = ( CurTime() + 1 ) end
            end
            if ( CurTime() - ragdoll.l_TranqGun_DropTime ) < wakeTime then continue end

            local wakeUp = false
            if !wakingTime then
                traceTbl.start = ( ragPos + vector_up * 6 )
                traceTbl.endpos = ( ragPos - vector_up * 32 )
                traceTbl.filter[ 1 ] = ragdoll
                traceTbl.filter[ 2 ] = lambda

                wakeUp = true
                local groundTr = TraceLine( traceTbl )
                if groundTr.Hit then
                    ent:SetPos( groundTr.HitPos )
                    ent:SetCollisionGroup( ent.l_TranqGun_LastCollisionGroup )
                    ent:RemoveFlags( FL_NOTARGET )

                    local phys = ent:GetPhysicsObject()
                    if IsValid( phys ) then phys:EnableCollisions( true ) end
        
                    local snoreSnd = ragdoll.l_TranqGun_SnoreSnd
                    if snoreSnd then
                        snoreSnd:Stop()
                        snoreSnd = nil
                    end

                    ent.l_TranqGun_PreWakePhysData = {}
                    for i = 0, ( ragdoll:GetPhysicsObjectCount() - 1 ) do
                        local phys = ragdoll:GetPhysicsObjectNum( i )
                        if !IsValid( phys ) then continue end

                        local physBone = ragdoll:TranslatePhysBoneToBone( i )
                        if !physBone then continue end

                        wakeUp = false
                        phys:EnableCollisions( false  )
                        ent.l_TranqGun_IsWakingUp = ( CurTime() + 0.75 )

                        ent.l_TranqGun_PreWakePhysData[ #ent.l_TranqGun_PreWakePhysData + 1 ] = { 
                            phys, 
                            physBone,
                            phys:GetPos(), 
                            phys:GetAngles() 
                        }
                    end
                end
            elseif !ent.l_TranqGun_IsProp and CurTime() < wakingTime then
                local lerpVal = ( 1 - ( wakingTime - CurTime() ) / 0.75 )

                for _, data in ipairs( ent.l_TranqGun_PreWakePhysData ) do
                    local phys = data[ 1 ]
                    local pos, ang = ent:GetBonePosition( data[ 2 ] )

                    phys:SetPos( LerpVector( lerpVal, data[ 3 ], pos ) )
                    phys:SetAngles( LerpAngle( lerpVal, data[ 4 ], ang ) )
                end
            else
                wakeUp = true 
            end

            if wakeUp then
                ent:RemoveEFlags( EFL_NO_THINK_FUNCTION )
                ent:SetNoDraw( false )
                ent:DrawShadow( true )

                local weapon = ent:GetActiveWeapon()
                local droppedWep = ent.l_TranqGun_DroppedWep
                if IsValid( weapon ) then 
                    weapon:SetNoDraw( false )
                    weapon:DrawShadow( true )
                elseif IsValid( droppedWep ) and !IsValid( droppedWep:GetOwner() ) and droppedWep:GetPos():DistToSqr( ragPos ) <= 16384 then
                    ent:PickupWeapon( droppedWep )
                end

                local hiddenChildren = ent.l_TranqGun_HiddenChildren
                for _, child in ipairs( hiddenChildren ) do
                    if !IsValid( child ) then continue end
                    child:SetRenderMode( RENDERMODE_NORMAL )
                    child:DrawShadow( true )
                end

                ent.l_TranqGun_IsWakingUp = false
                ent.l_TranqGun_IsTranquilized = false 
                ent.BecomeActiveRagdoll = ent.l_TranqGun_ZippyRagFunc
                ent.FRMignore = false

                if ragdoll:IsOnFire() then
                    ent:Ignite( GetBurnEndTime( ragdoll ) )
                end
                
                if ent.stealth_MEnemies then
                    net.Start( "AddNPCtoTable" )
                        net.WriteEntity( ent )
                    net.Broadcast()
                end

                ragdoll:Remove()
            end
        end
    end

    hook.Add( "Think", "LambdaTranq_OnServerThink", OnServerThink )
    hook.Add( "CreateEntityRagdoll", "LambdaTranq_OnCreateEntityRagdoll", OnCreateEntityRagdoll )
    hook.Add( "EntityTakeDamage", "LambdaTranq_", OnEntityTakeDamage )
    hook.Add( "PostEntityTakeDamage", "LambdaTranq_OnEntityPostTakeDamage", OnEntityPostTakeDamage )
    hook.Add( "EntityRemoved", "LambdaTranq_OnEntityRemoved", OnEntityRemoved )
    hook.Add( "EntityEmitSound", "LambdaTranq_OnEntityEmitSound", OnEntityEmitSound )
else
    local DrawText = draw.DrawText
    local LocalPlayer = LocalPlayer
    local EyePos = EyePos
    local EyeVector = EyeVector
    local EyeAngles = EyeAngles
    local tostring = tostring
    local ScrW = ScrW
    local ScrH = ScrH
    local pairs = pairs
    local FindByClass = ents.FindByClass

    local uiscale = GetConVar( "lambdaplayers_uiscale" )
    local displayArmor = GetConVar( "lambdaplayers_displayarmor" )
    local sleepMat = Material( "lambdaplayers/icon/sleepytime" )

    traceTbl.mask = MASK_SHOT

    local function RagdollNameDisplay()
        traceTbl.start = EyePos()
        traceTbl.endpos = ( traceTbl.start + EyeVector() * 32756 )
        traceTbl.filter = LocalPlayer()

        local traceent = TraceLine( traceTbl ).Entity
        if !IsValid( traceent ) then return end

        local sleepingLambda = traceent:GetNW2Entity( "lambda_tranqgun_owner" )
        if !LambdaIsValid( sleepingLambda ) or !sleepingLambda.IsLambdaPlayer or LET and LET.Lambda == sleepingLambda then return end

        local result = LambdaRunHook( "LambdaShowNameDisplay", sleepingLambda )
        if result == false then return end

        local sw, sh = ScrW(), ScrH()
        local name = sleepingLambda:GetLambdaName()
        local color = sleepingLambda:GetDisplayColor()
        local hp = sleepingLambda:GetNW2Float( "lambda_health", "NAN" )
        local hpW = 2
        local armor = sleepingLambda:GetArmor()
        hp = hp == "NAN" and sleepingLambda:GetNWFloat( "lambda_health", "NAN" ) or hp

        if armor > 0 and displayArmor:GetBool() then
            hpW = 2.1
            DrawText( tostring( armor ) .. "%", "lambdaplayers_healthfont", ( sw / 1.9 ), ( sh / 1.87 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), color, TEXT_ALIGN_CENTER)
        end

        DrawText( name, "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.95 ) , color, TEXT_ALIGN_CENTER )
        DrawText( tostring( hp ) .. "%", "lambdaplayers_healthfont", ( sw / hpW ), ( sh / 1.87 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), color, TEXT_ALIGN_CENTER)
    end

    local sleepIcons = {}

    local function DrawZZZs()
        for _, ragdoll in ipairs( ents_GetAll() ) do
            if !IsValid( ragdoll ) then continue end

            local owner = ragdoll:GetNW2Entity( "lambda_tranqgun_owner" )
            if !IsValid( owner ) then continue end

            local drawPos = GetHeadPosition( ragdoll )
            local iconData = sleepIcons[ owner ]
            if !iconData then
                local plyClr = ( owner.GetPlayerColor and owner:GetPlayerColor():ToColor() or Color( 255, 255, 255 ) )
                plyClr.a = 0

                sleepIcons[ owner ] = {
                    Pos = drawPos,
                    Color = plyClr,
                    Ragdoll = ragdoll
                }
            else
                iconData.Pos = drawPos
            end
        end

        local drawAng = EyeAngles()
        drawAng:RotateAroundAxis( drawAng:Up(), -90 )
        drawAng:RotateAroundAxis( drawAng:Forward(), 90 )

        for owner, iconData in pairs( sleepIcons ) do
            local drawClr = iconData.Color
            local drawPos = iconData.Pos
            local ragdoll = iconData.Ragdoll

            if !IsValid( owner ) or !IsValid( ragdoll ) then
                if IsValid( owner ) then
                    local target = owner
                    if owner.IsLambdaPlayer and owner:GetIsDead() then
                        target = owner.ragdoll
                        if !IsValid( ragdoll ) then
                            target = owner:GetNW2Entity( "lambda_serversideragdoll" )
                            if !IsValid( target ) then target = owner end
                        end
                    end
                    drawPos = GetHeadPosition( target )
                end

                drawClr.a = ( drawClr.a - ( RealFrameTime() * 255 / 1.25 ) )
                if drawClr.a <= 0 then sleepIcons[ owner ] = nil continue end 
            else
                drawClr.a = min( drawClr.a + ( RealFrameTime() * 255 / 2 ), 255 )
            end

            cam.Start3D2D( drawPos, drawAng, 1 )
                surface.SetDrawColor( drawClr )
                surface.SetMaterial( sleepMat )
                surface.DrawTexturedRect( -30, -17.5, 30, 17.5 )
            cam.End3D2D()
        end
    end

    if LambdaIsForked then hook.Add( "HUDPaint", "LambdaTranq_RagdollNameDisplay", RagdollNameDisplay ) end
    hook.Add( "PreDrawEffects", "LambdaTranq_DrawZZZs", DrawZZZs )

    ---

    local function AddToolMenuTabs()
        spawnmenu.AddToolCategory( "Utilities", "YerSoMashy", "YerSoMashy" )
    end

    local cvarList = {
        [ "sv_npctranqgun_hitdamage" ] = sv_npctranqgun_hitdamage:GetDefault(),
        [ "sv_npctranqgun_sleeptime" ] = sv_npctranqgun_sleeptime:GetDefault(),
        [ "sv_npctranqgun_knockouttime" ] = sv_npctranqgun_knockouttime:GetDefault(),
        [ "sv_npctranqgun_physdmgthreshold" ] = sv_npctranqgun_physdmgthreshold:GetDefault(),
        [ "sv_npctranqgun_dropweapon" ] = sv_npctranqgun_dropweapon:GetDefault(),
    }

    local function PopulateToolMenu()
        spawnmenu.AddToolMenuOption( "Utilities", "YerSoMashy", "TranqGunMenu", "Tranquilizer Gun", "", "", function( panel ) 
            local preset = panel:ToolPresets( "npctranqgun", cvarList )

            panel:NumSlider( "Hit Damage", "sv_npctranqgun_hitdamage", 0, 100, 0 )
            panel:ControlHelp( "How much damage does the tranquilizer's darts deal? Scales depending on how close the hit were from the target's head." )

            panel:NumSlider( "Sleep Time", "sv_npctranqgun_sleeptime", 0, 600, 0 )
            panel:ControlHelp( "For how long the target that are put down can sleep until they finally wake up. Scales depending on how close the hit were from the target's head." )

            panel:NumSlider( "Pass Out Time", "sv_npctranqgun_knockouttime", 0, 60, 1 )
            panel:ControlHelp( "For how long the target that's been shot with dart can stand on foot until passing out. Scales depending on how close the hit were from the target's head." )
        
            panel:NumSlider( "Physical Damage Threshold", "sv_npctranqgun_physdmgthreshold", 0, 1000, 0 )
            panel:ControlHelp( "How big should the physical damage dealt to a ragdoll to be in order for it to count for the entity?" )
        
            panel:CheckBox( "Drop Weapon", "sv_npctranqgun_dropweapon" )
            panel:ControlHelp( "If the NPC should drop their weapon instead of still holding it when knocked out." )
        end )
    end

    hook.Add( "AddToolMenuTabs", "LambdaTranq_AddToolMenuTab", AddToolMenuTabs )
    hook.Add( "PopulateToolMenu", "LambdaTranq_PopulateToolMenu", PopulateToolMenu )
end

local function OnDartTouch( self, ent )
    if !ent or !ent:IsSolid() or ent:GetSolidFlags() == FSOLID_VOLUME_CONTENTS then return end
    
    local owner = self:GetOwner()
    if ent == owner then return end
    if !IsValid( owner ) then owner = nil end

    traceTbl.start = self:GetPos()
    traceTbl.endpos = ( traceTbl.start + ( self:GetVelocity() * FrameTime() ) )
    traceTbl.filter[ 1 ] = self
    traceTbl.filter[ 2 ] = owner
    local touchTr = TraceLine( traceTbl )

    if !touchTr.HitSky then 
        local hitPos = touchTr.HitPos

        local koMaxTime = sv_npctranqgun_knockouttime:GetFloat()
        local koTime = koMaxTime
        local hitGroup = touchTr.HitGroup
        if hitGroup == HITGROUP_HEAD or hitGroup == HITGROUP_CHEST and random( 2 ) == 1 and ent:GetForward():Dot( touchTr.Normal ) < 0.1 then
            koTime = 0
        else
            koTime = min( Remap( hitPos:Distance( GetHeadPosition( ent ) ), 0, 64, 0, koMaxTime ), koMaxTime )
        end

        local dmg = sv_npctranqgun_hitdamage:GetInt()
        if dmg > 0 then
            local dmginfo = DamageInfo()
            dmginfo:SetDamage( dmg - ( dmg * ( koTime / koMaxTime ) ) )
            dmginfo:SetDamageType( DMG_DIRECT + DMG_NEVERGIB )
            dmginfo:SetDamagePosition( hitPos )
            dmginfo:SetDamageForce( touchTr.Normal * dmg * 30 )
            dmginfo:SetAttacker( owner or self )
            dmginfo:SetInflictor( IsValid( self.l_Weapon ) and self.l_Weapon or ( owner or self ) )

            touchTr.HitGroup = 0
            ent:DispatchTraceAttack( dmginfo, touchTr )
        end

        if livingBeingMat[ ent:GetMaterialType() ] then
            self:EmitSound( "lambdaplayers/weapons/tranqgun/tranqgun_hit" .. random( 3 ) .. ".mp3", 65, random( 98, 104 ), 1, CHAN_STATIC )
        end

        local dropTime = ent.l_TranqGun_DropTime
        if dropTime then
            local maxTime = sv_npctranqgun_sleeptime:GetFloat()
            local incTime = min( maxTime - ( maxTime * ( koTime / koMaxTime ) ), ( CurTime() - dropTime ) )
            ent.l_TranqGun_DropTime = ( dropTime + incTime )
        elseif ent:Health() > 0 then
            if ent.IsLambdaPlayer and ent:Alive() and LambdaIsForked then 
                if !ent:GetState( "Tranquilized" ) then
                    local hitTime = ent.l_TranqGun_HitTime
                    if !hitTime then
                        if ent:GetEnemy() == owner and random( 100 ) <= ent:GetVoiceChance() then
                            ent:PlaySoundFile( "panic" )
                        end

                        ent.l_TranqGun_HitTime = ( CurTime() + koTime )
                    else
                        ent.l_TranqGun_HitTime = ( ent.l_TranqGun_HitTime - koTime )
                    end
                elseif ent.l_TranqGun_State == 4 then
                    ent.l_TranqGun_State = 5
                end
            elseif !ent:IsNextBot() and ent:IsNPC() and ( IsValidRagdoll( ent:GetModel() ) or IsValidProp( ent:GetModel() ) ) then
                local createID = ent:GetCreationID()
                local koTimer = "LambdaTranq_NPCKnockOutTimer_" .. createID

                if !TimerExists( koTimer ) then
                    local function BecomeADoll( ent, ragCopyTarg )
                        local preStopVel = ( ent:GetVelocity() + ent:GetMoveVelocity() )

                        ent:SentenceStop()
                        ent:StopMoving()

                        ent:SetNoDraw( true )
                        ent:DrawShadow( false )
                        ent:AddEFlags( EFL_NO_THINK_FUNCTION )
                        ent:AddFlags( FL_NOTARGET )

                        local soundTbl = ent.l_TranqGun_EmitedSounds
                        if soundTbl then
                            for _, snd in ipairs( soundTbl ) do
                                ent:StopSound( snd )
                            end
                            table.Empty( soundTbl )
                        end

                        local preCollGroup = ent:GetCollisionGroup()
                        ent:SetCollisionGroup( COLLISION_GROUP_IN_VEHICLE )
                        ent.l_TranqGun_LastCollisionGroup = preCollGroup

                        for _, v in ipairs( ents_GetAll() ) do
                            if !v.GetEnemy or v:GetEnemy() != ent then continue end
                            v:SetEnemy( NULL )

                            if v.IsLambdaPlayer and v:GetState( "Combat" ) then
                                v:SetState()
                                v:CancelMovement()
                            end
                        end

                        local phys = ent:GetPhysicsObject()
                        if IsValid( phys ) then phys:EnableCollisions( false ) end

                        local isRagdoll = IsValidRagdoll( ent:GetModel() )
                        local ragdoll = ents_Create( isRagdoll and "prop_ragdoll" or "prop_physics" )

                        ragdoll:SetModel( ent:GetModel() )
                        ragdoll:SetPos( ent:GetPos() )
                        if !isRagdoll then ragdoll:SetAngles( ent:GetAngles() ) end
                        ragdoll:SetOwner( ent )

                        if isRagdoll then
                            ragdoll:AddEffects( EF_BONEMERGE )
                            ragdoll:SetParent( ragCopyTarg or ent ) 
                        end

                        ragdoll:Spawn()
                        ragdoll:SetCollisionGroup( isRagdoll and COLLISION_GROUP_WEAPON or ent.l_TranqGun_LastCollisionGroup )

                        ragdoll:SetSkin( ent:GetSkin() )
                        for _, v in ipairs( ent:GetBodyGroups() ) do 
                            ragdoll:SetBodygroup( v.id, ent:GetBodygroup( v.id ) )
                        end

                        if isRagdoll then
                            ragdoll:SetParent()
                            ragdoll:RemoveEffects( EF_BONEMERGE )
                        end

                        for i = 0, ( ragdoll:GetPhysicsObjectCount() - 1 ) do
                            local phys = ragdoll:GetPhysicsObjectNum( i )
                            if IsValid( phys ) then phys:AddVelocity( ent:GetVelocity() + ent:GetMoveVelocity() ) end
                        end

                        ragdoll.l_TranqGun_DropTime = CurTime()
                        ragdoll:SetNW2Entity( "lambda_tranqgun_owner", ent )

                        local blinkFlex = ragdoll:GetFlexIDByName( "blink" )
                        if blinkFlex then ragdoll:SetFlexWeight( blinkFlex, 1 ) end

                        local rndPitch = random( 95, 110 )
                        ragdoll:EmitSound( "lambdaplayers/weapons/tranqgun/vo_presleep" .. random( 7 ) .. ".mp3", 70, rndPitch, 1, CHAN_VOICE )
                        
                        local snoreSnd
                        SimpleTimer( 1, function()
                            if !IsValid( ragdoll ) then return end

                            snoreSnd = CreateSound( ragdoll, "lambdaplayers/weapons/tranqgun/vo_snoring" .. random( 3 ) .. ".wav" )
                            if !snoreSnd then return end 

                            snoreSnd:PlayEx( 1, rndPitch ) 
                            snoreSnd:SetSoundLevel( 65 )
                            ragdoll.l_TranqGun_SnoreSnd = snoreSnd
                        end )

                        if ent:IsOnFire() then
                            ragdoll:Ignite( GetBurnEndTime( ent ) )
                            ent:Extinguish()
                        end

                        local dropWpn = sv_npctranqgun_dropweapon:GetBool()
                        local weapon = ent:GetActiveWeapon()
                        local hiddenChildren = {}
                        for _, child in ipairs( ent:GetChildren() ) do
                            if !IsValid( child ) or child:GetNoDraw() then continue end

                            local mdl = child:GetModel()
                            if !mdl or !IsValidModel( mdl ) then continue end

                            if child != weapon then
                                child:SetRenderMode( RENDERMODE_NONE )
                                child:DrawShadow( false )
                            elseif dropWpn then
                                continue
                            end

                            local fakeChild = ents_Create( "base_gmodentity" )
                            fakeChild:SetModel( mdl )
                            fakeChild:SetPos( ragdoll:GetPos() )
                            fakeChild:SetAngles( ragdoll:GetAngles() )
                            fakeChild:Spawn()
                            fakeChild:SetParent( ragdoll )
                            fakeChild:AddEffects( EF_BONEMERGE )
                            ragdoll:DeleteOnRemove( fakeChild )

                            hiddenChildren[ #hiddenChildren + 1 ] = child
                        end

                        if IsValid( weapon ) then
                            if !dropWpn then
                                weapon:SetNoDraw( true )
                                weapon:DrawShadow( false )
                            else
                                ent.l_TranqGun_DroppedWep = weapon
                                ent:DropWeapon( weapon, nil, ragdoll:GetVelocity() )    
                            end
                        end

                        ent.l_TranqGun_ZippyRagFunc = ent.BecomeActiveRagdoll
                        ent.BecomeActiveRagdoll = nil
                        
                        if RDReagdollMaster then 
                            SimpleTimer( 0.1, function() RDReagdollMaster.Kill( ragdoll, true ) end )
                        end

                        ent.l_TranqGun_Ragdoll = ragdoll
                        ent.l_TranqGun_IsProp = !isRagdoll
                        ent.l_TranqGun_IsTranquilized = true
                        ent.l_TranqGun_HiddenChildren = hiddenChildren

                        return ragdoll
                    end

                    if NPCVC and random( 100 ) <= ent.NPCVC_SpeechChance then
                        NPCVC:PlayVoiceLine( ent, "panic" )
                    end

                    CreateTimer( koTimer, koTime, 1, function()
                        if !IsValid( ent ) or ent:Health() <= 0 or ent:GetInternalVariable( "m_lifeState" ) != 0 then return end

                        local zippyRag = ent.ActiveRagdoll
                        if IsValid( zippyRag ) then
                            zippyRag:DontDeleteOnRemove( ent )
                            ent:StopActiveRagdoll()
                            hook_Remove( "Think", "RagAnimateTo" .. ent:EntIndex() )

                            SimpleTimer( 0.81, function()
                                if !IsValid( ent ) then return end
                                BecomeADoll( ent, ( IsValid( zippyRag ) and zippyRag ) )
                                if IsValid( zippyRag ) then zippyRag:Remove() end
                            end )

                            return
                        end
                        local corpse = BecomeADoll( ent )

                        local stealthPlys = ent.stealth_MEnemies
                        if stealthPlys then
                            for k, ply in pairs( stealthPlys ) do
                                if !IsValid( ply ) then continue end
                                table.remove( stealthPlys, k )
                                ent:SetTarget( ent )

                                net.Start( "NPCCalmed" )
                                    net.WriteEntity( ent )
                                net.Send( ply )
                            end
                            if table.IsEmpty( stealthPlys ) then ent:SetNWBool( "stealth_alerted", false ) end

                            if CorpseCreate then CorpseCreate( ent, corpse ) end
                            net.Start( "RemoveNPCfromTable" )
                                net.WriteEntity( ent )
                            net.Broadcast()
                        end
                        ent.FRMignore = true

                        if NPCVC then NPCVC:StopCurrentSpeech( ent ) end
                    end )
                else
                    AdjustTimer( koTimer, max( TimerTimeLeft( koTimer ) - koTime, 0 ) )
                end
            end
        end

        if IsFirstTimePredicted() then
            local effectData = EffectData()
            effectData:SetOrigin( hitPos )
            effectData:SetStart( touchTr.StartPos )
            effectData:SetSurfaceProp( touchTr.SurfaceProps )
            effectData:SetHitBox( touchTr.HitBox )
            effectData:SetEntity( touchTr.Entity )
            effectData:SetDamageType( DMG_DIRECT + DMG_NEVERGIB )
            util_Effect( "Impact", effectData )
        end
    end

    local trail = self.l_trail
    if IsValid( trail ) then
        trail:SetParent()
        SafeRemoveEntityDelayed( trail, 0.66 )
    end

    self:Remove()
end

local function OnDartThink( self )
    self:SetAngles( self:GetVelocity():Angle() )
    self:NextThink( CurTime() ); return true
end

function M9TranqGun_FireDart( pos, fwd, owner, weapon )
    local dart = ents_Create( "base_gmodentity" )
    dart:SetModel( "models/weapons/rifleshell.mdl" )
    dart:SetPos( pos )
    dart:SetAngles( fwd:Angle() )
    dart:SetOwner( owner )
    dart:Spawn()

    dart:SetSolid( SOLID_BBOX )
    dart:SetMoveType( MOVETYPE_FLYGRAVITY )
    dart:SetMoveCollide( MOVECOLLIDE_FLY_CUSTOM )
    dart:SetGravity( 0.33 )
    dart:SetLocalVelocity( fwd * 1500 )

    dart:ManipulateBoneScale( 0, dartScale )
    dart:SetMaterial( "models/shiny" )
    dart.l_trail = SpriteTrail( dart, 0, trailClr, true, 1, 0, 0.3, 0.5, "effects/beam_generic01" )

    if weapon then
        dart.l_Weapon = weapon
    elseif LambdaIsForked then
        dart.IsLambdaWeapon = true
        dart.l_killiconname = "weapon_m9tranqgun"
    end

    dart.Think = OnDartThink
    dart.Touch = OnDartTouch
end