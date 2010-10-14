-- This function is called back by C function do_completion, itself called
-- back by readline library, in order to complete the current input line.
function completion(word, line, startpos, endpos)
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

   -- This function makes a guess of the next character following an identifier,
   -- based on the type of the value it holds.
   local function postfix(value)
      local t = type(value)
      if t == 'function' or (getmetatable(value) or {}).__call then
	 return '('
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
	 add(k..' ')
      end
      for k,v in pairs(_G) do
	 add(k..postfix(v))
      end
   end

   -- Main completion function. It evaluates the current sub-expression
   -- to determine its type. Currently supports tables fields, global
   -- variables and function prototype completion.
   local function contextual_list(expr, sep, str)
      if str then return filename_list(str) end
      if expr == nil or expr == "" then return add_globals() end
      local v = loadstring("return "..expr)
      if not v then return end
      v = v()
      local t = type(v)
      if sep == '.' then
	 if t ~= 'table' then return end
	 for k,v2 in pairs(v) do
	    if type(k) == 'string' then
	       add(k..postfix(v2))
	    end
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
	 add("function "..expr.." (...)"..string.rep(" ", 40))
	 add("°") -- display trick
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
      return curstring,expr:match("([%.%w%[%]_]-)([%.%[%(])"..word.."$")
   end

   -- Now calls the processing functions and returns the list of results.
   local str, expr, sep = simplify_expression(line:sub(1,endpos))
   contextual_list(expr, sep, str)
   return matches
end
