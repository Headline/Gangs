#include <sourcemod>
#include <cstrike>

#define REQUIRE_PLUGIN
#include <hl_gangs>

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "1.1"

public Plugin myinfo =
{
	name = "[CS:GO/CS:S] Jailbreak Gangs Clan Tags",
	author = "Headline",
	description = "Gangs clan tag extension",
	version = PLUGIN_VERSION,
	url = "http://michaelwflaherty.com"
};

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	for (int i = 0; i < MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			SetClientClanTag(i);
		}
	}
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	SetClientClanTag(client);

	return Plugin_Continue;
}

void SetClientClanTag(int client)
{
	if (Gangs_HasGang(client))
	{
		char gangName[256];
		Gangs_GetGangName(client, gangName, sizeof(gangName));
		CS_SetClientClanTag(client, gangName);
	}
	else
	{
		CS_SetClientClanTag(client, "");
	}
}

bool IsValidClient(int client, bool bAllowBots = false, bool bAllowDead = true)
{
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client) || (IsFakeClient(client) && !bAllowBots) || IsClientSourceTV(client) || IsClientReplay(client) || (!bAllowDead && !IsPlayerAlive(client)))
	{
		return false;
	}
	return true;
}