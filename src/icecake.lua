local format = string.format
local getinfo = debug.getinfo
local gsub = string.gsub
local match = string.match
local stderr = io.stderr
local sub = string.sub
local tconcat = table.concat
local tinsert = table.insert
local traceback = debug.traceback

---@type {[string]: {[integer]: string}}
local cache = {}
setmetatable(cache, { __mode = "kv" })

---@param info table
---@return string
local function read_source(info)
   local filename = info.source:sub(2) -- Remove the '@' prefix
   local start_line = info.currentline
   local end_line = info.lastlinedefined

   local cached_file = cache[filename]
   if cached_file then
      local cached_function = cached_file[start_line]
      if cached_function then
         return cached_function
      end
   else
      cached_file = {}
      cache[filename] = cached_file
   end

   local lines = {}
   local i = 0
   for line in io.lines(filename) do
      i = i + 1
      if i >= start_line and i <= end_line then
         tinsert(lines, line)
      end
   end

   local source = tconcat(lines, "\n")
   cached_file[start_line] = source
   return source
end

---@param fmt string
---@vararg ...
local function printf(fmt, ...)
   stderr:write(format(fmt, ...))
end

---@param s string
---@return string
local function trim(s)
   s = match(s, "^%s*(.*%S)") or "" -- trim spaces
   s = gsub(s, "^([%[%[\"'])(.-)%1$", "%2") -- trim quotes
   return s
end

--- Split the arguments string into a table of arguments.
--- Does not handle square-bracketed strings.
---@param source string
---@return string[]?, integer
local function parse_args(source)
   -- strip everything up to first argument
   source = gsub(source, "^[^(]*%(", "")

   local size = #source
   local args, arg_count = {}, 0
   local current_arg = {}
   local char_count = 0
   local level, in_string = 0, false

   for i = 1, size do
      local char = sub(source, i, i)

      if level == 0 and not in_string and (char == "," or char == ")") then
         arg_count = arg_count + 1
         args[arg_count] = trim(tconcat(current_arg))
         current_arg = {}
         char_count = 0

         if char == ")" then
            break
         end
      else
         char_count = char_count + 1
         current_arg[char_count] = char

         if char == '"' or char == "'" then
            in_string = not in_string
         elseif not in_string then
            if char == "(" then
               level = level + 1
            elseif char == ")" then
               level = level - 1
            end
         end
      end
   end

   if char_count > 0 then
      arg_count = arg_count + 1
      args[arg_count] = trim(tconcat(current_arg))
   end

   return arg_count > 0 and args or nil, arg_count
end

--- Quick print function for debugging purposes.
---@vararg any Argument(s) to print
---@return ... The argument(s) passed to ic
local function ic(...)
   local info = getinfo(2, "Sln")
   local location = format("%s:%s", info.short_src, info.currentline)

   local fun_name = info.name
   local header = fun_name and format("[%s](%s)", location, fun_name) or location

   local arg_count = select("#", ...)
   if arg_count == 0 then
      printf(traceback())
      printf("\n")
      return ...
   end

   local source = read_source(info)
   local keys, key_count = parse_args(source)

   if not "keys" or key_count ~= select("#", ...) then
      error(format("Failed to parse arguments from source @%s", location))
   end

   local pretty_args = {}
   for i = 1, key_count do
      ---@cast keys string[]
      local arg = keys[i]
      local value = select(i, ...)

      local key
      if arg == tostring(value) then
         key = ""
      else
         key = format("%s = ", arg)
      end

      pretty_args[i] = format("%s%s", key, value)
   end

   printf("%s: %s", header, tconcat(pretty_args, ", "))
   printf("\n")
   return ...
end

return ic
