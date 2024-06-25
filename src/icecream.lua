---@class IceCream
local IceCream = {
   _VERSION = "0.5.0",
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

local getinfo = debug.getinfo
local gsub = string.gsub
local match = string.match
local stderr = io.stderr
local tconcat = table.concat
local tinsert = table.insert

local has_parser, parser = pcall(require, "dumbParser")
local toLua, parse, traverseTree
if has_parser then
   toLua, parse, traverseTree = parser.toLua, parser.parse, parser.traverseTree
end

local has_stack_trace_plus, stp = pcall(require, "StackTracePlus")
local traceback = has_stack_trace_plus and stp.stacktrace or debug.traceback

stderr:setvbuf("no")

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------
-- region Config

local config = {
   enabled = false, -- IceCream:enable() will turn this on later if NO_ICECREAM is not set.
   indent = "  ",
   color = true,
   include_context = true,
   prefix = "ic|",
   traceback = traceback,
   output_function = function(s)
      stderr:write(s)
   end,
}

local get_env, get_termsize
do
   local default_termsize = function()
      return config.max_width or 80
   end

   local has_sys, sys = pcall(require, "system")

   if not has_sys then
      get_env = os.getenv
      get_termsize = default_termsize
   else
      get_env = sys.getenv or os.getenv -- get_env added to luasystem v0.3.0
      local termsize = sys.termsize
      -- termsize added to luasystem v0.4.0
      -- termize can return "Failed to get terminal size.: Inappropriate ioctl for device"
      if termsize and select(2, termsize()) == "number" then
         get_termsize = function()
            local max_width = config.max_width
            if max_width then
               return max_width
            end
            local _, cols = termsize()
            print(cols)
            return cols
         end
      else
         get_termsize = default_termsize
      end
   end
end

---@param varname string
---@return boolean
local function is_env_set(varname)
   local value = get_env(varname)
   return value ~= nil and value ~= ""
end

-- endregion

-------------------------------------------------------------------------------
-- Formatting
-------------------------------------------------------------------------------
-- region Formatting

do
   if is_env_set("NO_COLOR") then
      config.color = false
   end

   local has_ansicolors, ansicolors = pcall(require, "ansicolors")

   ---@param color string
   ---@return fun(s: string): string
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
      if config.color and not has_ansicolors then
         config.color = false
      end

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
      inspect = {}
      setmetatable(inspect, {
         __call = function(_, value)
            return tostring(value)
         end,
      })
   end
end

local INSPECT_KEY = inspect.KEY
---@param item string
---@param path string[]
---@return string
local function tag_key(item, path)
   if type(item) ~= "number" and path[#path] == INSPECT_KEY and not match(item, "^__") then
      return "@" .. item .. "@"
   end
   return item
end

---@param s string
local function should_wrap(s)
   return #gsub(s, "\27%[%d+m", "") > get_termsize()
end

---@param s string
---@param process? function
local function wrap_table(s, process)
   local original = s
   local options = { newline = " ", indent = "" }
   options.process = process
   ---@diagnostic disable-next-line: redundant-parameter
   s = inspect(original, options)
   if #s <= get_termsize() then
      return s
   end

   local indent = config.indent
   options.indent = indent
   options.newline = "\n" .. indent
   ---@diagnostic disable-next-line: redundant-parameter
   s = inspect(original, options)
   -- indent opening bracket
   s = gsub(s, "{", "{\n" .. indent .. " ", 1)
   -- remove empty lines
   s = gsub(s, "\n%s*\n", "\n")
   return s
end

---@param s any
---@return string
function IceCream:_prettify(s)
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
   if not config.color then
      return wrap_table(s)
   end

   s = wrap_table(s, tag_key)
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
   s = string.gsub(s, "(%f[%a]false%f[%A])", function(bool)
      return self.format_boolean(bool)
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
   if filename == "(tail call)" then
      error("Cannot use IceCream as a return value")
   end

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
   local aliases
   local call_count = 0
   local n = 0

   traverseTree(ast, function(node)
      if node.type == "call" and node.token.lineStart == relative_line then
         call_count = call_count + 1

         local callee = node.callee
         local object = callee.object
         local name = object and object.name or callee.name
         if name ~= "ic" and call_count > 1 then
            return
         end

         local node_arguments = node.arguments
         n = #node_arguments
         aliases = {}
         for i = 1, n do
            local expr = node_arguments[i]
            local expr_type = expr.type
            if expr_type == "identifier" or expr_type == "call" then
               aliases[i] = toLua(expr)
            end
         end

         if name == "ic" then
            return "stop"
         end
      end
   end)

   return aliases, n
end

-- endregion

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
-- region public

---@vararg any
---@return string
function IceCream:_format(level, ...)
   local info = getinfo(level, "Sln")
   if info.namewhat == "[C]" then
      info = getinfo(level + 1, "Sln")
   end

   local prefix = config.prefix

   local short_src = info.short_src
   local has_source = short_src ~= "stdin" and short_src ~= "(command line)"

   local location = ""
   if config.include_context and has_source then
      location = short_src .. ":" .. info.currentline

      local fn_name = info.name
      if fn_name then
         location = location .. " <" .. fn_name .. ">"
      end
      location = location .. ":"
   end

   local header
   if prefix == "" or location == "" then
      header = prefix .. location
   else
      header = prefix .. " " .. location
   end
   header = self.format_header(header)

   local arg_count = select("#", ...)
   if arg_count == 0 then
      if config.traceback then
         return header .. " " .. (config.traceback("", 3) or "")
      end
      return header
   end

   local should_parse = has_parser and has_source
   local keys, key_count
   if should_parse then
      keys, key_count = parse_aliases(info)
      if not "keys" or key_count ~= select("#", ...) then
         error("Failed to parse arguments from source " .. location)
      end
   else
      key_count = select("#", ...)
   end

   local pretty_args = {}
   for i = 1, key_count do
      ---@cast keys string[]
      local key = should_parse and keys[i] or nil
      local value = select(i, ...)

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
   else
      header = header .. " "
   end

   return header .. output
end

local FORMAT_LEVEL = (_VERSION == "Lua 5.1" and not jit) and 3 or 2

--- Format its arguments for debugging purposes.
---@vararg any Argument(s) to format
---@return string
function IceCream:format(...)
   return self:_format(FORMAT_LEVEL, ...)
end

--- Quick print function for debugging purposes.
---@vararg any Argument(s) to print
---@return ... The argument(s) passed to ic
function IceCream:ic(...)
   if config.enabled then
      local output = self:_format(3, ...)
      config.output_function(output .. "\n")
   end
   return ...
end

--- Enable IceCream debugging output, if environment variable NO_ICECREAM is not set.
function IceCream:enable()
   if not is_env_set("NO_ICECREAM") then
      config.enabled = true
   end
end

--- Disable IceCream debugging output.
function IceCream:disable()
   config.enabled = false
end

function IceCream:export()
   _G.ic = self
end

local mt = {
   __index = function(_, k)
      return config[k]
   end,
   __newindex = function(_, k, v)
      if k ~= "max_width" and k ~= "traceback" then
         if config[k] == nil then
            error(k .. " is not a valid config option.")
         end

         if v == nil then
            error(k .. " option cannot be set to nil.")
         end
      end

      config[k] = v

      if k == "color" then
         IceCream:_configure_color()
      end
   end,
   __call = IceCream.ic,
}

IceCream:_configure_color()
IceCream:enable()

-- endregion

return setmetatable(IceCream, mt)
