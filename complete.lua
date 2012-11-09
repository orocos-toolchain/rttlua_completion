-- This Lua file implements the main completion.
-- Licensed under the MIT License.

require "rttlib"
require "readline"
require "utils"

local ts = tostring
local stderr=function(...) return end

-- This function is called back by C function do_completion, itself called
-- back by readline library, in order to complete the current input line.
function completion(word, line, startpos, endpos)
   stderr("\nmain, word:" .. ts(word), " line:" .. ts(line),
	  " start:".. ts(startpos), " end:".. ts(endpos) .. '\n')
   -- The complete list of Lua keywords
   local keywords = {
      'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
      'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat',
      'return', 'then', 'true', 'until', 'while' }

   -- Helper function registering possible completion words, verifying matches.
   local matches = { }
   local function add(value)
      value = tostring(value)
      if value:match("^"..word) then
	 matches[#matches+1] = value
      end
   end

   local function rtt_constructor(tab)
      local mt = getmetatable(tab)
      if mt == getmetatable(rtt.Variable) then return 'Variable'
      elseif mt == getmetatable(rtt.Property) then return 'Property'
      elseif mt == getmetatable(rtt.InputPort) then return 'InputPort'
      elseif mt == getmetatable(rtt.OutputPort) then return 'OutputPort'
      elseif mt == getmetatable(rtt.EEHook) then return 'EEHook' end
      return false
   end

   local function complete_rtt_type()
      for _,v in ipairs(rtt.types()) do add("'"..v.."'") end
   end

   -- This function does the same job as the default completion of readline,
   -- completing paths and filenames. Rewritten because
   -- rl_basic_word_break_characters is different.
   -- Uses LuaFileSystem (lfs) module for this task.
   local function filename_list(str)
      local path, name = str:match("(.*)[\\/]+(.*)")
      path = (path or ".").."/"
      name = name or str
      for f in lfs.dir(path) do
	 if (lfs.attributes(path..f) or {}).mode == 'directory' then
	    add(f.."/")
	 else
	    add(f)
	 end
      end
   end

   --- Complete (metatable) operations for a callable rtt object
   local function callable_rtt_obj_add_ops(o)
      local res = {}
      local mt = getmetatable(o)
      for name,_ in pairs(mt) do
	 add(name ..'(')
      end
   end

   local function taskcontext_add_ops(tc)
      local res = {}
      local mt = getmetatable(tc)

      for name,_ in pairs(mt) do res[#res+1] = name end
      for _,op in ipairs(tc:getOps()) do res[#res+1] = op end

      for _,op in ipairs(utils.table_unique(res)) do
	 local typ, ar = nil
	 if tc:hasOperation(op) then typ,ar = tc:getOpInfo(op) end
	 if not ar or ar ~= 0 then
	    -- unknown lua function or multiple arguments:
	    add(op..'(')
	 else
	    -- known that this op takes no arguments:
	    add(op..'()')
	 end
      end
   end

   -- This function makes a guess of the next character following an identifier,
   -- based on the type of the value it holds.
   local function postfix(value)
      local t = rttlib.rtt_type(value)
      if t == 'function' or (getmetatable(value) or {}).__call then
	 return '('
      elseif t == 'TaskContext' then return ':'
      elseif t == 'InputPort' or t=='OutputPort' then return ':'
      elseif t == 'table' and #value > 0 then
	 return '['
      elseif t == 'table' then
	 return '.'
      else
	 return ' '
      end
   end

   -- This function is called in a context where a keyword or a global
   -- variable can be inserted. Local variables cannot be listed!
   local function add_globals()
      for _,k in ipairs(keywords) do
	 add(k..'')
      end
      for k,v in pairs(_G) do
	 add(k..postfix(v))
      end
   end

   -- Main completion function. It evaluates the current sub-expression
   -- to determine its type. Currently supports tables fields, global
   -- variables and function prototype completion.
   local function contextual_list(expr, sep, str)
      stderr("contextual_list, expr:" .. ts(expr), " sep:" .. ts(sep) .. " str:".. ts(str), '\n')
      -- mk: we want to complete op names etc: if str then return filename_list(str) end
      --if expr == nil or expr == "" then return add_globals() end
      if expr == nil or expr == "" then return add_globals() end
      local v = loadstring("return "..expr)
      if not v then return end
      v = v()
      local t = rttlib.rtt_type(v)
      if sep == '.' then
	 if t == 'table' then
	    for k,v2 in pairs(v) do
	       if type(k) == 'string' then
		  add(k..postfix(v2))
	       end
	    end
	 elseif t=='Variable' then
	    local parts = v:getMemberNames()
	    if #parts == 2 and -- catch arrays
	       utils.table_has(parts, "size") and utils.table_has(parts, "capacity") then
	       return
	    else
	       for k,v2 in pairs(parts) do add(v2) end
	    end
	 else
	    return
	 end
      elseif sep == ':' then
      	 if t == 'TaskContext' then taskcontext_add_ops(v)
	 elseif t == 'InputPort' or t=='OutputPort' or t=='Variable' or
	    t=='EEHook' or t=='Operation' or t=='SendHandle' or t=='Service' or
	    t=='ServiceRequester' then
	    callable_rtt_obj_add_ops(v)
	 else
	    return
	 end
      elseif sep == '[' then
	 if t ~= 'table' then return end
	 for k,v2 in pairs(v) do
	    if type(k) == 'number' then
	       add(k.."]"..postfix(v2))
	    end
	 end
	 if word ~= "" then add_globals() end
      elseif sep == '(' then
	 -- This is a great place to return the prototype of the function,
	 -- in case your application has some mean to know it.
	 -- The following is just a useless example:
	 if t == 'Operation' then
	    io.stderr:write('\n'..tostring(v))
	 elseif t=='table' then
	    -- This doesn't work yet, because the simplify_expression
	    -- eats up our string.
	    local typ=rtt_constructor(v)
	    if typ == 'Variable' then complete_rtt_type() end
	 elseif t=='TaskContext' then
	    print(v)
	 end
      end
   end

   -- This complex function tries to simplify the input line, by removing
   -- literal strings, full table constructors and balanced groups of
   -- parentheses. Returns the sub-expression preceding the word, the
   -- separator item ( '.', '[', '(' ) and the current string in case
   -- of an unfinished string literal.
   function simplify_expression(expr)
      -- replace annoying sequences \' and \" inside literal strings
      expr = expr:gsub("\\(['\"])", function(c) return
				       string.format("\\%03d", string.byte(c)) end)
      local curstring
      -- remove (finished and unfinished) literal strings
      while true do
      	 local idx1,_,equals = expr:find("%[(=*)%[")
      	 local idx2,_,sign = expr:find("(['\"])")
      	 if idx1 == nil and idx2 == nil then break end
      	 local idx,startpat,endpat
      	 if (idx1 or math.huge) < (idx2 or math.huge) then
      	    idx,startpat,endpat  = idx1, "%["..equals.."%[", "%]"..equals.."%]"
      	 else
      	    idx,startpat,endpat = idx2, sign, sign
      	 end
      	 if expr:sub(idx):find("^"..startpat..".-"..endpat) then
      	    expr = expr:gsub(startpat.."(.-)"..endpat, " STRING ")
      	 else
      	    expr = expr:gsub(startpat.."(.*)", function(str)
      						  curstring = str; return "(CURSTRING " end)
      	 end
      end
      expr = expr:gsub("%b()"," PAREN ")      -- remove groups of parentheses
      expr = expr:gsub("%b{}"," TABLE ")      -- remove table constructors
      -- avoid two consecutive words without operator
      expr = expr:gsub("(%w)%s+(%w)","%1|%2")
      expr = expr:gsub("%s","")               -- remove now useless spaces
      -- This main regular expression looks for table indexes and function calls.
      -- You may have to complete it depending on your application.
      return curstring,expr:match("([%.%w%[%]_]-)([%.%:%[%(])"..word.."$")
   end

   -- Now calls the processing functions and returns the list of results.
   local str, expr, sep = simplify_expression(line:sub(1,endpos))
   contextual_list(expr, sep, str)
   return matches
end
