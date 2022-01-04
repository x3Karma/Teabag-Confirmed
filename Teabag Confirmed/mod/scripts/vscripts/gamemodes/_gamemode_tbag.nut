global function GamemodeTbag_Init

struct {
	table<entity, float> players
	table<entity, entity> trigger
	table<entity, int> tbag
} file


void function GamemodeTbag_Init()
{
	SetShouldUseRoundWinningKillReplay( true )
	Riff_ForceTitanAvailability( eTitanAvailability.Never )
	ClassicMP_ForceDisableEpilogue( true )

	AddCallback_OnClientConnected( TbagInitPlayer )
	AddCallback_OnPlayerKilled( TbagOnPlayerKilled )
	AddCallback_OnClientDisconnected( TbagCleanupClient )
	AddCallback_GameStateEnter( eGameState.WinnerDetermined, OnWinnerDetermined )

	SetTimeoutWinnerDecisionFunc( CheckScoreForDraw )

	AddClientCommandCallback("Tbag_down", Crouching );
}

void function TbagInitPlayer( entity player )
{
	file.players[player] <- Time()
	file.tbag[player] <- 0
}

void function TbagCleanupClient( entity player )
{
	if (player in file.players)
		delete file.players[player]

	if (player in file.trigger)
		delete file.trigger[player]

	if (player in file.tbag)
		delete file.tbag[player]
}

void function TbagOnPlayerKilled( entity victim, entity attacker, var damageInfo )
{
	if ( !victim.IsPlayer() || GetGameState() != eGameState.Playing || attacker == victim)
		return

	if ( attacker.IsPlayer() )
    {
		CreateBattery(victim)
		SetRoundWinningKillReplayAttacker(attacker)
    }
}

void function CreateBattery(entity player)
{
	entity batteryPack = CreateEntity( "prop_dynamic" )
	batteryPack.SetValueForModelKey( RODEO_BATTERY_MODEL )
	batteryPack.kv.fadedist = 10000

	array ignoreArray = []
	TraceResults downTrace = TraceLine( player.EyePosition(), player.GetOrigin() + <0.0, 0.0, -1000.0>, ignoreArray, TRACE_MASK_SHOT, TRACE_COLLISION_GROUP_BLOCK_WEAPONS )

	batteryPack.SetOrigin(downTrace.endPos)
	DispatchSpawn( batteryPack )
	batteryPack.SetModel( RODEO_BATTERY_MODEL )
	Battery_StartFX( batteryPack )
	batteryPack.SetVelocity( < 0, 0, 1 > )

	SetTeam(batteryPack, player.GetTeam())

	thread CreateBatteryTrigger(batteryPack)
	thread DestroyBattery(batteryPack, 45)
}

void function DestroyBattery(entity batteryPack, int duration)
{
	batteryPack.EndSignal( "OnDestroy" )
	OnThreadEnd(
		function () : ( batteryPack )
		{
			if ( IsValid( batteryPack ) )
			{
				ClearChildren( batteryPack )
				batteryPack.Destroy()
			}
		}
	)
	wait duration
}

void function CreateBatteryTrigger(entity batteryPack)
{
	entity trigger = CreateEntity( "trigger_cylinder" )
	trigger.SetRadius( 100 )
	trigger.SetAboveHeight( 100 )
	trigger.SetBelowHeight( 100 ) //i.e. make the trigger a sphere as opposed to a cylinder
	trigger.SetOrigin( batteryPack.GetOrigin() )
	trigger.SetParent( batteryPack )
	trigger.kv.triggerFilterNpc = "none" // none
	DispatchSpawn( trigger )
	SetTeam(trigger, batteryPack.GetTeam())
	trigger.SetEnterCallback( BatteryTrigger_Enter )
	trigger.SetLeaveCallback( BatteryTrigger_Leave )

	thread DestroyBattery(trigger, 45)
}

void function BatteryTrigger_Enter( entity trigger, entity player )
{
	if ( trigger != null )
	{
		if (! (player in file.trigger))
		{
			if (IsValid(player) && player.IsPlayer())
			{
				file.trigger[player] <- trigger
			}
		}
	}
}

void function BatteryTrigger_Leave( entity trigger, entity player )
{
	if ( trigger != null )
	{
		if (player in file.trigger)
		{
			delete file.trigger[player]
		}
	}
}

void function CheckTbag(entity player)
{
/* 		wait 0.2
		AddButtonPressedPlayerInputCallback(player, IN_DUCK, Crouching(player)) */
}

bool function Crouching(entity player, array<string> args)
{
	if (! (player in file.players) )
		return true;

	if (! (player in file.trigger) )
		return true;

	if (Time() - file.players[player] > 3.0)
	{
		file.tbag[player] = 0
		file.players[player] = Time()
	}

	if (Time() - file.players[player] <= 3.0)
	{
		int i = file.tbag[player]
		i++
		file.tbag[player] = i
		file.players[player] = Time()
	}

	if (file.tbag[player] >= 4)
	{
		if (file.trigger[player].GetTeam() != player.GetTeam())
		{
			AddTeamScore( player.GetTeam(), 1)
			entity batteryPack = file.trigger[player].GetParent()
			if ( IsValid( batteryPack ) )
			{
				ClearChildren( batteryPack )
				batteryPack.Destroy()
			}
			if (IsValid (file.trigger[player]))
			{
				entity trigger = file.trigger[player]
				delete file.trigger[player]
				trigger.Destroy()
			}
			Remote_CallFunction_NonReplay( player, "ServerCallback_TeabagConfirmed" )
		} else
		{
			entity batteryPack = file.trigger[player].GetParent()
			if ( IsValid( batteryPack ) )
			{
				ClearChildren( batteryPack )
				batteryPack.Destroy()
			}
			if (IsValid (file.trigger[player]))
			{
				entity trigger = file.trigger[player]
				delete file.trigger[player]
				trigger.Destroy()
			}
			Remote_CallFunction_NonReplay( player, "ServerCallback_TeabagDenied" )
		}
	}
	return true;
}

void function Standing(entity player)
{
	print("standing detected")
	if (! (player in file.players) )
		return;

	if (! (player in file.trigger) )
		return;

	if (file.trigger[player].GetTeam() == player.GetTeam())
	{
		print("Same team as victim, not triggering a teabag counter.")
	}
	else
	{
		if (Time() - file.players[player] > 3.0)
		{
			file.tbag[player] = 0
			print ("Resetted teabag counter.")
			file.players[player] = Time()
		}

		if (Time() - file.players[player] <= 3.0)
		{
			int i = file.tbag[player]
			print("Teabag count for " + player.GetPlayerName() + " is " + i)
			i++
			file.tbag[player] = i
		}
	}
}

void function OnWinnerDetermined()
{
	SetRespawnsEnabled( false )
	SetKillcamsEnabled( false )
}

int function CheckScoreForDraw()
{
	if (GameRules_GetTeamScore(TEAM_IMC) > GameRules_GetTeamScore(TEAM_MILITIA))
		return TEAM_IMC
	else if (GameRules_GetTeamScore(TEAM_MILITIA) > GameRules_GetTeamScore(TEAM_IMC))
		return TEAM_MILITIA

	return TEAM_UNASSIGNED
}