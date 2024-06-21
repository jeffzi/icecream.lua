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

local getinfo = debug.getinfo
local gsub = string.gsub
local match = string.match
local stderr = io.stderr
local tconcat = table.concat
local tinsert = table.insert
local traceback = debug.traceback

stderr:setvbuf("no")

-------------------------------------------------------------------------------
-- Formatting
-------------------------------------------------------------------------------
-- region Formatting

local colorizer, format_key, format_header
do
   local has_inspect, inspect = pcall(require, "inspect")
   if not has_inspect then
      inspect = function(value)
         return value
      end
   end

   IceCream.color = true
   local nocolor = os.getenv("NO_COLOR")
   if nocolor and nocolor ~= "" then
      IceCream.color = false
   end

   local has_ansicolors, ansicolors = pcall(require, "ansicolors")
   local colorize
   if has_ansicolors then
      function colorize(s, color)
         return ansicolors("%{" .. color .. "}" .. s .. "%{reset}")
      end
   else
      function colorize(s, _)
         return s
      end
   end

   function colorizer(color)
      return function(s)
         return colorize(s, color)
      end
   end

   format_key = colorizer("blue")
   format_header = colorizer("underline white")

   local format_bracketed = colorizer("cyan")
   local format_number = colorizer("magenta")
   local format_boolean = colorizer("yellow")
   local format_misc = colorizer("cyan")
   local format_string = colorizer("green")
   local format_bracket = colorizer("bright white")

   local INSPECT_KEY = inspect.KEY
   local function tag_key(item, path)
      if type(item) ~= "number" and path[#path] == INSPECT_KEY and not match(item, "^__") then
         return "@" .. item .. "@"
      end
      return item
   end

   function IceCream:format(s)
      if not self.color then
         return inspect(s)
      end

      local type_ = type(s)
      if type_ == "string" then
         return format_string('"' .. s .. '"')
      elseif type_ == "number" then
         return format_number(s)
      elseif type_ == "boolean" then
         return format_boolean(tostring(s))
      elseif type_ ~= "table" then
         return format_misc(inspect(s))
      end

      -- Formatting a table
      s = inspect(s, { process = tag_key })
      s = gsub(s, '%["@(.-)@"%]', format_key)
      s = gsub(s, '%b""', format_string)
      s = gsub(s, "%b''", format_string)
      s = gsub(s, "%b<>", format_bracketed)
      s = gsub(s, "(-?%d*%.?%d+)(%s*[,%}\n])", function(num, post)
         return format_number(num) .. post
      end)
      s = gsub(s, "inf,", format_number)
      s = gsub(s, "(=%s*)(true)", function(pre, bool)
         return pre .. format_boolean(bool)
      end)
      s = gsub(s, "(=%s*)(false)", function(pre, bool)
         return pre .. format_boolean(bool)
      end)
      s = gsub(s, "(__[a-z]+)(%s*=)", function(fn, pre)
         -- format metamethod
         return format_misc(fn) .. pre
      end)
      s = gsub(s, "([{}])", format_bracket)

      return s
   end
end

-- endregion

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

---@param s string
local function output_fn(s)
   stderr:write(s)
end

--- Split the arguments string into a table of arguments.
--- Does not handle square-bracketed strings.
---@param info table
---@return string[]?, integer
local function parse_aliases(info)
   local source = read_source(info)
   local relative_line = info.currentline - info.linedefined + 1

   local ast = parse(source)

   local aliases = {}
   local n = 0
   traverseTree(ast, function(node)
      if node.type == "call" and node.token.lineStart == relative_line then
         local node_arguments = node.arguments
         n = #node_arguments
         for i = 1, n do
            local expr = node_arguments[i]
            local expr_type = expr.type
            if expr_type == "identifier" or expr_type == "call" then
               aliases[i] = toLua(expr)
            end
         end
         return "stop"
      end
   end)

   return n > 0 and aliases or nil, n
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
   local location = info.short_src .. ":" .. info.currentline

   local fn_name = info.name
   local header = "[" .. location .. "]"
   if fn_name then
      header = format_header(header .. "(" .. fn_name .. ")")
   else
      header = format_header(header)
   end

   local arg_count = select("#", ...)
   if arg_count == 0 then
      output_fn(traceback())
      output_fn("\n")
      return ...
   end

   local keys, key_count = parse_aliases(info)
   if not "keys" or key_count ~= select("#", ...) then
      error("Failed to parse arguments from source @" .. location)
   end

   local pretty_args = {}
   for i = 1, key_count do
      ---@cast keys string[]
      local key, value = keys[i], select(i, ...)

      if not key or key == tostring(value) then
         key = ""
      else
         key = format_key(key) .. " = "
      end

      pretty_args[i] = key .. self:format(value)
   end

   output_fn(header .. " " .. tconcat(pretty_args, ", "))
   output_fn("\n")
   return ...
end

-- endregion

return setmetatable(IceCream, { __call = IceCream.ic })
