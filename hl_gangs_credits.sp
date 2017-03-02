/*  [CS:GO] Gangs Credits
 *
 *  Copyright (C) 2016 Michael Flaherty // michaelwflaherty.com // michaelwflaherty@me.com
 * 
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option) 
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT 
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with 
 * this program. If not, see http://www.gnu.org/licenses/.
 */
 
#include <sourcemod>
#include <autoexecconfig>

#define REQUIRE_PLUGIN
#include <hl_gangs>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"

/* ConVars */
ConVar gcv_iCreditAmmount;
ConVar gcv_iIntervalAmmount;

/* Client Vars */
int ga_iCredits[MAXPLAYERS + 1] = {0, ...};
bool ga_bLoaded[MAXPLAYERS + 1] = {false, ...};
char ga_sSteamID[MAXPLAYERS + 1][32];

/* Database Globals */
Database g_hDatabase = null;
char g_sDatabaseName[60];

/* Plugin Load Status */
bool g_bLateLoad = false;

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int err_max)
{
	RegPluginLibrary("hl_gangs_credits_library");

	CreateNative("Gangs_GetCredits", Native_GetCredits);
	CreateNative("Gangs_SetCredits", Native_SetCredits);
	
	g_bLateLoad = bLate;
	return APLRes_Success;
}

public int Native_GetCredits(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!IsValidClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%i)", client);
	}

	return ga_iCredits[client];
}

public int Native_SetCredits(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int credits = GetNativeCell(2);

	if (!IsValidClient(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%i)", client);
	}
	ga_iCredits[client] = credits;
	
	return 0;
}


 public Plugin myinfo =
{
	name = "[ANY] Blank Credits System",
	author = "Headline",
	description = "A generic unfeatured credit system",
	version = PLUGIN_VERSION,
	url = "http://michaelwflaherty.com"
};


public void OnPluginStart()
{
	AutoExecConfig_SetFile("hl_gangs_credits");
	
	AutoExecConfig_CreateConVar("hl_gangs_credits_version", PLUGIN_VERSION, "Headline's Gangs Plugin : Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	gcv_iCreditAmmount = AutoExecConfig_CreateConVar("hl_gangs_credits_ammount", "1", "Credit ammount per interval", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	gcv_iIntervalAmmount = AutoExecConfig_CreateConVar("hl_gangs_credits_interval", "2", "Interval between credit delieveries (minutes)", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();


	SetDB();
	
	RegAdminCmd("sm_givecredits", Command_GiveCredits, ADMFLAG_ROOT, "Gives a player credits!");
	RegAdminCmd("sm_givecred", Command_GiveCredits, ADMFLAG_ROOT, "Gives a player credits!");
	RegConsoleCmd("sm_credits", Command_Credits, "View your credits!");
}

public Action Command_Credits(int client, int args)
{
	if (args != 0)
	{
		ReplyToCommand(client, "[SM] Usage: sm_credits");
		return Plugin_Handled;
	}

	if (!IsValidClient(client))
	{
		Gangs_Message(client, "You must be ingame to use this command!");
		return Plugin_Handled;
	}
	
	Gangs_Message(client, "You have %i credits!", ga_iCredits[client]);
	return Plugin_Handled;
}
public Action Command_GiveCredits(int client, int args)
{
	if (args != 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_givecredits <target> <ammount>");
		return Plugin_Handled;
	}
	
	char sArg1[MAX_NAME_LENGTH];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	int target = FindTarget(client, sArg1, true);

	char sArg2[32];
	GetCmdArg(2, sArg2, sizeof(sArg2));
	int credits = StringToInt(sArg2);
	
	Gangs_Message(client, "%i credits given to %N", credits, target);
	ga_iCredits[target] += credits;
	
	return Plugin_Handled;
}

public void OnClientPostAdminCheck(int client)
{
	LoadSQL(client);
}

public void OnClientConnected(int client)
{
	ResetVariables(client);
}

public void OnClientDisconnect(int client)
{
	UpdateSQL(client);
	
	ResetVariables(client);
}

public void OnConfigsExecuted()
{
	if (g_hDatabase == null)
	{
		SetDB();
	}
	if (g_bLateLoad)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i))
			{
				GetClientAuthId(i, AuthId_Steam2, ga_sSteamID[i], sizeof(ga_sSteamID[]));

				if (StrContains(ga_sSteamID[i], "STEAM_", true) != -1)
				{
					LoadSQL(i);
				}
				else
				{
					CreateTimer(10.0, RefreshSteamID, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
				}
			}
		}
	}
}

public void OnMapStart()
{
	CreateTimer((gcv_iIntervalAmmount.IntValue * 60.0), Timer_GiveCredits, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_GiveCredits(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && ga_bLoaded[i])
		{
			ga_iCredits[i] += gcv_iCreditAmmount.IntValue;
			Gangs_Message(i, "You have gained %i credits! You now have %i", gcv_iCreditAmmount.IntValue, ga_iCredits[i]);
		}
	}
}

void LoadSQL(int client)
{
	if (!IsValidClient(client))
	{
		return;
	}
	GetClientAuthId(client, AuthId_Steam2, ga_sSteamID[client], sizeof(ga_sSteamID[]));

	if (StrContains(ga_sSteamID[client], "STEAM_", true) == -1) //if ID is invalid
	{
		CreateTimer(10.0, RefreshSteamID, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	
	if (g_hDatabase == null) //connect not loaded - retry to give it time
	{
		CreateTimer(1.0, RepeatCheckRank, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		char sQuery[300];
		Format(sQuery, sizeof(sQuery), "SELECT credits FROM hl_gangs_credits WHERE steamid=\"%s\"", ga_sSteamID[client]);
		g_hDatabase.Query(SQLCallback_CheckPlayer, sQuery, GetClientUserId(client));
	}
}

void UpdateSQL(int client)
{
	if (ga_bLoaded[client] && !StrEqual(ga_sSteamID[client], "", false))
	{
		char sQuery[300];
		Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_credits SET credits=%i WHERE steamid=\"%s\"", ga_iCredits[client], ga_sSteamID[client]);

		g_hDatabase.Query(SQLCallback_Void, sQuery, GetClientUserId(client));
	}
}

void ResetVariables(int client)
{
	ga_iCredits[client] = 0;
	ga_sSteamID[client] = "";
	ga_bLoaded[client] = false;
}

void SetDB()
{
	ConVar convar;
	if (g_hDatabase == null)
	{
		convar = FindConVar("hl_gangs_database_name");
		convar.GetString(g_sDatabaseName, sizeof(g_sDatabaseName));
		delete convar;
		
		Database.Connect(SQLCallback_Connect, g_sDatabaseName);
	}
}



/***********************************************************
*********************** SQL CALLBACKS **********************
************************************************************/


/* SQL Callback On First Connection */
public void SQLCallback_Connect(Database db, const char[] error, any data)
{
	if (db == null)
	{
		SetDB();
	}
	else
	{
		g_hDatabase = db;		

		g_hDatabase.Query(SQLCallback_Void, "CREATE TABLE IF NOT EXISTS `hl_gangs_credits` (`id` int(20) NOT NULL AUTO_INCREMENT, `steamid` varchar(32) NOT NULL, `credits` int(16) NOT NULL, PRIMARY KEY (`id`)) DEFAULT CHARSET=utf8 AUTO_INCREMENT=1", 1);
	}
}

public void SQLCallback_CheckPlayer(Database db, DBResultSet results, const char[] error, int data)
{
	if (db == null)
	{
		SetDB();
	}

	int client = GetClientOfUserId(data);

	if (!IsValidClient(client))
	{
		return;
	}

	if (results.RowCount == 0)
	{
		char sQuery[300];
		Format(sQuery, sizeof(sQuery), "INSERT INTO hl_gangs_credits (credits, steamid) VALUES(0, \"%s\")", ga_sSteamID[client]);
		g_hDatabase.Query(SQLCallback_Void, sQuery, GetClientUserId(client));
	}
	else
	{
		results.FetchRow();
		ga_iCredits[client] = results.FetchInt(0);
	}
	ga_bLoaded[client] = true;
}


public void SQLCallback_Void(Database db, DBResultSet results, const char[] error, int data)
{
	if (db == null)
	{
		LogError("Error (%i): %s", data, error);
	}
}

/***********************************************************
************************ SQL TIMERS ************************
************************************************************/

public Action RepeatCheckRank(Handle timer, int iUserID)
{
	int client = GetClientOfUserId(iUserID);
	LoadSQL(client);
}

public Action RefreshSteamID(Handle hTimer, int iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if (!IsValidClient(client))
	{
		return;
	}

	GetClientAuthId(client, AuthId_Steam2, ga_sSteamID[client], sizeof(ga_sSteamID[]));
	
	if (StrContains(ga_sSteamID[client], "STEAM_", true) == -1) //still invalid - retry again
	{

		CreateTimer(10.0, RefreshSteamID, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		LoadSQL(client);
	}
}


/***********************************************************
********************* HELPER FUNCTIONS *********************
************************************************************/


bool IsValidClient(int client, bool bAllowBots = false, bool bAllowDead = true)
{
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client) || (IsFakeClient(client) && !bAllowBots) || IsClientSourceTV(client) || IsClientReplay(client) || (!bAllowDead && !IsPlayerAlive(client)))
	{
		return false;
	}
	return true;
}