#if defined hl_gangs_credits_include
  #endinput
#endif
#define hl_gangs_credits_include
 

/**
 * Returns the client's credit ammount
 *
 * @param	client			client index
 * @return  int				credits
 */
native int Gangs_GetCredits(int client)

/**
 * Sets a client's credit ammount
 *
 * @param	client			client index
 * @return  no return
 */
native void Gangs_SetCredits(int client, int ammount);


public SharedPlugin hl_gangs_credits_include_shared =
{
	name = "[CS:GO] Gangs Credits",
	file = "hl_gangs_credits.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public hl_gangs_include_shared()
{	
	MarkNativeAsOptional("Gangs_GetCredits");
	MarkNativeAsOptional("Gangs_SetCredits");
}
#endif 