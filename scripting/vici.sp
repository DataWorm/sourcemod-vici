#pragma semicolon 1
//#pragma newdecls required

#include <sourcemod>
#include <geoip>
#include <basecomm>
#include <sdktools_engine>
#include <ripext>
#include <morecolors>
#include <nextmap>
 
public Plugin myinfo = {
	name = "VICI",
	author = "DataWorm",
	description = "Chatbot Connector",
	version = "1.0",
	url = "http://ed-bot.vici.bot.zone"
};

#define IsValidClient(%1)	(1 <= %1 <= MaxClients && IsClientInGame(%1))
#define CHAT_SYMBOL '@'

//static char botName[] = "Daniel Duck";
static char botName[] = "AI Bot";

static char g_ColorNames[13][10] = {"White", "Red", "Green", "Blue", "Yellow", "Purple", "Cyan", "Orange", "Pink", "Olive", "Lime", "Violet", "Lightblue"};

static ConVar g_authToken;
static ConVar g_heartbeat;
static ConVar g_Cvar_Chatmode;
static char authToken[51];
static HTTPClient httpClient;
static int roundCounter = 0; 
static char nextmap[50];
static Handle nextMapTimer;
static Handle heartbeatTimer;
static bool pluginStartComplete = false;

public void OnPluginStart() {
	g_authToken = CreateConVar("vici_token", "", "Sets a token managed by the backend server to authenticate/identify this gameserver. This value needs to be set otherwise the plugin will not perform any actions.", FCVAR_PROTECTED);
	g_authToken.AddChangeHook(authTokenChanged);
	g_heartbeat = CreateConVar("vici_heartbeat", "10", "The periodic time in seconds in which a heartbeat message is sent to the chatbot", FCVAR_PROTECTED);
	g_authToken.GetString(authToken, sizeof(authToken));
	
	g_Cvar_Chatmode = CreateConVar("sm_chat_mode", "1", "Allows player's to send messages to admin chat.", 0, true, 0.0, true, 1.0);
	
	httpClient = new HTTPClient("http://elite-duckerz.bot.zone");
	// httpClient.SetHeader("Authorization", "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==");
	
	AutoExecConfig(true, "vici");
	updateAuthToken();
	
	init();
	
	LogMessage("Plugin started!");
}

public init() {
	// basechat say commands redefined to also catch them and forward to the bot
	RegAdminCmd("sm_say", Command_SmSay, ADMFLAG_CHAT, "sm_say <message> - sends message to all players");
	RegAdminCmd("sm_csay", Command_SmCsay, ADMFLAG_CHAT, "sm_csay <message> - sends centered message to all players");
	RegAdminCmd("sm_hsay", Command_SmHsay, ADMFLAG_CHAT, "sm_hsay <message> - sends hint message to all players");
	RegAdminCmd("sm_tsay", Command_SmTsay, ADMFLAG_CHAT, "sm_tsay [color] <message> - sends top-left message to all players");
	RegAdminCmd("sm_chat", Command_SmChat, ADMFLAG_CHAT, "sm_chat <message> - sends message to admins");
	RegAdminCmd("sm_psay", Command_SmPsay, ADMFLAG_CHAT, "sm_psay <name or #userid> <message> - sends private message");
	RegAdminCmd("sm_msay", Command_SmMsay, ADMFLAG_CHAT, "sm_msay <message> - sends message as a menu panel");
	
	HookEvent("player_connect", Event_PlayerConnect); 
	HookEvent("player_disconnect", Event_PlayerDisconnect); 
	HookEvent("round_start", Event_RoundStart);  
	HookEvent("round_end", Event_RoundEnd);  
	HookEvent("player_changename", Event_PlayerChangeName);  
	//HookEvent("player_team", Event_PlayerTeamChange); 
	//HookEvent("player_spawn", Event_PlayerSpawn); 
	//HookEvent("player_death", Event_PlayerDeath);
	//HookEvent("player_hurt", Event_PlayerHurt);
	//HookEvent("player_footstep", Event_PlayerFootstep);  
	//HookEvent("player_falldamage", Event_PlayerFalldamage);

}

public updateAuthToken() {
	g_authToken.GetString(authToken, sizeof(authToken));
	if(strlen(authToken) > 0) {
		LogMessage("Auth Token has been configured!");
		if(!pluginStartComplete) {
			pluginStartComplete = true; 
			JSONObject metaData = new JSONObject();
			metaData.SetInt("heartbeatRate", g_heartbeat.IntValue);
			SendEventToBot("PLUGIN_STARTED", metaData);
			g_heartbeat.AddChangeHook(heartbeatChanged);
			updateHeartbeat(g_heartbeat.IntValue);
			init();
			OnMapStart();
			LogMessage("Plugin configured and ready!");
		}
	} else {
		LogMessage("Auth Token not yet configured");
	}
}

public authTokenChanged(ConVar convar, char[] oldValue, char[] newValue)
{
	updateAuthToken();
}

public void OnPluginEnd() {
	SendEventToBot("PLUGIN_STOPPED", new JSONObject());
}

public void heartbeatChanged(ConVar convar, char[] oldValue, char[] newValue) {
	updateHeartbeat(StringToInt(newValue));
}

public void updateHeartbeat(int newHeartbeat) {
	if(heartbeatTimer != null) {
		KillTimer(heartbeatTimer);
		heartbeatTimer = null;
	}
	if(newHeartbeat >= 1) {
		heartbeatTimer = CreateTimer(float(newHeartbeat), Heartbeat, _, TIMER_REPEAT);
	}
}

public void OnClientPostAdminCheck(int client) {
	// player gets a higher client id assigned when he connects to the server or his old one when he just reconnects due to map change
	if(IsFakeClient(client)) {
		return;
	}
	JSONObject metaData = new JSONObject();
	AddClientDetails(client, metaData);
	SendEventToBot("PLAYER_JOINED", metaData);
}

public void OnClientDisconnect(int client) {
	if(IsFakeClient(client)) {
		return;
	}
	JSONObject metaData = new JSONObject();
	AddClientDetails(client, metaData);
	SendEventToBot("PLAYER_LEFT", metaData);
}

public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) {
	int isBot = event.GetBool("bot");
	if(isBot) {
		return;
	}
	JSONObject metaData = new JSONObject();
	char username[35];
	event.GetString("name", username, sizeof(username));
	metaData.SetString("name", username);
	char steamId[30];
	event.GetString("networkid", steamId, sizeof(steamId));
	metaData.SetString("steamId", steamId);
	metaData.SetInt("userId", event.GetInt("userid"));
	metaData.SetInt("index", event.GetInt("index"));
	SendEventToBot("PLAYER_CONNECT", metaData);
}  

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int isBot = event.GetBool("bot");
	if(isBot) {
		return;
	}
	JSONObject metaData = new JSONObject();
	char username[35];
	event.GetString("name", username, sizeof(username));
	metaData.SetString("name", username);
	char steamId[30];
	event.GetString("networkid", steamId, sizeof(steamId));
	metaData.SetString("steamId", steamId);
	metaData.SetInt("userId", event.GetInt("userid"));
	char reason[64];
	event.GetString("reason", reason, sizeof(reason));
	metaData.SetString("reason", reason);
	SendEventToBot("PLAYER_DISCONNECT", metaData);
}  

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)  { 
	roundCounter++;
	JSONObject metaData = new JSONObject();
	metaData.SetInt("roundCounter", roundCounter);
	SendEventToBot("ROUND_START", metaData);
} 	

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)  {
	JSONObject metaData = new JSONObject();
	metaData.SetInt("winner", event.GetInt("winner"));
	metaData.SetInt("reason", event.GetInt("reason"));
	char message[64];
	event.GetString("message", message, sizeof(message));
	metaData.SetString("message", message);
	SendEventToBot("ROUND_END", metaData);
}

public void OnMapStart()  {
	if(!pluginStartComplete) {
		return;
	}
	roundCounter = 0;
	JSONObject metaData = new JSONObject();
	SendEventToBot("MAP_STARTED", metaData);
	nextmap = "";
	nextMapTimer = CreateTimer(15.0, CheckNextMap, _, TIMER_REPEAT);
}

public void OnMapEnd() {
	KillTimer(nextMapTimer);
	JSONObject metaData = new JSONObject();
	SendEventToBot("MAP_ENDED", metaData);
}

public Action CheckNextMap(Handle timer) {
	char map[50];
	char[] resettedValue = "";
	if(GetNextMap(map, sizeof(map))) {
		if(!StrEqual(nextmap, map)) {
			JSONObject metaData = new JSONObject();
			if(StrEqual(nextmap, resettedValue)) {
				metaData.SetBool("initialValue", true);
			} else {
				metaData.SetBool("initialValue", false);
			}
			metaData.SetString("nextmap", map);
			SendEventToBot("NEXTMAP_CHANGED", metaData);
			nextmap = map;
		}
	}
}

public Action Heartbeat(Handle timer) {
	SendEventToBot("HEARTBEAT", new JSONObject());
	return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	int startidx;
	if (sArgs[startidx] != CHAT_SYMBOL) {
		if (strcmp(command, "say", false) == 0) {
			SendMessageToBot(client, "say", sArgs[startidx]);
		} else if(strcmp(command, "say_team", false) == 0) {
			SendMessageToBot(client, "say_team", sArgs[startidx]);
		}
		return Plugin_Continue;
	}
	startidx++;
	
	if (strcmp(command, "say", false) == 0) {
		if (sArgs[startidx] != CHAT_SYMBOL) { // sm_say alias
			if (!CheckCommandAccess(client, "sm_say", ADMFLAG_CHAT)) {
				return Plugin_Continue;
			}
			SendMessageToBot(client, "sm_say", sArgs[startidx]);
			return Plugin_Continue;
		}
		startidx++;
		if (sArgs[startidx] != CHAT_SYMBOL) { // sm_psay alias
			if (!CheckCommandAccess(client, "sm_psay", ADMFLAG_CHAT)) {
				return Plugin_Continue;
			}
			char arg[64];
			int len = BreakString(sArgs[startidx], arg, sizeof(arg));
			int target = FindTarget(client, arg, true, false);
			if (target == -1 || len == -1)
				return Plugin_Continue;
			SendPrivateMessageToBot(client, target, sArgs[startidx+len]);
			return Plugin_Continue;
		}
		startidx++;
		// sm_csay alias
		if (!CheckCommandAccess(client, "sm_csay", ADMFLAG_CHAT)) {
			return Plugin_Continue;
		}
		SendMessageToBot(client, "sm_csay", sArgs[startidx]);
		return Plugin_Continue;
	}
	else if (strcmp(command, "say_team", false) == 0 || strcmp(command, "say_squad", false) == 0) {
		if (!CheckCommandAccess(client, "sm_chat", ADMFLAG_CHAT) && !g_Cvar_Chatmode.BoolValue) {
			return Plugin_Continue;
		}
		SendMessageToBot(client, "sm_chat", sArgs[startidx]);
		return Plugin_Continue;
	}
	return Plugin_Continue;
}

public Action Command_SmSay(int client, int args) {
	if (args < 1) {
		return Plugin_Continue;	
	}
	char text[192];
	GetCmdArgString(text, sizeof(text));
	SendMessageToBot(client, "sm_say", text);
	return Plugin_Continue;			
}

public Action Command_SmCsay(int client, int args) {
	if (args < 1) {
		return Plugin_Continue;	
	}
	char text[192];
	GetCmdArgString(text, sizeof(text));
	SendMessageToBot(client, "sm_csay", text);
	return Plugin_Continue;			
}

public Action Command_SmHsay(int client, int args) {
	if (args < 1) {
		return Plugin_Continue;	
	}
	char text[192];
	GetCmdArgString(text, sizeof(text));
	SendMessageToBot(client, "sm_hsay", text);
	return Plugin_Continue;		
}

public Action Command_SmTsay(int client, int args) {
	if (args < 1) {
		return Plugin_Continue;	
	}
	char text[192], colorStr[16];
	GetCmdArgString(text, sizeof(text));
	int len = BreakString(text, colorStr, 16);
	SendMessageToBot(client, "sm_tsay", text[FindColor(colorStr) == -1 ? 0 : len]);
	return Plugin_Continue;		
}

public Action Command_SmChat(int client, int args) {
	if (args < 1) {
		return Plugin_Continue;	
	}
	char text[192];
	GetCmdArgString(text, sizeof(text));
	SendMessageToBot(client, "sm_chat", text);
	return Plugin_Continue;		
}

public Action Command_SmPsay(int client, int args) {
	if (args < 2) {
		return Plugin_Continue;	
	}
	char text[192], arg[64], message[192];
	GetCmdArgString(text, sizeof(text));
	int len = BreakString(text, arg, sizeof(arg));
	BreakString(text[len], message, sizeof(message));
	int target = FindTarget(client, arg, true, false);
	if (target == -1)
		return Plugin_Continue;	
	SendPrivateMessageToBot(client, target, message);
	return Plugin_Continue;	
}

public Action Command_SmMsay(int client, int args) {
	if (args < 1) {
		return Plugin_Continue;	
	}
	char text[192];
	GetCmdArgString(text, sizeof(text));
	SendMessageToBot(client, "sm_msay", text);
	return Plugin_Continue;		
}

int FindColor(const char[] color) {
	for (int i = 0; i < sizeof(g_ColorNames); i++) {
		if (strcmp(color, g_ColorNames[i], false) == 0)
			return i;
	}
	return -1;
}

 
/*
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim_id = event.GetInt("userid");
	int attacker_id = event.GetInt("attacker");
	int victim = GetClientOfUserId(victim_id);
	int attacker = GetClientOfUserId(attacker_id);
	JSONObject metaData = new JSONObject();
	AddClientDetails(victim, metaData);
	JSONObject attackerObject = new JSONObject();
	AddClientDetails(attacker, attackerObject);
	metaData.Set("attacker", attackerObject);
	SendEventToBot("PLAYER_DEATH", metaData);
	delete attackerObject;
}


public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	int victim_id = event.GetInt("userid");
	int attacker_id = event.GetInt("attacker");
	int victim = GetClientOfUserId(victim_id);
	int attacker = GetClientOfUserId(attacker_id);
	int health = event.GetInt("health");
	int armor = event.GetInt("armor");
	int dmg_health = event.GetInt("dmg_health");
	int dmg_armor = event.GetInt("dmg_armor");
	int hitgroup = event.GetInt("hitgroup");
	char weapon[15];
	event.GetString("weapon", weapon, sizeof(weapon));
	JSONObject metaData = new JSONObject();
	AddClientDetails(victim, metaData);
	JSONObject attackerObject = new JSONObject();
	AddClientDetails(attacker, attackerObject);
	metaData.Set("attacker", attackerObject);
	metaData.SetInt("health", health);
	metaData.SetInt("armor", armor);
	metaData.SetInt("healthDamage", dmg_health);
	metaData.SetInt("armorDamage", dmg_armor);
	metaData.SetInt("hitGroup", hitgroup);
	metaData.SetString("attackerWeapon", weapon);
	SendEventToBot("PLAYER_HURT", metaData);
	delete attackerObject;
}

public void Event_PlayerFootstep(Event event, const char[] name, bool dontBroadcast) {
	// only triggered when a real step is made, not when player just tried to make a step but fails (e.g. running against a wall)
	int client_id = event.GetInt("userid");
	int client = GetClientOfUserId(client_id);
	JSONObject metaData = new JSONObject();
	AddClientDetails(client, metaData);
	SendEventToBot("PLAYER_FOOTSTEP", metaData);
}

public void Event_PlayerFalldamage(Event event, const char[] name, bool dontBroadcast) {
	int client_id = event.GetInt("userid");
	int client = GetClientOfUserId(client_id);
	float damage = event.GetFloat("damage");
	JSONObject metaData = new JSONObject();
	metaData.SetFloat("damage", damage);
	AddClientDetails(client, metaData);
	SendEventToBot("PLAYER_FALL_DAMAGE", metaData);
}
*/

public void Event_PlayerChangeName(Event event, const char[] name, bool dontBroadcast) {
	int client_id = event.GetInt("userid");
	int client = GetClientOfUserId(client_id);
	char oldName[40];
	char newName[40];
	event.GetString("oldname", oldName, sizeof(oldName));
	event.GetString("newname", newName, sizeof(newName));
	JSONObject metaData = new JSONObject();
	metaData.SetString("oldName", oldName);
	metaData.SetString("newName", newName);
	AddClientDetails(client, metaData);
	SendEventToBot("PLAYER_NAME_CHANGED", metaData);
}

public void Event_PlayerTeamChange(Event event, const char[] name, bool dontBroadcast) {
	int client_id = event.GetInt("userid");
	int client = GetClientOfUserId(client_id);
	int fromTeam = event.GetInt("oldteam");
	int toTeam = event.GetInt("team");
	bool disconnect = event.GetBool("disconnect"); // team change because player disconnects
	JSONObject metaData = new JSONObject();
	metaData.SetInt("fromTeam", fromTeam);
	metaData.SetInt("toTeam", toTeam);
	metaData.SetBool("causedByPlayerDisconnect", disconnect);
	AddClientDetails(client, metaData);
	SendEventToBot("PLAYER_TEAM_CHANGED", metaData);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client_id = event.GetInt("userid");
	int client = GetClientOfUserId(client_id);
	JSONObject metaData = new JSONObject();
	AddClientDetails(client, metaData);
	SendEventToBot("PLAYER_SPAWNED", metaData);
}

public void OnResponseReceived(HTTPResponse response, any value) {
	if (response.Data == null) {
		// Invalid JSON response
		LogError("Invalid Response!");
		return;
	}
	if (response.Status != HTTPStatus_OK) {
		JSONObject result = view_as<JSONObject>(response.Data);
		char message[256];
		result.GetString("message", message, sizeof(message));
		LogError("Chatbot Connection Failed [Status Code: %i]: %s", response.Status, message);
		return;
	}

	JSONArray results = view_as<JSONArray>(response.Data);
	int numResults = results.Length;
	JSONObject result;
	char message[256];
	
	for (int i = 0; i < numResults; i++) {
		result = view_as<JSONObject>(results.Get(i));
		int responseType = result.GetInt("responseType");
		if(responseType == 0) { // public chat
			result.GetString("message", message, sizeof(message));
			CPrintToChatAll("{fullred}(Admin) {lawngreen}%s: {fuchsia}%s", botName, message);
		}
		else if(responseType == 1) { // private chat
			result.GetString("message", message, sizeof(message));
			JSONArray targets = view_as<JSONArray>(result.Get("responseTargets"));
			int numTargets = targets.Length;
			for (int j = 0; j < numTargets; j++) {
				CPrintToChat(targets.GetInt(j), "{fullred}(Private) %s: {navajowhite}%s", botName, message);
			}
			delete targets;
		}
		delete result;
    }
	delete results;
}  

public void SendMessageToBot(int client, const char[] sayCommand, const char[] message) {
	JSONObject viciData = new JSONObject();
	viciData.SetString("sayCommand", sayCommand);
	viciData.SetString("message", message);
	AddClientDetails(client, viciData);
	SendEventToBot("CHAT", viciData);
}

public void SendPrivateMessageToBot(int client, int receiver, const char[] message) {
	JSONObject viciData = new JSONObject();
	viciData.SetString("sayCommand", "sm_psay");
	viciData.SetString("message", message);
	AddClientDetails(client, viciData);
	JSONObject receiverDetails = new JSONObject();
	AddClientDetails(receiver, receiverDetails);
	viciData.Set("receiver", receiverDetails);
	SendEventToBot("CHAT", viciData);
	delete receiverDetails;
}

public void SendEventToBot(char[] eventType, JSONObject metaData) {
	// LogMessage("Send event of type %s", eventType);
	metaData.SetString("eventType", eventType);
	AddGameDetails(metaData);
	SendToBot(metaData);
}

public void SendToBot(JSONObject metaData) {	
	if(pluginStartComplete) {
		metaData.SetString("source", "css");
		metaData.SetString("token", authToken);
		metaData.SetInt("playerCount", GetClientCount(true));
		httpClient.Post("daniel-duck.php", metaData, OnResponseReceived);
	}
	delete metaData;
}

public void AddGameDetails(JSONObject gameDetailObject) {
	char map[128];
	GetCurrentMap(map, sizeof(map));
	gameDetailObject.SetString("map", map);
}

public void AddClientDetails(int client, JSONObject clientDetailObject) {
	char username[35];
	GetClientName(client, username, sizeof(username));
	clientDetailObject.SetInt("clientId", client);
	clientDetailObject.SetString("username", username);
	
	if(!IsValidClient(client)) {
		return;
	}
	bool isBot = IsFakeClient(client);
	clientDetailObject.SetBool("isBot", isBot);
	
	int health = GetClientHealth(client);
	int team = GetClientTeam(client);
	
	float eyePosition[3]; 
	GetClientEyePosition(client, eyePosition); 
	char place[64]; 
	GetEntPropString(client, Prop_Send, "m_szLastPlaceName", place, sizeof(place)); 
	
	
	clientDetailObject.SetInt("team", team);
	clientDetailObject.SetInt("health", health);
	// temporarily splitted to avoid further object handles that could possibly cause a memory leak
	/*
	JSONObject eyePos = new JSONObject();
	eyePos.SetFloat("x", eyePosition[0]);
	eyePos.SetFloat("y", eyePosition[1]);
	eyePos.SetFloat("z", eyePosition[2]);
	clientDetailObject.Set("eyePos", eyePos);
	*/
	clientDetailObject.SetFloat("eyePosX", eyePosition[0]);
	clientDetailObject.SetFloat("eyePosY", eyePosition[1]);
	clientDetailObject.SetFloat("eyePosZ", eyePosition[2]);
	clientDetailObject.SetString("place", place);
	
	if(isBot) {
		return;
	}
	
	AdminId adminId = GetUserAdmin(client);
	clientDetailObject.SetBool("isChatAdmin", adminId != INVALID_ADMIN_ID && adminId.HasFlag(Admin_Chat));
	
	int steamAccountId = GetSteamAccountID(client, true);
	char steamId2[20], steamId3[20], steamId64[20], engineId[20];
	GetClientAuthId(client, AuthId_Steam2, steamId2, sizeof(steamId2));
	GetClientAuthId(client, AuthId_Steam3, steamId3, sizeof(steamId3));
	GetClientAuthId(client, AuthId_SteamID64, steamId64, sizeof(steamId64));
	GetClientAuthId(client, AuthId_Engine, engineId, sizeof(engineId));

	char ip[50];
	GetClientIP(client, ip, sizeof(ip), true);
	char countryCode[3];
	GeoipCode2(ip, countryCode);
	float connectionTime = -1.0;
	connectionTime = GetClientTime(client);
	
	clientDetailObject.SetString("steamId2", steamId2);
	clientDetailObject.SetString("steamId3", steamId3);
	clientDetailObject.SetString("steamId64", steamId64);
	clientDetailObject.SetString("engineId", engineId);
	clientDetailObject.SetInt("steamAccountId", steamAccountId);
	clientDetailObject.SetString("ip", ip);
	clientDetailObject.SetString("countryCode", countryCode);
	clientDetailObject.SetFloat("connectionTime", connectionTime);
	clientDetailObject.SetBool("isAlive", IsPlayerAlive(client));
	clientDetailObject.SetBool("isGagged", BaseComm_IsClientGagged(client));
	clientDetailObject.SetBool("isMuted", BaseComm_IsClientMuted(client));
}

/*
bool convertSteam2to3(int client, int args)
{
	if (args == 0) {
		ReplyToCommand(client, "Usage: steam2to3 STEAM_0:x:yyyyyy");
		return false;
	}
	
	char steam2[20];
	char steam3[17];
	char parts[3][10];
	int universe;
	int steamid32;
	
	GetCmdArgString(steam2, sizeof(steam2));
	
	if (IsSteamIDSpecial(steam2)) {
		strcopy(steam3, sizeof(steam3), steam2);
	}
	else {
		ExplodeString(steam2, ":", parts, sizeof(parts), sizeof(parts[]));
		
		ReplaceString(parts[0], sizeof(parts[]), "STEAM_", "");
		
		universe = StringToInt(parts[0]);
		if (universe == 0)
			universe = 1;
	
		steamid32 = StringToInt(parts[1]) + (StringToInt(parts[2]) << 1);
		
		Format(steam3, sizeof(steam3), "U:%d:%d", universe, steamid32);
	}
	
	ReplyToCommand(client, "Steam2: \"%s\" = Steam3: \"%s\"", steam2, steam3);
	return true;
}

bool convertSteam3to2(int client, int args) {
	if (args == 0) {
		ReplyToCommand(client, "Usage: steam3to2 U:x:yyyyyy");
		return false;
	}

	char steam3[17];
	char steam2[2][20];
	char parts[3][10];
	int universe;
	int steamid32;
	
	GetCmdArgString(steam3, sizeof(steam3));

	if (IsSteamIDSpecial(steam3)) {
		strcopy(steam2[0], sizeof(steam2[]), steam3);
	}
	else {
		ExplodeString(steam3, ":", parts, sizeof(parts), sizeof(parts[]));
		
		if (!StrEqual(parts[0], "U")) {
			ReplyToCommand(client, "Only \"U\" type accounts are convertible to Steam2");
			return false;
		}
		
		universe = StringToInt(parts[1]);
		
		steamid32 = StringToInt(parts[2]);
		
		Format(steam2[0], sizeof(steam2[]), "STEAM_%d:%d:%d", universe, steamid32 & (1 << 0), steamid32 >>> 1);
		
		if (universe == 1)
			Format(steam2[1], sizeof(steam2[]), "STEAM_%d:%d:%d", 0, steamid32 & (1 << 0), steamid32 >>> 1);
	}
	
	if (universe == 1) {
		ReplyToCommand(client, "OR Steam3: \"%s\" = Steam2: \"%s\" OR \"%s\"", steam3, steam2[0], steam2[1]);
	}
	else {
		ReplyToCommand(client, "Steam3: \"%s\" = Steam2: \"%s\"", steam3, steam2[0]);
	}
	return true;
}

bool IsSteamIDSpecial(const char[] steamid) {
	if (StrEqual(steamid, "STEAM_ID_PENDING") || StrEqual(steamid, "BOT") || StrEqual(steamid, "UNKNOWN")) {
		return true;
	}
	return false;
}
*/