#include <sourcemod>
#include <autoexecconfig>
#include <cstrike>
#include <sdkhooks>
#include <hl_jailbreakshop>
#include <smlib>
#include <hl_gangs>
#include <togservervalidation>

#define PLUGIN_VERSION "1.0b"
#define TAG " \x03[Gangs]\x01"

/* Plugin-Specific Defines */
#define GANGRANK_OWNER 2
#define GANGRANK_ADMIN 1
#define GANGRANK_NORMAL 0

/* Compiler Instructions */
#pragma semicolon 1
#pragma newdecls required

/* ConVars */
ConVar gcv_bPluginEnabled;
ConVar gcv_bDebug;
ConVar gcv_sDatabase;
ConVar gcv_iMaxGangSize;
ConVar gcv_bInviteStyle;
ConVar gcv_iHealthPrice;
ConVar gcv_iDamagePrice;
ConVar gcv_iGravityPrice;
ConVar gcv_iSpeedPrice;
ConVar gcv_iCreateGangPrice;
ConVar gcv_iRenamePrice;
ConVar gcv_iSizePrice;

/* Gang Globals */
int ga_iRank[MAXPLAYERS + 1] = {-1, ...}; // 0 - Regular | 1 - Admin | 2 - Owner
int ga_iGangSize[MAXPLAYERS + 1] = {-1, ...};
int ga_iInvitation[MAXPLAYERS + 1] = {-1, ...};
int ga_iDateJoined[MAXPLAYERS + 1] = {-1, ...};
int ga_iHealth[MAXPLAYERS + 1] = {0, ...};
int ga_iDamage[MAXPLAYERS + 1] = {0, ...};
int ga_iGravity[MAXPLAYERS + 1] = {0, ...};
int ga_iSpeed[MAXPLAYERS + 1] = {0, ...};
int ga_iSize[MAXPLAYERS + 1] = {0, ...};
int ga_iTimer[MAXPLAYERS + 1] = {0, ...};
int ga_iCTKills[MAXPLAYERS + 1] = {0, ...};
int ga_iTempInt[MAXPLAYERS + 1] = {0, ...};
int ga_iTempInt2[MAXPLAYERS + 1] = {0, ...};
int g_iGangAmmount = 0;

char ga_sGangName[MAXPLAYERS + 1][128];
char ga_sInvitedBy[MAXPLAYERS + 1][128];

bool ga_bSetName[MAXPLAYERS + 1] = {false, ...};
bool ga_bIsPlayerInDatabase[MAXPLAYERS + 1] = {false, ...};
bool ga_bIsGangInDatabase[MAXPLAYERS + 1] = {false, ...};
bool ga_bHasGang[MAXPLAYERS + 1] = {false, ...};
bool ga_bRename[MAXPLAYERS + 1] = {false, ...};
bool g_bLR = false;

float ga_fChangedGravity[MAXPLAYERS + 1] = {0.0, ...};

/* Player Globals */
char ga_sSteamID[MAXPLAYERS + 1][30];
bool g_bLateLoad = false;
bool ga_bLoaded[MAXPLAYERS + 1] = {false, ...};

/* Database Globals */
Handle g_hDatabase = INVALID_HANDLE;
char g_sDatabaseName[60];

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int err_max)
{
	CreateNative("hl_gangs_DamageModifier", Native_GetDmgModifier);
	
	RegPluginLibrary("hl_gangs_library");

	g_bLateLoad = bLate;
	return APLRes_Success;
}


public int Native_GetDmgModifier(Handle hPlugin, int numParams)
{
	int client = GetNativeCell(1);
	
	float fDamage = ga_iDamage[client] * 1.5;
	return view_as<int>(fDamage);
}

public Plugin myinfo =
{
	name = "[CS:GO] Jailbreak Gangs",
	author = "Headline",
	description = "An SQL-based gang plugin",
	version = PLUGIN_VERSION,
	url = "http://michaelwflaherty.com"
};

public void OnPluginStart()
{
	ValidateServer();
	LoadTranslations("core.phrases");
	LoadTranslations("common.phrases");
	
	AutoExecConfig_SetFile("hl_gangs");
	
	AutoExecConfig_CreateConVar("hl_gangs_version", PLUGIN_VERSION, "Headline's Gangs Plugin : Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
		
	gcv_bPluginEnabled = AutoExecConfig_CreateConVar("hl_gangs_enabled", "1", "Enable the plugin? (1 = Yes, 0 = No)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	gcv_bDebug = AutoExecConfig_CreateConVar("hl_gangs_debug", "0", "Enable debug logging? (1 = Yes, 0 = No)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	gcv_bInviteStyle = AutoExecConfig_CreateConVar("hl_gangs_invite_style", "1", "Set invite style to pop up a Menu? \n      (1 = Menu, 0 = Registered Command)", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	gcv_sDatabase = AutoExecConfig_CreateConVar("hl_gangs_database_name", "hl_gangs", "Name of the database for the plugin.");

	gcv_iMaxGangSize = AutoExecConfig_CreateConVar("hl_gangs_max_size", "6", "Max size for a gang");

	gcv_iHealthPrice = AutoExecConfig_CreateConVar("hl_gangs_health_price", "20", "Price of the Health perk");

	gcv_iDamagePrice = AutoExecConfig_CreateConVar("hl_gangs_damage_price", "20", "Price of the Damage perk");

	gcv_iGravityPrice = AutoExecConfig_CreateConVar("hl_gangs_gravity_price", "20", "Price of the Gravity perk");

	gcv_iSpeedPrice = AutoExecConfig_CreateConVar("hl_gangs_speed_price", "20", "Price of the Speed perk");
	
	gcv_iSizePrice = AutoExecConfig_CreateConVar("hl_gangs_size_price", "20", "Price of the Size perk");

	gcv_iCreateGangPrice = AutoExecConfig_CreateConVar("hl_gangs_creation_price", "100", "Price of gang creation");

	gcv_iRenamePrice = AutoExecConfig_CreateConVar("hl_gangs_rename_price", "100", "Price to rename");

	gcv_sDatabase.GetString(g_sDatabaseName, sizeof(g_sDatabaseName));
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	
	RegConsoleCmd("sm_gang", Command_Gang, "Open the gang menu!");
	RegConsoleCmd("sm_gangs", Command_Gang, "Open the gang menu!");

	if (gcv_bInviteStyle.BoolValue)
	{
		RegConsoleCmd("sm_accept", Command_Accept, "Accept an invitation!");
	}

	AddCommandListener(OnSay, "say"); 
	AddCommandListener(OnSay, "say_team");

	if(g_bLateLoad)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnClientConnected(int client)
{
	if (gcv_bPluginEnabled.BoolValue)
	{
		ResetVariables(client);
	}
}

public void OnClientDisconnect(int client)
{
	if (gcv_bPluginEnabled.BoolValue)
	{
		UpdateSQL(client);
		
		ResetVariables(client);
	
		if (gcv_bDebug.BoolValue)
		{
			Log("hl_gangs.log","Client %L disconnecting. Saving to database!", client);
		}
	}
}

public void OnConfigsExecuted()
{
	if (gcv_bPluginEnabled.BoolValue)
	{
		if (g_hDatabase == INVALID_HANDLE)
		{
			SetDBHandle();
		}
		if (g_bLateLoad)
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i))
				{
					#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
						GetClientAuthId(i, AuthId_Steam2, ga_sSteamID[i], sizeof(ga_sSteamID[]));
					#else
						GetClientAuthString(i, ga_sSteamID[i], sizeof(ga_sSteamID[]));
					#endif
					if (StrContains(ga_sSteamID[i], "STEAM_", true) != -1)
					{
						if (gcv_bDebug.BoolValue)
						{
							Log("hl_gangs.log","Loading #s for %L", i);
						}
						LoadSteamID(i);
					}
					else
					{
						if (gcv_bDebug.BoolValue)
						{
							Log("hl_gangs.log","Refreshing steam ID for client %L", i);
						}
						CreateTimer(10.0, RefreshSteamID, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
					}
				}
			}
		}
	}
}

public Action Event_RoundEnd(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	g_bLR = false;
}

public Action Event_RoundStart(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	g_bLR = false;
}

public Action Event_PlayerSpawn(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	if (IsValidClient(client) && GetClientTeam(client) == 2)
	{
		if (ga_bHasGang[client])
		{
			if (ga_iHealth[client] != 0)
			{
				int iHealth = ga_iHealth[client] * 1 + 100;
				SetEntProp(client, Prop_Send, "m_iHealth", iHealth);
			}
			if (ga_iGravity[client] != 0)
			{
				SetEntityGravity(client, GetClientGravityAmmount(client));
				ga_iTimer[client] = 0;
				CreateTimer(0.4, Timer_CheckSetGravity, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
			}
			if (ga_iSpeed[client] != 0)
			{
				SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", GetClientSpeedAmmount(client));
			}
		}
	}
}

public Action Timer_CheckSetGravity(Handle hHandle, int iUserid)
{
	int client = GetClientOfUserId(iUserid);
	if (ga_iTimer[client] == 0)
	{
		if (GetEntityGravity(client) != 1.0 && GetEntityGravity(client) != GetClientGravityAmmount(client))
		{
			ga_fChangedGravity[client] = GetEntityGravity(client);
		}
	}
	else
	{
		if(GetEntityGravity(client) == ga_fChangedGravity[client])
		{
			// Do nothing
		}
		else
		{
			SetEntityGravity(client, GetClientGravityAmmount(client));
			return Plugin_Stop;
		}
	}
	ga_iTimer[client]++;
	return Plugin_Continue;
}


public Action RefreshSteamID(Handle hTimer, int iUserID)
{
	int client = GetClientOfUserId(iUserID);
	if (!IsValidClient(client))
	{
		return;
	}

	#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
		GetClientAuthId(client, AuthId_Steam2, ga_sSteamID[client], sizeof(ga_sSteamID[]));
	#else
		GetClientAuthString(client, ga_sSteamID[client], sizeof(ga_sSteamID[]));
	#endif
	
	if (StrContains(ga_sSteamID[client], "STEAM_", true) == -1) //still invalid - retry again
	{
		if (gcv_bDebug.BoolValue)
		{
			Log("hl_gangs.log","Re-refreshing steam ID for client %L", client);
		}
		CreateTimer(10.0, RefreshSteamID, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		if (gcv_bDebug.BoolValue)
		{
			Log("hl_gangs.log","Loading client %L", client);
		}
		LoadSteamID(client);
	}
}

public void OnClientPutInServer(int client) 
{ 
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage); 

    CreateTimer(2.0, Timer_AlertGang, client, TIMER_FLAG_NO_MAPCHANGE);
} 

public Action Timer_AlertGang(Handle hTimer, int client)
{
	PrintToGang(client, false, "%s \x04Gang member \x03%N\x04 has joined the game!", TAG, client);
}


public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) 
{
	if (!g_bLR && IsValidClient(attacker) && IsValidClient(victim) && ga_bHasGang[attacker] && attacker != victim && GetClientTeam(victim) == CS_TEAM_CT && GetClientTeam(attacker) == CS_TEAM_T)
	{
		char sWeapon[32];
		GetClientWeapon(attacker, sWeapon, sizeof(sWeapon)); 
		if (StrContains(sWeapon, "knife") != -1)
		{
			damage = damage + ga_iDamage[attacker] * 1.5;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
} 

public void OnClientPostAdminCheck(int client)
{
	if (gcv_bPluginEnabled.BoolValue)
	{	
		#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
			GetClientAuthId(client, AuthId_Steam2, ga_sSteamID[client], sizeof(ga_sSteamID[]));
		#else
			GetClientAuthString(client, ga_sSteamID[client], sizeof(ga_sSteamID[]));
		#endif
		LoadSteamID(client);
	}
}

public Action Event_PlayerDeath(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(hEvent, "attacker"));

	if (GetPlayerAliveCount(2) == 1 && GetPlayerAliveCount(3) > 0)
	{
		LastRequest();
	}
	
	if (IsValidClient(attacker) && IsValidClient(client) && client != attacker && ga_bHasGang[attacker])
	{
		if (GetClientTeam(attacker) == CS_TEAM_T && GetClientTeam(client) == CS_TEAM_CT)
		{
			ga_iCTKills[attacker]++;
			char sQuery[300];
			Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_statistics SET ctkills = %i WHERE gang=\"%s\"", ga_iCTKills[attacker], ga_sGangName[attacker]);
			
			for (int i = 0; i <= MaxClients; i++)
			{
				if (IsValidClient(i))
				{
					if (StrEqual(ga_sGangName[i], ga_sGangName[attacker]))
					{
						ga_iCTKills[i]++;
					}
				}
			}
			
			SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery);
		}
	}
}

/* SQL Callback On First Connection */
public void SQLCallback_Connect(Handle hOwner, Handle hHndl, const char[] sError, any data)
{
	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}
	else
	{
		g_hDatabase = hHndl;
		char sDriver[64];
		
		SQL_ReadDriver(g_hDatabase, sDriver, 64);
		

		SQL_TQuery(g_hDatabase, SQLCallback_Void, "CREATE TABLE IF NOT EXISTS `hl_gangs_players` (`id` int(20) NOT NULL AUTO_INCREMENT, `steamid` varchar(32) NOT NULL, `playername` varchar(32) NOT NULL, `gang` varchar(32) NOT NULL, `rank` int(16) NOT NULL, `invitedby` varchar(32) NOT NULL, `date` int(32) NOT NULL, PRIMARY KEY (`id`)) DEFAULT CHARSET=utf8 AUTO_INCREMENT=1", 1);
		SQL_TQuery(g_hDatabase, SQLCallback_Void, "CREATE TABLE IF NOT EXISTS `hl_gangs_groups` (`id` int(20) NOT NULL AUTO_INCREMENT, `gang` varchar(32) NOT NULL, `health` int(16) NOT NULL, `damage` int(16) NOT NULL, `gravity` int(16) NOT NULL, `speed` int(16) NOT NULL, `size` int(16) NOT NULL, PRIMARY KEY (`id`)) DEFAULT CHARSET=utf8 AUTO_INCREMENT=1", 1);
		SQL_TQuery(g_hDatabase, SQLCallback_Void, "CREATE TABLE IF NOT EXISTS `hl_gangs_statistics` (`id` int(20) NOT NULL AUTO_INCREMENT, `gang` varchar(32) NOT NULL, `ctkills` int(16) NOT NULL, PRIMARY KEY (`id`)) DEFAULT CHARSET=utf8 AUTO_INCREMENT=1", 1);

		if (gcv_bDebug.BoolValue)
		{
			Log("hl_gangs.log","Successfully connected to database!");
		}
	}
}

void LoadSteamID(int client)
{
	if (gcv_bPluginEnabled.BoolValue)
	{
		if (!IsValidClient(client))
		{
			return;
		}
		#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 7
			GetClientAuthId(client, AuthId_Steam2, ga_sSteamID[client], sizeof(ga_sSteamID[]));
		#else
			GetClientAuthString(client, ga_sSteamID[client], sizeof(ga_sSteamID[]));
		#endif
		if (StrContains(ga_sSteamID[client], "STEAM_", true) == -1) //if ID is invalid
		{
			CreateTimer(10.0, RefreshSteamID, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			if (gcv_bDebug.BoolValue)
			{
				Log("hl_gangs.log","Refreshing Steam ID for client %L!", client);
			}
		}
		
		if (g_hDatabase == INVALID_HANDLE) //connect not loaded - retry to give it time
		{
			CreateTimer(1.0, RepeatCheckRank, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			if (gcv_bDebug.BoolValue)
			{
				Log("hl_gangs.log","Database connection not established yet! Delaying loading of client %L", client);
			}
		}
		else
		{
			if (gcv_bDebug.BoolValue)
			{
				Log("hl_gangs.log","Sending database query to load client %L", client);
			}
			char sQuery[300];
			Format(sQuery, sizeof(sQuery), "SELECT * FROM hl_gangs_players WHERE steamid=\"%s\"", ga_sSteamID[client]);
			SQL_TQuery(g_hDatabase, SQLCallback_CheckSQL_Player, sQuery, GetClientUserId(client));
		}
	}
}

public void SQLCallback_CheckSQL_Player(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{
	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}
	
	int client = GetClientOfUserId(iUserID);
	if (!IsValidClient(client))
	{
		return;
	}
	else 
	{
		if (SQL_GetRowCount(hHndl) == 1)
		{
			SQL_FetchRow(hHndl);

			SQL_FetchString(hHndl, 3, ga_sGangName[client], sizeof(ga_sGangName[]));
			ga_iRank[client] = SQL_FetchInt(hHndl, 4);
			SQL_FetchString(hHndl, 5, ga_sInvitedBy[client], sizeof(ga_sInvitedBy[]));
			ga_iDateJoined[client] = SQL_FetchInt(hHndl, 6);
			ga_bIsPlayerInDatabase[client] = true;
			ga_bHasGang[client] = true;
			ga_bLoaded[client] = true;

			ga_iHealth[client] = 0;
			ga_iDamage[client] = 0;
			ga_iGravity[client] = 0;
			ga_iSpeed[client] = 0;
			ga_iSize[client] = 0;

			char sQuery_2[300];
			Format(sQuery_2, sizeof(sQuery_2), "SELECT * FROM hl_gangs_groups WHERE gang=\"%s\"", ga_sGangName[client]);
			SQL_TQuery(g_hDatabase, SQLCallback_CheckSQL_Groups, sQuery_2, GetClientUserId(client));
		}
		else
		{
			if (SQL_GetRowCount(hHndl) > 1)
			{
				LogError("Player %L has multiple entries under their ID. Running script to clean up duplicates and keep original entry (oldest)", client);
				DeleteDuplicates();
				CreateTimer(20.0, RepeatCheckRank, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			}
			else if (g_hDatabase == INVALID_HANDLE)
			{
				CreateTimer(2.0, RepeatCheckRank, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			}
			else
			{
				ga_bHasGang[client] = false;
				ga_bLoaded[client] = true;
			}
		}
	}
}

public void SQLCallback_CheckSQL_Groups(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{
	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}
	
	int client = GetClientOfUserId(iUserID);
	if (!IsValidClient(client))
	{
		return;
	}
	else 
	{
		if (SQL_GetRowCount(hHndl) == 1)
		{
			SQL_FetchRow(hHndl);

			ga_iHealth[client] = SQL_FetchInt(hHndl, 2);
			ga_iDamage[client] = SQL_FetchInt(hHndl, 3);
			ga_iGravity[client] = SQL_FetchInt(hHndl, 4);
			ga_iSpeed[client] = SQL_FetchInt(hHndl, 5);
			ga_iSize[client] = SQL_FetchInt(hHndl, 6);

			char sQuery[300];
			Format(sQuery, sizeof(sQuery), "SELECT * FROM hl_gangs_statistics WHERE gang=\"%s\"", ga_sGangName[client]);
			SQL_TQuery(g_hDatabase, SQL_Callback_CTKills, sQuery, GetClientUserId(client));
		}
	}
}

public void SQL_Callback_CTKills(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{
	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}
	
	int client = GetClientOfUserId(iUserID);
	if (!IsValidClient(client))
	{
		return;
	}
	else 
	{
		
		if (SQL_GetRowCount(hHndl) == 1 && SQL_FetchRow(hHndl))
		{
			ga_iCTKills[client] = SQL_FetchInt(hHndl, 2);
			
			if(gcv_bDebug.BoolValue)
			{
				Log("hl_gangs.log","Player %L has been completely loaded from the database", client);
			}
		}

	}
}


public Action RepeatCheckRank(Handle hTimer, int iUserID)
{
	int client = GetClientOfUserId(iUserID);
	LoadSteamID(client);
}

public void SQLCallback_Void(Handle hOwner, Handle hHndl, const char[] sError, int iData)
{
	if (hHndl == INVALID_HANDLE)
	{
		LogError("Error (%i): %s", iData, sError);
	}
}

public Action Command_Accept(int client, int args)
{
	if (!gcv_bPluginEnabled.BoolValue)
	{
		ReplyToCommand(client, "This plugin is disabled!");
		return Plugin_Handled;
	}
	if (gcv_bInviteStyle.BoolValue)
	{
		ReplyToCommand(client, "Accepting via command is disabled!");
		return Plugin_Handled;
	}

	if (!IsValidClient(client))
	{
		ReplyToCommand(client, "[SM] You must be in-game to use this command!");
		return Plugin_Handled;
	}
	if (GetClientTeam(client) != 2)
	{
		ReplyToCommand(client, "[SM] You must be on the terrorist team to use this!");
		return Plugin_Handled;
	}
	if (ga_bHasGang[client])
	{
		ReplyToCommand(client, "%s \x04You are already in a gang!", TAG);
		return Plugin_Handled;
	}
	if (ga_iInvitation[client] == -1)
	{
		ReplyToCommand(client, "%s \x04You must be invited first!", TAG);
		return Plugin_Handled;
	}
	if (ga_iGangSize[GetClientOfUserId(ga_iInvitation[client])] <= gcv_iMaxGangSize.IntValue + ga_iSize[GetClientOfUserId(ga_iInvitation[client])])
	{
		ReplyToCommand(client, "%s \x04That Gang is full!", TAG);
		return Plugin_Handled;
	}

	ga_sGangName[client] = ga_sGangName[GetClientOfUserId(ga_iInvitation[client])];
	ga_iDateJoined[client] = GetTime();
	ga_bHasGang[client] =  true;
	ga_bSetName[client] = false;

	char sName[MAX_NAME_LENGTH];
	GetClientName(GetClientOfUserId(ga_iInvitation[client]), sName, sizeof(sName));
	
	ga_iHealth[client] = ga_iHealth[GetClientOfUserId(ga_iInvitation[client])];
	ga_iDamage[client] = ga_iDamage[GetClientOfUserId(ga_iInvitation[client])];
	ga_iGravity[client] = ga_iGravity[GetClientOfUserId(ga_iInvitation[client])];
	ga_iSpeed[client] = ga_iSpeed[GetClientOfUserId(ga_iInvitation[client])];
	ga_iCTKills[client] = ga_iCTKills[GetClientOfUserId(ga_iInvitation[client])];
	ga_iSize[client] = ga_iSize[GetClientOfUserId(ga_iInvitation[client])];
	
	ga_sInvitedBy[client] = sName;
	ga_iGangSize[client] = 1;
	ga_iRank[client] = GANGRANK_NORMAL;
	UpdateSQL(client);
	return Plugin_Handled;
}

public Action Command_Gang(int client, int args)
{
	if (!IsValidClient(client))
	{
		ReplyToCommand(client, "[SM] You must be in-game to use this command!");
		return Plugin_Handled;
	}
	if (GetClientTeam(client) != 2)
	{
		ReplyToCommand(client, "%s \x04You must be on the terrorist team to use this!", TAG);
		return Plugin_Handled;
	}
	StartOpeningGangMenu(client);
	return Plugin_Handled;
}


/*****************************************************************
*********************** MAIN GANG MENU  **************************
******************************************************************/


void StartOpeningGangMenu(int client)
{
	if (!StrEqual(ga_sGangName[client], ""))
	{
		char sQuery[300];
		Format(sQuery, sizeof(sQuery), "SELECT * FROM hl_gangs_players WHERE gang = \"%s\"", ga_sGangName[client]);
		SQL_TQuery(g_hDatabase, SQLCallback_OpenGangMenu, sQuery, GetClientUserId(client));
	}
	else
	{
		OpenGangsMenu(client);
	}
}

public void SQLCallback_OpenGangMenu(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{

	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}
	
	int client = GetClientOfUserId(iUserID);
	if (!IsValidClient(client))
	{
		return;
	}
	else 
	{
		ga_iGangSize[client] = SQL_GetRowCount(hHndl);
	}
	OpenGangsMenu(client);
}

void OpenGangsMenu(int client)
{
	Handle hMenu = CreateMenu(GangsMenu_Callback, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem);
	if (ga_bHasGang[client])
	{
		char sString[128];
		Format(sString, sizeof(sString), "[CG] Gangs Menu \nCredits: %i \nCurrent Gang: %s %i/%i", GetClientCredits(client), ga_sGangName[client], ga_iGangSize[client], gcv_iMaxGangSize.IntValue + ga_iSize[client]);
		SetMenuTitle(hMenu, sString);
	}
	else
	{
		char sString[128];
		Format(sString, sizeof(sString), "[CG] Gangs Menu \nCredits: %i \nCurrent Gang: N/A \n ", GetClientCredits(client));
		SetMenuTitle(hMenu, sString);
	}
	char sDisplayBuffer[128];
	
	Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Create a Gang! [%i Credits]", gcv_iCreateGangPrice.IntValue);
	AddMenuItem(hMenu, "create", sDisplayBuffer, (ga_bHasGang[client] || GetClientCredits(client) < gcv_iCreateGangPrice.IntValue)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	AddMenuItem(hMenu, "invite", "Invite to Gang", (ga_bHasGang[client] && ga_iRank[client] > GANGRANK_NORMAL && ga_iGangSize[client] < gcv_iMaxGangSize.IntValue + ga_iSize[client])?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	AddMenuItem(hMenu, "members", "Gang Members", (ga_bHasGang[client])?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	AddMenuItem(hMenu, "perks", "Gang Perks", (ga_bHasGang[client])?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	AddMenuItem(hMenu, "admin", "Gang Admin", (ga_iRank[client] >= 1)?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	AddMenuItem(hMenu, "leave", "Leave Gang", (ga_bHasGang[client])?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	AddMenuItem(hMenu, "topgangs", "Top Gangs");

	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);

}

public int GangsMenu_Callback(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[64];
			GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));
			if (StrEqual(sInfo, "create"))
			{
				SetClientCredits(param1, GetClientCredits(param1) - gcv_iCreateGangPrice.IntValue);
				StartGangCreation(param1);
			}
			else if (StrEqual(sInfo, "invite"))
			{
				OpenInvitationMenu(param1);
			}
			else if (StrEqual(sInfo, "members"))
			{
				StartOpeningMembersMenu(param1);
			}
			else if (StrEqual(sInfo, "perks"))
			{
				StartOpeningPerkMenu(param1);
			}
			else if (StrEqual(sInfo, "admin"))
			{
				OpenAdministrationMenu(param1);
			}
			else if (StrEqual(sInfo, "leave"))
			{
				OpenLeaveConfirmation(param1);
			}
			else if (StrEqual(sInfo, "topgangs"))
			{
				StartOpeningTopGangsMenu(param1);
			}

		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}



/*****************************************************************
***********************  GANG CREATION  **************************
******************************************************************/



void StartGangCreation(int client)
{
	if (!IsValidClient(client))
	{
		ReplyToCommand(client, "[SM] You must be in-game to use this command!");
		return;
	}
	if (GetClientTeam(client) != 2)
	{
		ReplyToCommand(client, "[SM] You must be on the terrorist team to use this command!");
		return;
	}
	for (int i = 0; i <= 5; i++)
	{
		PrintToChat(client, " %s \x04Please type desired gang name in chat!", TAG);
	}
	ga_bSetName[client] = true;
}

public Action OnSay(int client, const char[] command, int args) 
{
	if (!IsValidClient(client))
	{
		return Plugin_Continue;
	}
	if (ga_bSetName[client])
	{
		char sText[64]; 
		GetCmdArgString(sText, sizeof(sText));
		
		StripQuotes(sText);
		TrimString(sText);
		
		if (strlen(sText) > 16)
		{
			PrintToChat(client, "%s \x04The name you selected is too long!", TAG);
			return Plugin_Handled;
		}
		
		Handle hDatapack = CreateDataPack();
		WritePackCell(hDatapack, client);
		WritePackString(hDatapack, sText);
		ResetPack(hDatapack);

		char sQuery[300];
		Format(sQuery, sizeof(sQuery), "SELECT * FROM hl_gangs_groups WHERE gang=\"%s\"", sText);
		SQL_TQuery(g_hDatabase, SQL_Callback_CheckName, sQuery, hDatapack);

		return Plugin_Handled;
	}
	else if (ga_bRename[client])
	{
		char sText[64]; 
		GetCmdArgString(sText, sizeof(sText));
		
		StripQuotes(sText);
		TrimString(sText);

		if (strlen(sText) > 16)
		{
			PrintToChat(client, "%s \x04The name you selected is too long!", TAG);
			return Plugin_Handled;
		}
		
		char sQuery[300];
		Format(sQuery, sizeof(sQuery), "SELECT * FROM hl_gangs_groups WHERE gang=\"%s\"", sText);
		
		Handle hDatapack = CreateDataPack();
		WritePackCell(hDatapack, client);
		WritePackString(hDatapack, sText);
		ResetPack(hDatapack);

		SQL_TQuery(g_hDatabase, SQL_Callback_CheckName, sQuery, hDatapack);

		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void SQL_Callback_CheckName(Handle hOwner, Handle hHndl, const char[] sError, Handle hDatapack)
{
	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}
	char sText[64];
	int client = ReadPackCell(hDatapack);
	ReadPackString(hDatapack, sText, sizeof(sText));
	CloseHandle(hDatapack);

	if (!IsValidClient(client))
	{
		return;
	}
	else
	{
		if (ga_bSetName[client])
		{
			if (SQL_GetRowCount(hHndl) == 0)
			{

				strcopy(ga_sGangName[client], sizeof(ga_sGangName[]), sText);
				ga_bHasGang[client] = true;
				ga_iDateJoined[client] = GetTime();
				ga_bHasGang[client] =  true;
				ga_sInvitedBy[client] = "N/A";
				ga_iRank[client] = GANGRANK_OWNER;
				ga_iGangSize[client] = 1;

				ga_iHealth[client] = 0;
				ga_iDamage[client] = 0;
				ga_iGravity[client] = 0;
				ga_iSpeed[client] = 0;
				ga_iSize[client] = 0;
				
				UpdateSQL(client);

				CreateTimer(0.2, Timer_OpenGangMenu, client, TIMER_FLAG_NO_MAPCHANGE);

				PrintToChatAll("%s \x04%N\x01 has created \x02%s", TAG, client, ga_sGangName[client]);

				ga_bSetName[client] = false;
			}
			else
			{
				PrintToChat(client, "%s \x04That name is already used, try again!", TAG);
			}
		}
		else if (ga_bRename[client])
		{
			if (SQL_GetRowCount(hHndl) == 0)
			{

				char sOldName[32];
				strcopy(sOldName, sizeof(sOldName), ga_sGangName[client]);
				strcopy(ga_sGangName[client], sizeof(ga_sGangName[]), sText);
				for (int i = 1; i <= MaxClients; i++)
				{
					if (IsValidClient(i) && StrEqual(ga_sGangName[i], sOldName))
					{
						strcopy(ga_sGangName[i], sizeof(ga_sGangName[]), sText);
					}
				}
				char sQuery[300];
				Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_players SET gang=\"%s\" WHERE gang=\"%s\"", sText, sOldName);

				SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery);

				Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_groups SET gang=\"%s\" WHERE gang=\"%s\"", sText, sOldName);

				SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery);
		
				Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_statistics SET gang=\"%s\" WHERE gang=\"%s\"", sText, sOldName);

				SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery);

				PrintToChatAll("%s \x04%N\x01 has changed the name of \x04%s\x01 to \x04%s", TAG, client, sOldName, sText);

				StartOpeningGangMenu(client);

				ga_bRename[client] = false;
			}
			else
			{
				PrintToChat(client, " %s \x04That name is already used, try again!");
			}
		}
	}
}

public Action Timer_OpenGangMenu(Handle hTimer, int client)
{
	StartOpeningGangMenu(client);
}


/*****************************************************************
*********************** MEMBER LIST MENU *************************
******************************************************************/


void StartOpeningMembersMenu(int client)
{
	if (!StrEqual(ga_sGangName[client], ""))
	{
		char sQuery[300];
		Format(sQuery, sizeof(sQuery), "SELECT * FROM hl_gangs_players WHERE gang=\"%s\"", ga_sGangName[client]);

		SQL_TQuery(g_hDatabase, SQLCallback_OpenMembersMenu, sQuery, GetClientUserId(client));
	}
}

public void SQLCallback_OpenMembersMenu(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{
	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}
	int client = GetClientOfUserId(iUserID);
	if (!IsValidClient(client))
	{
		return;
	}
	else
	{

		Handle hMenu = CreateMenu(MemberListMenu_CallBack, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem | MenuAction_Cancel);
		SetMenuTitle(hMenu, "Member List :");

		while (SQL_FetchRow(hHndl))
		{
			char a_sTempArray[5][128]; // 0 - SteamID | 1 - Name | 2 - Invited By | 3 - Rank | 4 - Date (UTF)
			SQL_FetchString(hHndl, 1, a_sTempArray[0], sizeof(a_sTempArray[])); // Steam-ID
			SQL_FetchString(hHndl, 2, a_sTempArray[1], sizeof(a_sTempArray[])); // Player Name
			SQL_FetchString(hHndl, 5, a_sTempArray[2], sizeof(a_sTempArray[])); // Invited By
			IntToString(SQL_FetchInt(hHndl, 4), a_sTempArray[3], sizeof(a_sTempArray[])); // Rank
			IntToString(SQL_FetchInt(hHndl, 6), a_sTempArray[4], sizeof(a_sTempArray[])); // Date


			char sInfoString[128];
			char sDisplayString[128];

			Format(sInfoString, sizeof(sInfoString), "%s;%s;%s;%i;%i", a_sTempArray[0], a_sTempArray[1], a_sTempArray[2], StringToInt(a_sTempArray[3]), StringToInt(a_sTempArray[4]));

			if (StrEqual(a_sTempArray[3], "0"))
			{
				Format(sDisplayString, sizeof(sDisplayString), "%s (Member)", a_sTempArray[1]);
			}
			else if (StrEqual(a_sTempArray[3], "1"))
			{
				Format(sDisplayString, sizeof(sDisplayString), "%s (Admin)", a_sTempArray[1]);
			}
			else if (StrEqual(a_sTempArray[3], "2"))
			{
				Format(sDisplayString, sizeof(sDisplayString), "%s (Owner)", a_sTempArray[1]);
			}
			AddMenuItem(hMenu, sInfoString, sDisplayString);
		}
		SetMenuExitBackButton(hMenu, true);
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	}
}

public int MemberListMenu_CallBack(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[128];
			GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));
			OpenIndividualMemberMenu(param1, sInfo);
		}
		case MenuAction_Cancel:
		{
			StartOpeningGangMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}

void OpenIndividualMemberMenu(int client, char[] sInfo)
{
	Handle hMenu = CreateMenu(IndividualMemberMenu_Callback, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem | MenuAction_Cancel);
	SetMenuTitle(hMenu, "Information On : ");

	char sTempArray[5][64]; // 0 - SteamID | 1 - Name | 2 - Invited By | 3 - Rank | 4 - Date (UTF)
	char sDisplayBuffer[32];

	ExplodeString(sInfo, ";", sTempArray, 5, sizeof(sTempArray[]));

	Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Name : %s", sTempArray[1]);
	AddMenuItem(hMenu, "", sDisplayBuffer, ITEMDRAW_DISABLED);

	Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Steam ID : %s", sTempArray[0]);
	AddMenuItem(hMenu, "", sDisplayBuffer, ITEMDRAW_DISABLED);

	Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Invited By : %s", sTempArray[2]);
	AddMenuItem(hMenu, "", sDisplayBuffer, ITEMDRAW_DISABLED);


	if (StrEqual(sTempArray[3], "0"))
	{
		Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Rank : Member");
	}
	else if (StrEqual(sTempArray[3], "1"))
	{
		Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Rank : Admin");
	}
	else if (StrEqual(sTempArray[3], "2"))
	{
		Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Rank : Owner");
	}
	AddMenuItem(hMenu, "", sDisplayBuffer, ITEMDRAW_DISABLED);

	char sFormattedTime[64];
	FormatTime(sFormattedTime, sizeof(sFormattedTime), "%x", StringToInt(sTempArray[4]));
	Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Date Joined : %s", sFormattedTime);

	AddMenuItem(hMenu, "", sDisplayBuffer, ITEMDRAW_DISABLED);

	SetMenuExitBackButton(hMenu, true);

	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int IndividualMemberMenu_Callback(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{

		}
		case MenuAction_Cancel:
		{
			StartOpeningMembersMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}
/*****************************************************************
*********************** INVITATION MENU **************************
******************************************************************/



void OpenInvitationMenu(int client)
{
	Handle hMenu = CreateMenu(InvitationMenu_Callback, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem);
	SetMenuTitle(hMenu, "Invite a player!");

	char sInfoString[64];
	char sDisplayString[64];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && i != client)
		{
			Format(sInfoString, sizeof(sInfoString), "%i", GetClientUserId(i));
			Format(sDisplayString, sizeof(sDisplayString), "%N", i);
			AddMenuItem(hMenu, sInfoString, sDisplayString, (ga_bHasGang[i] || ga_iRank[client] == GANGRANK_NORMAL)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
		}
	}

	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);

}

public int InvitationMenu_Callback(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[64];
			GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));
			int iUserID = StringToInt(sInfo);

			ga_iInvitation[GetClientOfUserId(iUserID)] = GetClientUserId(param1);

			if (ga_iGangSize[param1] >= gcv_iMaxGangSize.IntValue + ga_iSize[param1])
			{
				PrintToChat(param1, "%s \x04Your gang is full!");
			}

			if (!gcv_bInviteStyle.BoolValue)
			{
				PrintToChat(GetClientOfUserId(iUserID), "%s \x04Type !accept to join \x02%s\x04!", TAG, ga_sGangName[param1]);
			}
			else
			{
				OpenGangInvitationMenu(GetClientOfUserId(iUserID));
			}
			StartOpeningGangMenu(param1);
		}
		case MenuAction_Cancel:
		{
			StartOpeningGangMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}


void OpenGangInvitationMenu(int client)
{
	Handle hMenu = CreateMenu(SentInviteMenu_Callback, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem);
	SetMenuTitle(hMenu, "Invite a player!");
	char sDisplayString[64];

	Format(sDisplayString, sizeof(sDisplayString), "%N has invited you to their gang!", GetClientOfUserId(ga_iInvitation[client]));
	AddMenuItem(hMenu, "", sDisplayString, ITEMDRAW_DISABLED);

	Format(sDisplayString, sizeof(sDisplayString), "Would you like to join \"%s\"", ga_sGangName[GetClientOfUserId(ga_iInvitation[client])]);
	AddMenuItem(hMenu, "", sDisplayString, ITEMDRAW_DISABLED);

	AddMenuItem(hMenu, "yes", "Yes, I'd like to join");

	AddMenuItem(hMenu, "no", "No, I'd like to decline");

	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}


public int SentInviteMenu_Callback(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[64];
			GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));
			if (StrEqual(sInfo, "yes"))
			{
				ga_sGangName[param1] = ga_sGangName[GetClientOfUserId(ga_iInvitation[param1])];
				ga_iDateJoined[param1] = GetTime();
				ga_bHasGang[param1] =  true;
				ga_bSetName[param1] = false;
				
				ga_iHealth[param1] = ga_iHealth[GetClientOfUserId(ga_iInvitation[param1])];
				ga_iDamage[param1] = ga_iDamage[GetClientOfUserId(ga_iInvitation[param1])];
				ga_iGravity[param1] = ga_iGravity[GetClientOfUserId(ga_iInvitation[param1])];
				ga_iSpeed[param1] = ga_iSpeed[GetClientOfUserId(ga_iInvitation[param1])];
				ga_iSize[param1] = ga_iSize[GetClientOfUserId(ga_iInvitation[param1])];
				ga_iCTKills[param1] = ga_iCTKills[GetClientOfUserId(ga_iInvitation[param1])];
				
				char sName[MAX_NAME_LENGTH];
				GetClientName(GetClientOfUserId(ga_iInvitation[param1]), sName, sizeof(sName));
				ga_sInvitedBy[param1] = sName;
				ga_iGangSize[param1] = 1;
				ga_iRank[param1] = GANGRANK_NORMAL;
				UpdateSQL(param1);
				PrintToChatAll("%s \x05%N\x04 has joined \x02%s!", TAG, param1, ga_sGangName[param1]);
			}
			else if (StrEqual(sInfo, "no"))		
			{
				// Do Nothing
			}
		}
		case MenuAction_Cancel:
		{
			StartOpeningGangMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}


/*****************************************************************
***********************    PERK MENU     *************************
******************************************************************/


public void StartOpeningPerkMenu(int client)
{
	if (IsValidClient(client))
	{
		char sQuery[300];
		Format(sQuery, sizeof(sQuery), "SELECT health, damage, gravity, speed, size FROM hl_gangs_groups WHERE gang=\"%s\"", ga_sGangName[client]);
		SQL_TQuery(g_hDatabase, SQLCallback_Perks, sQuery, GetClientUserId(client));
	}
}

public void SQLCallback_Perks(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{
	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}
	
	int client = GetClientOfUserId(iUserID);
	
	if (!IsValidClient(client))
	{
		return;
	}
	else
	{
		Handle hMenu = CreateMenu(PerksMenu_CallBack, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem);
		SetMenuTitle(hMenu, "Gang Perks");
		if (SQL_GetRowCount(hHndl) == 1 && SQL_FetchRow(hHndl))
		{
			ga_iHealth[client] = SQL_FetchInt(hHndl, 0); // Health
			ga_iDamage[client] = SQL_FetchInt(hHndl, 1); // Damage
			ga_iGravity[client] = SQL_FetchInt(hHndl, 2); // Gravity
			ga_iSpeed[client] = SQL_FetchInt(hHndl, 3); // Speed
			ga_iSize[client] = SQL_FetchInt(hHndl, 4);
		}
		
		char sDisplayBuffer[64];

		Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Health [%i/10] [%i Credits]", ga_iHealth[client], gcv_iHealthPrice.IntValue);
		AddMenuItem(hMenu, "health", sDisplayBuffer, (ga_iHealth[client] >= 10 || GetClientCredits(client) < gcv_iHealthPrice.IntValue)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);


		Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Knife Damage [%i/10] [%i Credits]", ga_iDamage[client], gcv_iDamagePrice.IntValue);
		AddMenuItem(hMenu, "damage", sDisplayBuffer, (ga_iDamage[client] >= 10 || GetClientCredits(client) < gcv_iDamagePrice.IntValue)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);


		Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Gravity [%i/10] [%i Credits]", ga_iGravity[client], gcv_iGravityPrice.IntValue);
		AddMenuItem(hMenu, "gravity", sDisplayBuffer, (ga_iGravity[client] >= 10 || GetClientCredits(client) < gcv_iGravityPrice.IntValue)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);


		Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Speed [%i/10] [%i Credits]", ga_iSpeed[client], gcv_iSpeedPrice.IntValue);
		AddMenuItem(hMenu, "speed", sDisplayBuffer, (ga_iSpeed[client] >= 10 || GetClientCredits(client) < gcv_iSpeedPrice.IntValue)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

		Format(sDisplayBuffer, sizeof(sDisplayBuffer), "Gang Size [%i/9] [%i Credits]", ga_iSize[client], gcv_iSizePrice.IntValue);
		AddMenuItem(hMenu, "size", sDisplayBuffer, (ga_iSize[client] >= 9 || GetClientCredits(client) < gcv_iSizePrice.IntValue)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

		SetMenuExitBackButton(hMenu, true);
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	}
}

public int PerksMenu_CallBack(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[64];
			GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));
			char sQuery[300];
			
			if (StrEqual(sInfo, "health"))
			{
				SetClientCredits(param1, GetClientCredits(param1) - gcv_iHealthPrice.IntValue);
				++ga_iHealth[param1];
				PrintToGang(param1, true, "%s \x04Health upgrade will be applied next round!", TAG);
				Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_groups SET health=%i WHERE gang=\"%s\"", ga_iHealth[param1], ga_sGangName[param1]);
			}
			else if (StrEqual(sInfo, "damage"))
			{
				SetClientCredits(param1, GetClientCredits(param1) - gcv_iDamagePrice.IntValue);
				++ga_iDamage[param1];
				PrintToGang(param1, true, "%s \x02Damage\x04 upgrade has been applied!", TAG);
				Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_groups SET damage=%i WHERE gang=\"%s\"",  ga_iDamage[param1], ga_sGangName[param1]);
			}
			else if (StrEqual(sInfo, "gravity"))
			{
				SetClientCredits(param1, GetClientCredits(param1) - gcv_iGravityPrice.IntValue);
				PrintToGang(param1, true, "%s \x04Gravity will be applied next round!", TAG);
				++ga_iGravity[param1];
				Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_groups SET gravity=%i WHERE gang=\"%s\"", ga_iGravity[param1], ga_sGangName[param1]);
				SetEntityGravity(param1, GetClientGravityAmmount(param1));
			}
			else if (StrEqual(sInfo, "speed"))
			{
				SetClientCredits(param1, GetClientCredits(param1) - gcv_iSpeedPrice.IntValue);
				PrintToGang(param1, true, "%s \x05Speed\x04 upgrade has been applied!", TAG);
				++ga_iSpeed[param1];
				Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_groups SET speed=%i WHERE gang=\"%s\"", ga_iSpeed[param1], ga_sGangName[param1]);
				SetEntPropFloat(param1, Prop_Send, "m_flLaggedMovementValue", GetClientSpeedAmmount(param1));
			}
			else if (StrEqual(sInfo, "size"))
			{
				SetClientCredits(param1, GetClientCredits(param1) - gcv_iSizePrice.IntValue);
				PrintToGang(param1, true, "%s \x05Size\x04 upgrade has been applied!", TAG);
				++ga_iSize[param1];
				Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_groups SET size=%i WHERE gang=\"%s\"", ga_iSize[param1], ga_sGangName[param1]);
			}
			SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery, GetClientUserId(param1));
			
			StartOpeningPerkMenu(param1);
		}
		case MenuAction_Cancel:
		{
			StartOpeningGangMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}



/*****************************************************************
*******************    LEAVE CONFIRMATION     ********************
******************************************************************/


void OpenLeaveConfirmation(int client)
{
	Handle hMenu = CreateMenu(LeaveConfirmation_Callback, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem | MenuAction_Cancel);
	SetMenuTitle(hMenu, "Leave Gang?");

	AddMenuItem(hMenu, "", "Are you sure you want to leave?", ITEMDRAW_DISABLED);
	if (ga_iRank[client] == GANGRANK_OWNER)
	{
		AddMenuItem(hMenu, "", "As owner, leaving will disband your gang!", ITEMDRAW_DISABLED);
	}

	AddMenuItem(hMenu, "yes", "Yes, I'd like to leave!");
	AddMenuItem(hMenu, "no", "No, nevermind.");

	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int LeaveConfirmation_Callback(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[64];
			GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));
			if (StrEqual(sInfo, "yes"))
			{
				RemoveFromGang(param1);
			}
			else if (StrEqual(sInfo, "no"))
			{
				StartOpeningGangMenu(param1);
			}

		}
		case MenuAction_Cancel:
		{
			StartOpeningGangMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}




/*****************************************************************
*********************  ADMIN MAIN MENU  **************************
******************************************************************/


void OpenAdministrationMenu(int client)
{
	Handle hMenu = CreateMenu(AdministrationMenu_Callback, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem | MenuAction_Cancel);
	SetMenuTitle(hMenu, "Gang Admin");
	char sDisplayString[128];
	
	AddMenuItem(hMenu, "kick", "Kick a member", (ga_iRank[client] == GANGRANK_NORMAL)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	
	Format(sDisplayString, sizeof(sDisplayString), "Rename Gang [%i Credits]", gcv_iRenamePrice.IntValue);
	AddMenuItem(hMenu, "rename", sDisplayString, (ga_iRank[client] == GANGRANK_OWNER && GetClientCredits(client) >= gcv_iRenamePrice.IntValue)?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	
	AddMenuItem(hMenu, "promote", "Promote a member", (ga_iRank[client] == GANGRANK_NORMAL)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	
	AddMenuItem(hMenu, "disband", "Disband gang", (ga_iRank[client] == GANGRANK_OWNER)?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);


	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);

}

public int AdministrationMenu_Callback(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[64];
			GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));
			if (StrEqual(sInfo, "kick"))
			{
				OpenAdministrationKickMenu(param1);
			}
			else if (StrEqual(sInfo, "rename"))
			{
				SetClientCredits(param1, GetClientCredits(param1) - 100);
				for (int i = 1; i <= 5; i++)
				{
					PrintToChat(param1, " %s \x04Please type desired gang name in chat!", TAG);
				}
				ga_bRename[param1] = true;
			}
			else if (StrEqual(sInfo, "promote"))
			{
				OpenAdministrationPromotionMenu(param1);
			}
			else if (StrEqual(sInfo, "disband"))
			{
				OpenDisbandMenu(param1);
			}
		}
		case MenuAction_Cancel:
		{
			StartOpeningGangMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}



/*****************************************************************
*******************  ADMIN PROMOTION MENU  ***********************
******************************************************************/




void OpenAdministrationPromotionMenu(int client)
{
	if (!StrEqual(ga_sGangName[client], ""))
	{
		char sQuery[200];
		Format(sQuery, sizeof(sQuery), "SELECT * FROM hl_gangs_players WHERE gang=\"%s\"", ga_sGangName[client]);

		SQL_TQuery(g_hDatabase, SQLCallback_AdministrationPromotionMenu, sQuery, GetClientUserId(client));
	}
}

public void SQLCallback_AdministrationPromotionMenu(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{
	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}
	int client = GetClientOfUserId(iUserID);
	if (!IsValidClient(client))
	{
		return;
	}
	else
	{
		Handle hMenu = CreateMenu(AdministrationPromoMenu_CallBack, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem | MenuAction_Cancel);
		SetMenuTitle(hMenu, "Promote a player :");

		while (SQL_FetchRow(hHndl))
		{
			char sTempArray[3][128]; // 0 - SteamID | 1 - Name | 2 - Invited By | 3 - Rank | 4 - Date (UTF)
			SQL_FetchString(hHndl, 1, sTempArray[0], sizeof(sTempArray[])); // Steam-ID
			SQL_FetchString(hHndl, 2, sTempArray[1], sizeof(sTempArray[])); // Player Name
			IntToString(SQL_FetchInt(hHndl, 4), sTempArray[2], sizeof(sTempArray[])); // Rank

			char sSteamID[34];
			GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));

			if (!StrEqual(sSteamID, sTempArray[0]))
			{
				char sInfoString[128];
				char sDisplayString[128];
				Format(sInfoString, sizeof(sInfoString), "%s;%s;%i", sTempArray[0], sTempArray[1], StringToInt(sTempArray[2]));
				Format(sDisplayString, sizeof(sDisplayString), "%s (%s)", sTempArray[1], sTempArray[0]);
				AddMenuItem(hMenu, sInfoString, sDisplayString, (ga_iRank[client] == GANGRANK_OWNER)?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
			}
		}
		SetMenuExitBackButton(hMenu, true);
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	}
}

public int AdministrationPromoMenu_CallBack(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[256];
			GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));

			OpenPromoteDemoteMenu(param1, sInfo);
		}
		case MenuAction_Cancel:
		{
			OpenAdministrationMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}


void OpenPromoteDemoteMenu(int client, const char[] sInfo)
{
	char sTempArray[3][32];
	ExplodeString(sInfo, ";", sTempArray, 3, 32);

	Handle hMenu = CreateMenu(AdministrationPromoDemoteMenu_CallBack, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem | MenuAction_Cancel);
	SetMenuTitle(hMenu, "Gang Members Ranks");
	char sInfoString[32];

	AddMenuItem(hMenu, "", "Simply click on the desired rank to set", ITEMDRAW_DISABLED);
	
	Format(sInfoString, sizeof(sInfoString), "%s;normal", sTempArray[0]);
	AddMenuItem(hMenu, sInfoString, "Normal", (ga_iRank[client] != GANGRANK_OWNER)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

	Format(sInfoString, sizeof(sInfoString), "%s;admin", sTempArray[0]);
	AddMenuItem(hMenu, sInfoString, "Admin", (ga_iRank[client] != GANGRANK_OWNER)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int AdministrationPromoDemoteMenu_CallBack(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[256];
			GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));
			char sTempArray[2][32];
			ExplodeString(sInfo, ";", sTempArray, 2, 32);

			char sQuery[300];

			if (StrEqual(sTempArray[1], "normal"))
			{
				Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_players SET rank=0 WHERE steamid=\"%s\"", sTempArray[0]);
			}
			else if (StrEqual(sTempArray[1], "admin"))
			{
				Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_players SET rank=1 WHERE steamid=\"%s\"", sTempArray[0]);
			}
			
			SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery);
			char sSteamID[32];
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i))
				{
					GetClientAuthId(i, AuthId_Steam2, sSteamID, sizeof(sSteamID));
					if (StrEqual(sSteamID, sTempArray[0]))
					{
						LoadSteamID(i);
						break;
					}
				}
			}
		}
		case MenuAction_Cancel:
		{
			OpenAdministrationMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}





/*****************************************************************
*********************   DISBAND MENU    **************************
******************************************************************/







void OpenDisbandMenu(int client)
{
	Handle hMenu = CreateMenu(DisbandMenu_CallBack, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem | MenuAction_Cancel);
	SetMenuTitle(hMenu, "Disband Gang");

	AddMenuItem(hMenu, "", "Are you sure you want to disband your gang?", ITEMDRAW_DISABLED);
	AddMenuItem(hMenu, "", "This change is PERMANENT", ITEMDRAW_DISABLED);

	AddMenuItem(hMenu, "disband", "Disband The Gang", (ga_iRank[client] != GANGRANK_OWNER)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

	AddMenuItem(hMenu, "no", "Don't Disband The Gang", (ga_iRank[client] != GANGRANK_OWNER)?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int DisbandMenu_CallBack(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[256];
			GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));
			if (StrEqual(sInfo, "disband"))
			{
				RemoveFromGang(param1);
			}
		}
		case MenuAction_Cancel:
		{
			OpenAdministrationMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}

/*****************************************************************
*********************  ADMIN KICK MENU  **************************
******************************************************************/

void OpenAdministrationKickMenu(int client)
{
	if (!StrEqual(ga_sGangName[client], ""))
	{
		char sQuery[200];
		Format(sQuery, sizeof(sQuery), "SELECT * FROM hl_gangs_players WHERE gang=\"%s\"", ga_sGangName[client]);

		SQL_TQuery(g_hDatabase, SQLCallback_AdministrationKickMenu, sQuery, GetClientUserId(client));
	}
}

public void SQLCallback_AdministrationKickMenu(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{
	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}
	int client = GetClientOfUserId(iUserID);
	if (!IsValidClient(client))
	{
		return;
	}
	else
	{

		Handle hMenu = CreateMenu(AdministrationKickMenu_CallBack, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem | MenuAction_Cancel);
		SetMenuTitle(hMenu, "Kick Gang Members");

		while (SQL_FetchRow(hHndl))
		{
			char sTempArray[3][128]; // 0 - SteamID | 1 - Name | 2 - Invited By | 3 - Rank | 4 - Date (UTF)
			SQL_FetchString(hHndl, 1, sTempArray[0], sizeof(sTempArray[])); // Steam-ID
			SQL_FetchString(hHndl, 2, sTempArray[1], sizeof(sTempArray[])); // Player Name
			IntToString(SQL_FetchInt(hHndl, 4), sTempArray[2], sizeof(sTempArray[])); // Rank

			
			char sInfoString[128];
			char sDisplayString[128];

			Format(sInfoString, sizeof(sInfoString), "%s;%s", sTempArray[0], sTempArray[1]);
			Format(sDisplayString, sizeof(sDisplayString), "%s (%s)", sTempArray[1], sTempArray[0]);
			AddMenuItem(hMenu, sInfoString, sDisplayString, (ga_iRank[client] > StringToInt(sTempArray[2]))?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
		}
		SetMenuExitBackButton(hMenu, true);
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	}
}

public int AdministrationKickMenu_CallBack(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[256];
			GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));
			char sTempArray[2][128];
			ExplodeString(sInfo, ";", sTempArray, 2, 128);
			char sQuery1[128];
			Format(sQuery1, sizeof(sQuery1), "DELETE FROM hl_gangs_players WHERE steamid = \"%s\"", sTempArray[0]);
			SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery1);
			PrintToChatAll("%s \x04%s \x01 has been kicked from \x02%s", TAG, sTempArray[1], ga_sGangName[param1]);
			char sSteamID[64];
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i))
				{
					GetClientAuthId(i, AuthId_Steam2, sSteamID, sizeof(sSteamID));
					if (StrEqual(sSteamID, sTempArray[0]))
					{
						ResetVariables(i);
					}
				}
			}
		}
		case MenuAction_Cancel:
		{
			OpenAdministrationMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}


/*****************************************************************
**********************  TOP GANGS MENU  **************************
******************************************************************/



public void StartOpeningTopGangsMenu(int client)
{
	if (IsValidClient(client))
	{
		SQL_TQuery(g_hDatabase, SQL_Callback_TopMenu, "SELECT * FROM hl_gangs_statistics ORDER BY ctkills DESC", GetClientUserId(client));
	}
}

public void SQL_Callback_TopMenu(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{
	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}
	int client = GetClientOfUserId(iUserID);
	if (!IsValidClient(client))
	{
		return;
	}
	else
	{
		Handle hMenu = CreateMenu(TopGangsMenu_Callback, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem);
		SetMenuTitle(hMenu, "Top Gangs");
		if (SQL_GetRowCount(hHndl) == 0)
		{
			PrintToChat(client, "%s \x04There are no gangs created!", TAG);
			delete hMenu;
			return;
		}
		char sGangName[128];
		char sInfoString[128];

		
		ga_iTempInt2[client] = 0;
		g_iGangAmmount = 0;
		while (SQL_FetchRow(hHndl))
		{
			g_iGangAmmount++;
			ga_iTempInt2[client]++;
			
			SQL_FetchString(hHndl, 1, sGangName, sizeof(sGangName));
			
			Format(sInfoString, sizeof(sInfoString), "%i;%s;%i", ga_iTempInt2[client], sGangName, SQL_FetchInt(hHndl, 2));

			AddMenuItem(hMenu, sInfoString, sGangName);
		}

		SetMenuExitBackButton(hMenu, true);
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	}
}

public int TopGangsMenu_Callback(Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[300];
			char sQuery[300];
			char sTempArray[3][128];
			GetMenuItem(hMenu, param2, sInfo, sizeof(sInfo));

			ExplodeString(sInfo, ";", sTempArray, 3, sizeof(sTempArray[]));

			ga_iTempInt2[param1] = StringToInt(sTempArray[0]);
			ga_iTempInt[param1] = StringToInt(sTempArray[2]);
			
			Format(sQuery, sizeof(sQuery), "SELECT * FROM `hl_gangs_players` WHERE `gang` = \"%s\" AND `rank` = 2", sTempArray[1]);
			SQL_TQuery(g_hDatabase, SQL_Callback_GangStatistics, sQuery, GetClientUserId(param1));

		}
		case MenuAction_Cancel:
		{
			StartOpeningGangMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}


public void SQL_Callback_GangStatistics(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{
	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}
	int client = GetClientOfUserId(iUserID);
	if (!IsValidClient(client))
	{
		return;
	}
	else
	{
		char sTempArray[2][128]; // Gang Name | Player Name 
		char sFormattedTime[64];
		char sDisplayString[128];
		
		SQL_FetchRow(hHndl);


		SQL_FetchString(hHndl, 3, sTempArray[0], sizeof(sTempArray[]));
		SQL_FetchString(hHndl, 2, sTempArray[1], sizeof(sTempArray[]));
		int iDate = SQL_FetchInt(hHndl, 6);

		Handle hMenu = CreateMenu(MenuCallback_Void, MenuAction_Select | MenuAction_End | MenuAction_DisplayItem);
		SetMenuTitle(hMenu, "Top Gangs");

		Format(sDisplayString, sizeof(sDisplayString), "Gang Name : %s", sTempArray[0]);
		AddMenuItem(hMenu, "", sDisplayString, ITEMDRAW_DISABLED);

		Format(sDisplayString, sizeof(sDisplayString), "Gang Rank : %i/%i", ga_iTempInt2[client], g_iGangAmmount);
		AddMenuItem(hMenu, "", sDisplayString, ITEMDRAW_DISABLED);

		FormatTime(sFormattedTime, sizeof(sFormattedTime), "%x", iDate);
		Format(sDisplayString, sizeof(sDisplayString), "Date Created : %s", sFormattedTime);
		AddMenuItem(hMenu, "", sDisplayString, ITEMDRAW_DISABLED);

		Format(sDisplayString, sizeof(sDisplayString), "Created By : %s", sTempArray[1]);
		AddMenuItem(hMenu, "", sDisplayString, ITEMDRAW_DISABLED);

		Format(sDisplayString, sizeof(sDisplayString), "CT Kills : %i ", ga_iTempInt[client]);
		AddMenuItem(hMenu, "", sDisplayString, ITEMDRAW_DISABLED);

		SetMenuExitBackButton(hMenu, true);
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	}
}

public int MenuCallback_Void (Handle hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			// Do Nothing
		}
		case MenuAction_Cancel:
		{
			StartOpeningTopGangsMenu(param1);
		}
		case MenuAction_End:
		{
			CloseHandle(hMenu);
		}
	}
	return 0;
}

/*****************************************************************
***********************  PLUGIN STOCKS  **************************
******************************************************************/


stock void UpdateSQL(int client)
{
	if (ga_bHasGang[client] &&ga_bLoaded[client] && !StrEqual(ga_sSteamID[client], "", false))
	{
		char sQuery[300];
		Format(sQuery, sizeof(sQuery), "SELECT * FROM hl_gangs_players WHERE steamid=\"%s\"", ga_sSteamID[client]);

		SQL_TQuery(g_hDatabase, SQLCallback_CheckIfInDatabase_Player, sQuery, GetClientUserId(client));
	}
}

public void SQLCallback_CheckIfInDatabase_Player(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{
	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}

	int client = GetClientOfUserId(iUserID);

	if (!IsValidClient(client))
	{
		return;
	}
	if (SQL_GetRowCount(hHndl) == 0)
	{
		ga_bIsPlayerInDatabase[client] = false;
	}
	else
	{
		ga_bIsPlayerInDatabase[client] = true;
	}
	char sQuery[300];
	if (!ga_bIsPlayerInDatabase[client])
	{
		Format(sQuery, sizeof(sQuery), "INSERT INTO hl_gangs_players (gang, invitedby, rank, date, steamid, playername) VALUES(\"%s\", \"%s\", %i, %i, \"%s\", \"%N\")", ga_sGangName[client], ga_sInvitedBy[client], ga_iRank[client], ga_iDateJoined[client], ga_sSteamID[client], client);
	}
	else
	{
		Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_players SET gang=\"%s\",invitedby=\"%s\",playername=\"%N\",rank=%i,date=%i WHERE steamid=\"%s\"", ga_sGangName[client], ga_sInvitedBy[client], client, ga_iRank[client], ga_iDateJoined[client], ga_sSteamID[client]);
	}
	SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery);
	
	char sQuery2[128];

	Format(sQuery2, sizeof(sQuery2), "SELECT * FROM hl_gangs_groups WHERE gang=\"%s\"", ga_sGangName[client]);
	
	SQL_TQuery(g_hDatabase, SQLCALLBACK_GROUPS, sQuery2, GetClientUserId(client));

}
public void SQLCALLBACK_GROUPS(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{

	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}

	int client = GetClientOfUserId(iUserID);

	if (!IsValidClient(client))
	{
		return;
	}

	if (SQL_GetRowCount(hHndl) == 0)
	{
		ga_bIsGangInDatabase[client] = false;
	}
	else
	{
		ga_bIsGangInDatabase[client] = true;
	}

	char sQuery[300];
	if (!ga_bIsGangInDatabase[client])
	{
		Format(sQuery, sizeof(sQuery), "INSERT INTO hl_gangs_groups (gang, health, damage, gravity, speed) VALUES(\"%s\", %i, %i, %i, %i, %i)", ga_sGangName[client], ga_iHealth[client], ga_iDamage[client], ga_iGravity[client], ga_iSpeed[client], ga_iSize[client]);
	}
	else
	{
		Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_groups SET health=%i,damage=%i,gravity=%i,speed=%i,size=%i WHERE gang=\"%s\"", ga_iHealth[client], ga_iDamage[client], ga_iGravity[client], ga_iSpeed[client], ga_iSize[client], ga_sGangName[client]);

	}

	SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery);

	Format(sQuery, sizeof(sQuery), "SELECT * FROM hl_gangs_statistics WHERE gang = \"%s\"", ga_sGangName[client]);
	SQL_TQuery(g_hDatabase, SQL_Callback_LoadStatistics, sQuery, GetClientUserId(client));

}


public void SQL_Callback_LoadStatistics(Handle hOwner, Handle hHndl, const char[] sError, int iUserID)
{

	if (hHndl == INVALID_HANDLE)
	{
		SetDBHandle();
	}

	int client = GetClientOfUserId(iUserID);

	if (!IsValidClient(client))
	{
		return;
	}

	if (SQL_GetRowCount(hHndl) == 0)
	{
		ga_bIsGangInDatabase[client] = false;
	}
	else
	{
		ga_bIsGangInDatabase[client] = true;
	}

	char sQuery[300];
	if (!ga_bIsGangInDatabase[client])
	{
		Format(sQuery, sizeof(sQuery), "INSERT INTO hl_gangs_statistics (gang, ctkills) VALUES(\"%s\", %i)", ga_sGangName[client], ga_iCTKills[client]);
	}
	else
	{
		Format(sQuery, sizeof(sQuery), "UPDATE hl_gangs_statistics SET ctkills=%i WHERE gang=\"%s\"", ga_iCTKills[client], ga_sGangName[client]);
	}

	SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery);

}

void SetDBHandle()
{
	if (g_hDatabase == INVALID_HANDLE)
	{
		gcv_sDatabase.GetString(g_sDatabaseName, sizeof(g_sDatabaseName));
		SQL_TConnect(SQLCallback_Connect, g_sDatabaseName);
	}
}

void DeleteDuplicates()
{
	if (g_hDatabase != INVALID_HANDLE)
	{
		if (gcv_bDebug.BoolValue)
		{
			Log("hl_gangs.log","Duplicates detected in database. Deleting duplicate Steam IDs!");
		}
		SQL_TQuery(g_hDatabase, SQLCallback_Void, "delete hl_gangs_players from hl_gangs_players inner join (select min(id) minid, steamid from hl_gangs_players group by steamid having count(1) > 1) as duplicates on (duplicates.steamid = hl_gangs_players.steamid and duplicates.minid <> hl_gangs_players.id)", 4);
	}
}

int GetClientCredits(int client)
{
	return hl_jailbreakshop_GetClientCredits(client);
}

void SetClientCredits(int client, int iAmmount)
{
	hl_jailbreakshop_SetClientCredits(client, iAmmount);
}

void RemoveFromGang(int client)
{
	if (ga_iRank[client] == GANGRANK_OWNER)
	{
		char sQuery1[300];
		char sQuery2[300];
		char sQuery3[300];
		Format(sQuery1, sizeof(sQuery1), "DELETE FROM hl_gangs_players WHERE gang = \"%s\"", ga_sGangName[client]);
		Format(sQuery2, sizeof(sQuery2), "DELETE FROM hl_gangs_groups WHERE gang = \"%s\"", ga_sGangName[client]);
		Format(sQuery3, sizeof(sQuery2), "DELETE FROM hl_gangs_statistics WHERE gang = \"%s\"", ga_sGangName[client]);

		SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery1);
		SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery2);
		SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery3);
		PrintToChatAll("%s \x04%N\x01 has disbanded \x02%s", TAG, client, ga_sGangName[client]);
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && StrEqual(ga_sGangName[i], ga_sGangName[client]) && i != client)
			{
				ResetVariables(i);
			}
		}
		ResetVariables(client);
	}
	else
	{
		char sQuery1[128];
		Format(sQuery1, sizeof(sQuery1), "DELETE FROM hl_gangs_players WHERE steamid = \"%s\"", ga_sSteamID[client]);
		SQL_TQuery(g_hDatabase, SQLCallback_Void, sQuery1);
		PrintToChatAll("%s \x04%N\x01 has left \x02%s", TAG, client, ga_sGangName[client]);
		ResetVariables(client);
	}
}


float GetClientGravityAmmount(int client)
{
	float fGravityAmmount;
	switch (ga_iGravity[client])
	{
		case 1:
		{
			fGravityAmmount = 0.98;
		}
		case 2:
		{
			fGravityAmmount = 0.96;
		}
		case 3:
		{
			fGravityAmmount = 0.94;
		}
		case 4:
		{
			fGravityAmmount = 0.92;
		}
		case 5:
		{
			fGravityAmmount = 0.90;
		}
		case 6:
		{
			fGravityAmmount = 0.89;
		}
		case 7:
		{
			fGravityAmmount = 0.88;
		}
		case 8:
		{
			fGravityAmmount = 0.87;
		}
		case 9:
		{
			fGravityAmmount = 0.86;
		}
		case 10:
		{
			fGravityAmmount = 0.85;
		}
	}
	return fGravityAmmount;
}


float GetClientSpeedAmmount(int client)
{
	float fSpeedAmmount;
	switch (ga_iSpeed[client])
	{
		case 1:
		{
			fSpeedAmmount = 1.01;
		}
		case 2:
		{
			fSpeedAmmount = 1.02;
		}
		case 3:
		{
			fSpeedAmmount = 1.03;
		}
		case 4:
		{
			fSpeedAmmount = 1.04;
		}
		case 5:
		{
			fSpeedAmmount = 1.05;
		}
		case 6:
		{
			fSpeedAmmount = 1.06;
		}
		case 7:
		{
			fSpeedAmmount = 1.07;
		}
		case 8:
		{
			fSpeedAmmount = 1.08;
		}
		case 9:
		{
			fSpeedAmmount = 1.09;
		}
		case 10:
		{
			fSpeedAmmount = 1.1;
		}
	}
	return fSpeedAmmount;
}

void PrintToGang(int client, bool bPrintToClient = false, const char[] sMsg, any ...)
{
	if(!IsValidClient(client))
	{
		return;
	}
	char sFormattedMsg[256];
	VFormat(sFormattedMsg, sizeof(sFormattedMsg), sMsg, 4); 

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && StrEqual(ga_sGangName[i], ga_sGangName[client]) && !StrEqual(ga_sGangName[client], ""))
		{
			if (bPrintToClient)
			{
				PrintToChat(i, sFormattedMsg);
			}
			else
			{
				if (i == client)
				{
					// Do nothing
				}
				else
				{
					PrintToChat(i, sFormattedMsg);
				}
			}
		}
	}
}


stock void ResetVariables(int client)
{
	ga_iRank[client] = -1;
	ga_iGangSize[client] = -1;
	ga_iInvitation[client] = -1;
	ga_iDateJoined[client] = -1;
	ga_iHealth[client] = 0;
	ga_iDamage[client] = 0;
	ga_iGravity[client] = 0;
	ga_iSpeed[client] = 0;
	ga_iSize[client] = 0;
	ga_iTimer[client] = 0;
	ga_iCTKills[client] = 0;
	ga_iTempInt[client] = 0;
	ga_iTempInt2[client] = 0;
	ga_sGangName[client] = "";
	ga_sInvitedBy[client] = "";
	ga_bSetName[client] = false;
	ga_bIsPlayerInDatabase[client] = false;
	ga_bIsGangInDatabase[client] = false;
	ga_bHasGang[client] = false;
	ga_bRename[client] = false;
	ga_fChangedGravity[client] = 0.0;
	ga_sSteamID[client] = "";
	ga_bLoaded[client] = false;
}

void LastRequest()
{
	if (g_bLR)
	{
		return;
	}
	
	g_bLR = true;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (IsPlayerAlive(i) && GetClientTeam(i) == 2)
			{
				if (ga_bHasGang[i])
				{
					PrintToChat(i, "%s Your gang perks have been disabled!", TAG);
					if (GetClientHealth(i) > 100)
					{
						SetEntProp(i, Prop_Send, "m_iHealth", 100);
					}
					if (GetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue") != 1.0)
					{
						SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", 1.0);
					}
					SetEntityGravity(i, 1.0);
				}
			}
		}
	}
}

int GetPlayerAliveCount(int Team)
{
	int iAmmount = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == Team)
		{
			iAmmount++;
		}
	}
	return iAmmount;
}

bool IsValidClient(int client, bool bAllowBots = false, bool bAllowDead = true)
{
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client) || (IsFakeClient(client) && !bAllowBots) || IsClientSourceTV(client) || IsClientReplay(client) || (!bAllowDead && !IsPlayerAlive(client)))
	{
		return false;
	}
	return true;
}

void Log(char[] sPath, const char[] sMsg, any ...)
{
	char sLogFilePath[PLATFORM_MAX_PATH];
	char sFormattedMsg[256];
	BuildPath(Path_SM, sLogFilePath, sizeof(sLogFilePath), "logs/%s", sPath);
	VFormat(sFormattedMsg, sizeof(sFormattedMsg), sMsg, 3);
	LogToFileEx(sLogFilePath, "%s", sFormattedMsg);
}