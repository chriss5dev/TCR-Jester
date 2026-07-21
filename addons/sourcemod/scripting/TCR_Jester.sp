#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <treason>

int g_crJester = -1;
int g_JesterClient = 0;
int jColor[3];
treasonAbility jAbilities[3];
treasonGadget jGadgets[2];

bool g_jesterExists = false;
int g_CurrentlyDyingClient = 0;
int g_CurrentlyKillingClient = 0;

ConVar g_cvPrevalence;
ConVar g_cvWeight;
ConVar g_cvMinPlayers;
ConVar g_cvMinTraitors;
ConVar g_cvJesterRound;
 
public Plugin myinfo =
{
	name = "TCR Jester-Traitor",
	author = "chriss5",
	description = "Adds the Jester role using Treason Custom Roles (TCR) from chriss5's Treason API (TAPI).",
	version = "1.0",
	url = "http://www.sourcemod.net/"
};

public void OnPluginStart()
{
	jColor[0] = 255;
	jColor[1] = 255;
	jColor[2] = 255;
	jAbilities[0] = TA_None;
	jAbilities[1] = TA_None;
	jAbilities[2] = TA_None;
	jGadgets[0] = TG_None;
	jGadgets[1] = TG_None;
	
	CreateConVars();
	SetupDownloads();
	HookEvents();
}

public void OnMapStart()
{
	PrecacheSounds();
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

public void OnClientDisconnect(int client)
{
	if(client == g_JesterClient)
	{
		g_jesterExists = false;
	}
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKUnhook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

//setup shortcuts
public void SetupDownloads()
{
	AddFileToDownloadsTable("sound/jester/jesterwins.wav");
	AddFileToDownloadsTable("sound/jester/jesterstart.wav");
	AddFileToDownloadsTable("sound/jester/jesterreveal.wav");
}

public void PrecacheSounds()
{
	PrecacheSound("jester/jesterwins.wav", true);
	PrecacheSound("jester/jesterstart.wav", true);
	PrecacheSound("jester/jesterreveal.wav", true);
}

public void HookEvents()
{
	HookEvent("player_death", E_PlayerDeath, EventHookMode_Post);
}

public void CreateConVars()
{
	g_cvPrevalence = CreateConVar("cr_jester_prevalence", "3");
	g_cvWeight = CreateConVar("cr_jester_weight", "10");
	g_cvMinPlayers = CreateConVar("cr_jester_minplayers", "6");
	g_cvMinTraitors = CreateConVar("cr_jester_mintraitors", "2");
	g_cvJesterRound = CreateConVar("data_jesterround", "0", "Supplies the state of a Jester round to other plugins", FCVAR_SPONLY);
}

public void OnRegisterCustomRoles()
{
	g_crJester = RegisterCustomRole
	(
		// char[] id,
		"jester",
		// char[] displayName,
		"Jester",
		// int underlyingRole,
		TR_Traitor,
		// int underlyingClass,
		TC_None,
		// int prevalence,
		g_cvPrevalence.IntValue,
		// int weight,
		g_cvWeight.IntValue,
		// int minPlayers,
		g_cvMinPlayers.IntValue,
		// int maxPlayers,
		16,
		// int minTraitors,
		g_cvMinTraitors.IntValue,
		// int minInnocents,
		0,
		// bool requireDetective,
		false,
		// bool requireDoctor,
		false,
		// int maxHealthBonus,
		0,
		// bool displayAboveText,
		true,
		// int roleColor[3],
		jColor,
		// int roleTextBrightness,
		255,
		// char[] playerModel,
			"default",
			//"models/player/custom/jester/jester",
		// bool useClassPlayerModels,
		true,
		// char[] poleModel,
		"models/props_cluesystem/custom/jester/pole.mdl",
		// bool discardRoleAbilities,
		false,
		// bool discardRoleGadgets,
		false,
		// bool keepClassAbility,
		false,
		// int abilities[3],
		jAbilities,
		// int gadgets[2]
		jGadgets,
		// bool winIfLastAlive
		false
	);
}

public void OnClearCustomRoles()
{
	//this is no longer accurate, so reset it
	g_crJester = -1;
	g_JesterClient = 0;
	g_jesterExists = false;
	SetConVarInt(g_cvJesterRound, 0, false, false);
}


// jester assigned to player
public void OnClientAssignedCustomRole(int client, int customRoleIndex)
{
	if(customRoleIndex == g_crJester)
	{
		g_JesterClient = client;
		JesterRoundStart();
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if(attacker == g_JesterClient)
	{
		return Plugin_Handled;
	}
	
	// If the hit is going to kill them, store the victim index
    if (damage >= GetClientHealth(victim) && victim != 0 && attacker != 0)
    {
        g_CurrentlyDyingClient = victim;
		g_CurrentlyKillingClient = attacker;
    }
	
	return Plugin_Continue;
}

public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	// If the hit is going to kill them, store the victim index
    if (damage >= GetClientHealth(victim) && (victim == 0 || attacker == 0))
    {
        g_CurrentlyDyingClient = victim;
		g_CurrentlyKillingClient = attacker;
    }
}

public void E_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// if is jesterClient
	if(g_JesterClient > 0 && g_CurrentlyDyingClient == g_JesterClient)
	{
		any attackerRole = GetClientRole(g_CurrentlyKillingClient);
		g_JesterClient = 0;
		g_jesterExists = false;
	
		if(g_CurrentlyDyingClient != g_CurrentlyKillingClient)
		{
			//if attacker is traitor
			if(attackerRole == TR_Traitor)
			{JesterTeamKilled(g_CurrentlyKillingClient);}
			//if attacker is innocent
			else if(attackerRole != TR_Solo && attackerRole != TR_None && attackerRole != TR_Ghost)
			{JesterWinRound();}
		}
	}
}

int TraitorsAlive()
{
	int traitorCount = 0;
	// count the alive innocents, not including solos
	for(int i = 1;i <= MaxClients; i++)
	{
		if(!IsClientInGame(i)) {continue;}
		
		any role = GetClientRole(i);
		if(role == TR_Traitor)
		{
			traitorCount++;
		}
	}
	
	return traitorCount;
}

public void JesterRoundStart()
{
	SetConVarInt(g_cvJesterRound, 1, false, false);
	g_jesterExists = true;
	CreateTimer(1.0, Timer_CheckJesterTK, _, TIMER_REPEAT);
	PrintToChatAll("\x07FF0077There is a Jester-Traitor this round!");
	PrintToChatAll("\x07FF0077Don't get tricked into killing the Jester-Traitor!");
	PrintToChat(g_JesterClient, "\x07FF0000YOU are the Jester-Traitor! Trick someone into killing you as another way to win for your team! You deal no damage.");
	EmitSoundToClient(g_JesterClient, "ttt/jesterreveal.wav", g_JesterClient, SNDCHAN_AUTO, 70, SND_NOFLAGS, 1.0);
	
	//showhudtext for jester client
	SetHudTextParams(ABOVECENTERTEXT_X, ABOVECENTERTEXT_Y, 5.0, 255, 0, 70, 255);
	ShowHudText(g_JesterClient, AUTO_CHANNEL, "YOU are the Jester Traitor!");
	
	//ClientCommandAll sim
	for (int i = 1; i <= MaxClients; i++)
	{	
		if (IsClientInGame(i))
		{
			// jester round start sound
			EmitSoundToClient(i, "ttt/jesterstart.wav", i, SNDCHAN_AUTO, 70, SND_NOFLAGS, 1.0);
			
			if(i != g_JesterClient && GetClientRole(i) == TR_Traitor) //notify traitors of their teammate
			{
				// non-jester traitors only
				PrintToChat(i, "\x07FF0000%N\x07FF5500 is your Jester teammate. Trick innocents into killing them as another way to win!", g_JesterClient);
				SetHudTextParams(ABOVECENTERTEXT_X, ABOVECENTERTEXT_Y, 5.0, 255, 0, 70, 255);
				ShowHudText(i, AUTO_CHANNEL, "%N is your Jester teammate.", g_JesterClient);
			}
			
			if(GetClientRole(i) != TR_Traitor) //notify non-traitors of a jester
			{
				//non-traitors only
				SetHudTextParams(ABOVECENTERTEXT_X, ABOVECENTERTEXT_Y, 5.0, 255, 0, 70, 255);
				ShowHudText(i, AUTO_CHANNEL, "There is a Jester-Traitor this round!");
			}
		}
	}
}

public void JesterWinRound()
{
	g_jesterExists = false;
	PrintToChatAll("\x07FF0000Jester killed! Traitors win!");
	ForceEndRound(TE_TeamWin, 2);
	
	for (int i = 1; i <= MaxClients; i++)
	{	
		if (IsClientInGame(i))
		{
			EmitSoundToClient(i, "ttt/jesterwins.wav", i, SNDCHAN_AUTO, 70, SND_NOFLAGS, 1.0);
			SetHudTextParams(ABOVECENTERTEXT_X, ABOVECENTERTEXT_Y, 5.0, 255, 0, 70, 255);
			ShowHudText(i, AUTO_CHANNEL, "Jester killed! Traitors win!");
		}
	}
}

public void JesterTeamKilled(int attacker)
{
	SetConVarInt(g_cvJesterRound, 0, false, false);
	g_jesterExists = false;
	g_JesterClient = 0;
	PrintToChatAll("\x07FF0077The Jester has been teamkilled by a Traitor!");
	EmitSoundToClient(attacker, "ttt/wrongvictim.wav", attacker, SNDCHAN_AUTO, 70, SND_NOFLAGS, 1.0);
	
	for (int i = 1; i <= MaxClients; i++)
	{	
		if (IsClientInGame(i))
		{
			SetHudTextParams(ABOVECENTERTEXT_X, ABOVECENTERTEXT_Y, 5.0, 255, 0, 70, 255);
			ShowHudText(i, AUTO_CHANNEL, "The Jester has been teamkilled by a Traitor!");
		}
	}
}

public Action Timer_CheckJesterTK(Handle timer)
{
	if(g_jesterExists)
	{
		//check for jester last alive OR only traitor left if jester died
		if(TraitorsAlive() == 1)
		{
			SetConVarInt(g_cvJesterRound, 0, false, false);
			ServerCommand("mp_forcewin 1");
			
			return Plugin_Stop;
		}
		
	}
	else
	{
		return Plugin_Stop;
	}
	return Plugin_Continue; 
}