---@class IceCream
local IceCream = {
   _VERSION = "0.1.0",
   _DESCRIPTION = [[
      IceCream — Never use print() to debug again. A Lua port of the Python IceCream library."
   ]],
   _LICENCE = [[
      MIT License

      Copyright (c) 2024 Jean-Francois Zinque

      Permission is hereby granted, free of charge, to any person obtaining a copy
      of this software and associated documentation files (the "Software"), to deal
      in the Software without restriction, including without limitation the rights
      to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
      copies of the Software, and to permit persons to whom the Software is
      furnished to do so, subject to the following conditions:

      The above copyright notice and this permission notice shall be included in all
      copies or substantial portions of the Software.

      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
      IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
      FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
      AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
      LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
      OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
      SOFTWARE.
   ]],
}

local parser = require("dumbParser")
local toLua, parse, traverseTree = parser.toLua, parser.parse, parser.traverseTree

local format = string.format
local getinfo = debug.getinfo
local stderr = io.stderr
local tconcat = table.concat
local tinsert = table.insert
local traceback = debug.traceback

stderr:setvbuf("no")

-------------------------------------------------------------------------------
-- Parse source
-------------------------------------------------------------------------------
-- region Parse source

---@type {[string]: {[integer]: string}}
local cache = {}
setmetatable(cache, { __mode = "kv" })

---@param info table
---@return string
local function read_source(info)
   local filename = info.source:sub(2) -- Remove the '@' prefix
   local start_line = info.linedefined
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

--- Split the arguments string into a table of arguments.
--- Does not handle square-bracketed strings.
---@param info table
---@return string[]?, integer
local function parse_args(info)
   local source = read_source(info)
   local relative_line = info.currentline - info.linedefined + 1

   local ast = parse(source)

   local args = {}
   local arg_count = 0
   traverseTree(ast, function(node)
      if node.type == "call" and node.token.lineStart == relative_line then
         for _, arg in ipairs(node.arguments) do
            arg_count = arg_count + 1
            tinsert(args, toLua(arg))
         end
         return "stop"
      end
   end)

   return arg_count > 0 and args or nil, arg_count
end

-- endregion

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
-- region public

--- Quick print function for debugging purposes.
---@vararg any Argument(s) to print
---@return ... The argument(s) passed to ic
function IceCream:ic(...)
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

   local keys, key_count = parse_args(info)
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

      pretty_args[i] = format("%s%s", key, self:format_value(value))
   end

   printf("%s: %s", header, tconcat(pretty_args, ", "))
   printf("\n")
   return ...
end

-- endregion

return setmetatable(IceCream, { __call = IceCream.ic })
