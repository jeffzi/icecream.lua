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

      The above copyright notice and
      this permission notice shall be included in all
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

local has_stack_trace_plus, stp = pcall(require, "StackTracePlus")
local traceback = has_stack_trace_plus and stp.stacktrace or debug.traceback

stderr:setvbuf("no")

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------
-- region Config

local config = {
   max_width = 80,
   indent = "  ",
   color = true,
   include_context = true,
   prefix = "ic|",
   traceback = traceback,
}

-- endregion

-------------------------------------------------------------------------------
-- Formatting
-------------------------------------------------------------------------------
-- region Formatting

do
   local nocolor = os.getenv("NO_COLOR")
   if nocolor and nocolor ~= "" then
      IceCream.color = false
   end

   local has_ansicolors, ansicolors = pcall(require, "ansicolors")

   local function colorizer(color)
      if has_ansicolors and config.color then
         return function(s)
            return ansicolors("%{" .. color .. "}" .. s .. "%{reset}")
         end
      end
      return function(s)
         return s
      end
   end

   function IceCream:_configure_color()
      IceCream.format_boolean = colorizer("yellow")
      IceCream.format_bracket = colorizer("bright white")
      IceCream.format_header = colorizer("underline white")
      IceCream.format_key = colorizer("blue")
      IceCream.format_misc = colorizer("cyan")
      IceCream.format_number = colorizer("magenta")
      IceCream.format_string = colorizer("green")
   end
end

local inspect
do
   local has_inspect
   has_inspect, inspect = pcall(require, "inspect")
   if not has_inspect then
      inspect = function(value)
         return value
      end
   end
end

local INSPECT_KEY = inspect.KEY
local function tag_key(item, path)
   if type(item) ~= "number" and path[#path] == INSPECT_KEY and not match(item, "^__") then
      return "@" .. item .. "@"
   end
   return item
end

local function should_wrap(s)
   return #gsub(s, "\27%[%d+m", "") > config.max_width
end

local function wrap_table(s, options)
   local indent = config.indent
   options.indent = indent
   options.newline = "\n" .. indent
   ---@diagnostic disable-next-line: redundant-parameter
   s = inspect(s, options)
   -- indent opening bracket
   s = gsub(s, "{", "{\n" .. indent .. " ", 1)
   -- remove empty lines
   s = gsub(s, "\n%s*\n", "\n")
   return s
end

function IceCream:_prettify(s)
   if not self.color then
      return inspect(s)
   end

   local type_ = type(s)
   if type_ == "string" then
      return self.format_string('"' .. s .. '"')
   elseif type_ == "number" then
      return self.format_number(s)
   elseif type_ == "boolean" then
      return self.format_boolean(tostring(s))
   elseif type_ ~= "table" then
      return self.format_misc(inspect(s))
   end

   -- Formatting a table
   local original = s
   local options = { newline = " ", indent = "" }
   options.process = tag_key
   ---@diagnostic disable-next-line: redundant-parameter
   s = inspect(original, options)
   if #s > config.max_width then
      s = wrap_table(original, options)
   end
   s = gsub(s, '%["@(.-)@"%]', self.format_key)
   s = gsub(s, "(%[%d*%])(%s=)", function(index, post)
      return self.format_key(index) .. post
   end)
   s = gsub(s, '%b""', self.format_string)
   s = gsub(s, "%b''", self.format_string)
   s = gsub(s, "%b<>", self.format_misc)
   s = gsub(s, "(-?%d*%.?%d+)(%s*[,%}\n])", function(num, post)
      return self.format_number(num) .. post
   end)
   s = gsub(s, "inf,", self.format_number)
   s = gsub(s, "(=%s*)(true)", function(pre, bool)
      return pre .. self.format_boolean(bool)
   end)
   s = gsub(s, "(=%s*)(false)", function(pre, bool)
      return pre .. self.format_boolean(bool)
   end)
   s = gsub(s, "(__[a-z]+)(%s*=)", function(fn, pre)
      -- format metamethod
      return self.format_misc(fn) .. pre
   end)
   s = gsub(s, "([{}])", self.format_bracket)

   return s
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

   if start_line == 0 then
      -- source is not in a function
      start_line = info.currentline
      end_line = start_line
   end

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

--- Split the arguments string into a table of arguments.
--- Does not handle square-bracketed strings.
---@param info table
---@return string[]?, integer
local function parse_aliases(info)
   local source = read_source(info)

   local linedefined = info.linedefined
   -- relative_line = 1 if source is not in a function
   local relative_line = linedefined > 0 and info.currentline - linedefined + 1 or 1

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

IceCream.output_function = function(s)
   stderr:write(s)
end

function IceCream:_format(...)
   local include_context = config.include_context
   if include_context == nil then
      include_context = true
   end

   local info = getinfo(3, "Sln")

   local location = info.short_src .. ":" .. info.currentline
   local header = config.prefix

   if include_context then
      header = header .. " " .. location
      local fn_name = info.name
      if fn_name then
         header = header .. " <" .. fn_name .. ">"
      else
         header = header .. ":"
      end
   end
   header = self.format_header(header)

   local arg_count = select("#", ...)
   if arg_count == 0 then
      return header .. " " .. (config.traceback("", 3) or "")
   end

   local keys, key_count = parse_aliases(info)
   print(keys, key_count, select("#", ...))
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
         key = self.format_key(key) .. " = "
      end

      pretty_args[i] = key .. self:_prettify(value)
   end

   local output = tconcat(pretty_args, ", ")
   if should_wrap(output) then
      local sep = "\n" .. config.indent
      output = sep .. tconcat(pretty_args, sep)
   end

   return header .. " " .. output
end

--- Format its arguments for debugging purposes.
---@vararg any Argument(s) to format
---@return ... The argument(s) passed to format
function IceCream:format(...)
   return self:_format(...)
end

--- Quick print function for debugging purposes.
---@vararg any Argument(s) to print
---@return ... The argument(s) passed to ic
function IceCream:ic(...)
   if self.enabled then
      local output = self:_format(...)
      self.output_function(output .. "\n")
   end
   return ...
end

do
   local no_icecream = os.getenv("NO_ICECREAM")
   if no_icecream and no_icecream ~= "" then
      IceCream.enabled = false
   else
      IceCream.enabled = true
   end
end

function IceCream:enable()
   self.enabled = true
end

function IceCream:disable()
   self.enabled = false
end

local mt = {
   __index = function(_, k)
      return config[k]
   end,
   __newindex = function(_, k, v)
      if config[k] == nil then
         error(k .. " is not a valid config option.")
      end

      if v == nil then
         error(k .. " option cannot be set to nil.")
      end

      config[k] = v

      if k == "color" then
         IceCream:_configure_color()
      end
   end,
   __call = IceCream.ic,
}

IceCream:_configure_color()

-- endregion

return setmetatable(IceCream, mt)
