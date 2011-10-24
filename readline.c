/* build@ cc -shared readline.c -o readline.so
** Completely and absolutely minimal binding to the readline library
** Steve Donovan, 2007
** Merged with http://lua-users.org/wiki/CompleteWithReadline
** by Ulrik, 2010. I disclaim any copyright on my contributions.
*
*  Enable completion in your lua REPL with:
*  lua -lreadline -lcomplete
*  where complete.lua defines a global function:
*  completion (word, line, startpos, endpos) -> array of matches
*/
#include <stdlib.h>
#include <stdio.h>

#include <readline/readline.h>
#include <readline/history.h>

#define LUA_LIB
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/* The readline library uses a lot of global variables,
 * so we do too. Lua state for the completion function.
 *  I'm sorry for this.. */
static lua_State *stateL;


static int f_readline(lua_State* L)
{
	const char* prompt = lua_tostring(L,1);
	char *line = readline(prompt);
	lua_pushstring(L, line);
	/* readline return value must be free'd */
	free(line);
	return 1;
}

static int f_add_history(lua_State* L)
{
	if (lua_strlen(L,1) > 0) {
		add_history(lua_tostring(L, 1));
	}
	return 0;
}

static int f_read_history(lua_State *L)
{
	const char* file = lua_tostring(L,1);
	if(read_history(file) != 0)
		luaL_error(L, "reading history from file %s failed", file);
	lua_pushboolean(L, 1);
	return 1;
}

static int f_write_history(lua_State *L)
{
	const char* file = lua_tostring(L,1);
	if(write_history(file) != 0)
		luaL_error(L, "writing history from file %s failed", file);
	lua_pushboolean(L, 1);
	return 1;
}

static const struct luaL_reg lib[] = {
	{"readline", f_readline},
	{"add_history",f_add_history},
	{"read_history", f_read_history},
	{"write_history", f_write_history},
	{NULL, NULL},
};

/* This function is called repeatedly by rl_completion_matches inside
   do_completion, each time returning one element from the Lua table. */
static char* table_iterator (const char* text, int state)
{
	size_t len;
	const char* str;
	char* result;
	lua_State* L = stateL;
	lua_rawgeti(L, -1, state+1);
	if(lua_isnil(L, -1))
		return NULL;
	str = lua_tolstring(L, -1, &len);
	result = malloc(len + 1);
	strcpy(result, str);
	lua_pop(L, 1);
	return result;
}

/* This function is called by readline() when the user wants a completion.
   ... */
static char** do_completion (const char* text, int istart, int iend)
{
	char** matches = NULL;
	lua_State* L = stateL;
	int top;

	if(L == NULL)
		return NULL;
	do {
		top = lua_gettop(L);
		lua_getglobal(L, "completion");
		if(!lua_isfunction(L, -1))
			break;
		lua_pushstring(L, text);
		lua_pushstring(L, rl_line_buffer);
		lua_pushinteger(L, istart+1);
		lua_pushinteger(L, iend+1);
		if(lua_pcall(L, 4, 1, 0))
			break;
		if(!lua_istable(L, -1))
			break;
		matches = rl_completion_matches (text, table_iterator);
	} while(0);
	lua_settop(L, top);
	rl_completion_suppress_append = 1;
	return (matches);
}

/* Initialise Readline for completion. It should be called from main().*/
static int init_completion(lua_State* L)
{
	stateL = L;
	rl_attempted_completion_function = do_completion;
	/* This is a list of Lua operators, separating words. */
	rl_basic_word_break_characters = " \t\n\"\\'><=;+-*/%^~#{}()[].:,";
	/* Inhibits the default added space on completed words. */
	rl_completion_append_character = '\0';
	/* The completion Lua function is loaded here. The user might prefer
	   to "require" a module or incorporate it into an existing script. */
	return 0;
}

int luaopen_readline (lua_State *L) {
	luaL_openlib (L, "readline", lib, 0);
	(void) init_completion(L);
	return 1;
}
