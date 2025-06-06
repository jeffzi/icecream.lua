-- IceCream — Never use print() to debug again. A Lua port of the Python IceCream library.
-- Copyright (c) 2025 Jean-Francois Zinque
-- Licensed under the MIT License

---@class IceCream
---@field enabled boolean Enable or disable IceCream output globally. Can be toggled with enable() and disable()
---@field color boolean Enable ANSI color codes in output. When true, different data types are highlighted in distinct colors
---@field include_context boolean Include source information (file name, line number, function name) in output.
---@field prefix string? Prefix string added before each debug output line. Defaults to "ic|"
---@field max_width integer? Maximum width in characters before wrapping output text. If nil, uses terminal width.
---@field indent string Indentation string used for wrapped or multi-line output. Defaults to two spaces
---@field traceback function? Custom traceback function to use when ic() is called without arguments. Defaults to debug.traceback or StackTracePlus if available
---@field output_function function Function used to output debug information. Defaults to writing to stderr.
---@field _VERSION string IceCream version number
local IceCream = {
   _VERSION = "0.5.3",
}

local debug_getinfo = debug.getinfo
local io_stderr = io.stderr
local math_huge = math.huge
local string_gsub = string.gsub
local string_match = string.match
local table_concat = table.concat
local pcall, setmetatable, select, type, tostring = pcall, setmetatable, select, type, tostring

local has_parser, parser = pcall(require, "dumbParser")
local toLua, parse, traverseTree
if has_parser then
   toLua, parse, traverseTree = parser.toLua, parser.parse, parser.traverseTree
end

local has_stack_trace_plus, stp = pcall(require, "StackTracePlus")
local traceback = has_stack_trace_plus and stp.stacktrace or debug.traceback

-- stderr is unbuffered so messages appear immediately in REPL
io_stderr:setvbuf("no")

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------

local config = {
   enabled = false,
   indent = "  ",
   color = true,
   include_context = true,
   prefix = "ic|",
   traceback = traceback,
   max_width = 80,
   output_function = function(s)
      io_stderr:write(s .. "\n")
   end,
}

local function default_termsize()
   return config.max_width or 80
end

local get_env = os.getenv
local get_termsize = default_termsize

local has_sys, sys = pcall(require, "system")
if has_sys then
   get_env = sys.getenv
   local termsize = sys.termsize
   if type(select(2, termsize())) == "number" then
      get_termsize = function()
         return config.max_width or select(2, termsize())
      end
   end
end

---@param varname string
---@return boolean
local function is_env_set(varname)
   local value = get_env(varname)
   return value ~= nil and value ~= ""
end

-------------------------------------------------------------------------------
-- Formatting
-------------------------------------------------------------------------------

local format_boolean, format_bracket, format_header, format_key
local format_misc, format_number, format_address, format_string
local color_patterns

local has_ansicolors, ansicolors = pcall(require, "ansicolors")

local function setup_color()
   local use_color = config.color and not is_env_set("NO_COLOR") and has_ansicolors
   config.color = use_color

   local colorizer
   if use_color then
      colorizer = function(color_name)
         local color_code = "%{" .. color_name .. "}"
         return function(s)
            return ansicolors(color_code .. s .. "%{reset}")
         end
      end
   else
      local identity = function(s)
         return s
      end
      colorizer = function()
         return identity
      end
   end

   format_boolean = colorizer("yellow")
   format_bracket = colorizer("bright white")
   format_header = colorizer("underline white")
   format_key = colorizer("blue")
   format_misc = colorizer("cyan")
   format_number = colorizer("magenta")
   format_address = colorizer("underline magenta")
   format_string = colorizer("green")

   color_patterns = {
      { '%["@(.-)@"%]', format_key },
      {
         "(%[%d*%])(%s=)",
         function(index, post)
            return format_key(index) .. post
         end,
      },
      { '%b""', format_string },
      { "%b''", format_string },
      { "cdata%b<>", format_misc },
      { "ctype%b<>", format_misc },
      { "%b<>", format_misc },
      {
         "(%s+-?%d*%.?%d+)(%s?[,%}\n]+)",
         function(num, post)
            return format_number(num) .. post
         end,
      },
      {
         "(0x%x+)([%s,%}\n]+)",
         function(hex, post)
            return format_address(hex) .. post
         end,
      },
      { "inf,", format_number },
      {
         "(=%s*)(true)",
         function(pre, bool)
            return pre .. format_boolean(bool)
         end,
      },
      { "(%f[%a]false%f[%A])", format_boolean },
      {
         "(__[a-z]+)(%s*=)",
         function(fn, pre)
            return format_misc(fn) .. pre
         end,
      },
      { "([{}])", format_bracket },
   }
end

local inspect
do
   local has_inspect
   has_inspect, inspect = pcall(require, "inspect")
   if not has_inspect then
      inspect = setmetatable({}, {
         __call = function(_, value)
            return tostring(value)
         end,
      })
   end
end

local INSPECT_KEY = inspect.KEY

--- Tag table keys for formatting.
---@param item string
---@param path string[]
---@return string
local function tag_key(item, path)
   if type(item) ~= "number" and path[#path] == INSPECT_KEY and not string_match(item, "^__") then
      return "@" .. item .. "@"
   end
   return item
end

local function should_wrap(s)
   return #string_gsub(s, "\27%[%d+m", "") > get_termsize()
end

---@param s string
---@param process? function
local function wrap_table(s, process)
   local original = s
   local options = { newline = " ", indent = "", process = process }

   s = inspect(original, options)
   if #s <= get_termsize() then
      return s
   end

   local indent = config.indent
   options.indent = indent
   options.newline = "\n" .. indent
   s = inspect(original, options)
   s = string_gsub(s, "{", "{\n" .. indent .. " ", 1)
   s = string_gsub(s, "\n%s*\n", "\n")
   return s
end

local function format_table(s)
   for i = 1, #color_patterns do
      local pattern, replacement = color_patterns[i][1], color_patterns[i][2]
      s = string_gsub(s, pattern, replacement)
   end
   return s
end

---@param s any
---@return string
function IceCream:_prettify(s)
   local value_type = type(s)

   if value_type == "string" then
      return format_string('"' .. s .. '"')
   elseif value_type == "number" then
      return format_number(s)
   elseif value_type == "boolean" then
      return format_boolean(tostring(s))
   elseif value_type ~= "table" then
      return format_misc(inspect(s))
   end

   -- Handle table formatting
   if not config.color then
      return wrap_table(s)
   end

   return format_table(wrap_table(s, tag_key))
end

-------------------------------------------------------------------------------
-- Parse source
-------------------------------------------------------------------------------

---@type {[string]: {[integer]: string}}
local source_cache = setmetatable({}, { __mode = "kv" })

-- Track the number of ic() calls per line
---@type {[string]: integer}
local current_line_calls = setmetatable({}, { __mode = "k" })

-- Cache parsed aliases per line
---@type {[string]: {[integer]: string[]}}
local aliases_cache = setmetatable({}, { __mode = "k" })

--- Read source code from file with caching.
---@param info table
---@return string
local function read_source(info)
   local filename = info.source:sub(2)
   if filename == "(tail call)" then
      error("Cannot use IceCream as a return value")
   end

   local start_line = info.linedefined
   local end_line = info.lastlinedefined

   if start_line == 0 then
      start_line = info.currentline
      end_line = math_huge
   end

   local cached_file = source_cache[filename]
   if cached_file then
      local cached_function = cached_file[start_line]
      if cached_function then
         return cached_function
      end
   else
      cached_file = {}
      source_cache[filename] = cached_file
   end

   local lines = {}
   local i = 0
   for line in io.lines(filename) do
      i = i + 1
      if i >= start_line and i <= end_line then
         lines[#lines + 1] = line
      end
   end

   local source = table_concat(lines, "\n")
   cached_file[start_line] = source
   return source
end

--- Parse function call arguments to extract variable names.
---@param info table debug info table with source and line information
---@return {[integer]: string[]}? table Mapping call number to an array of argument aliases
local function parse_aliases(info)
   local cache_key = info.source .. ":" .. info.currentline
   local cached = aliases_cache[cache_key]
   if cached then
      return cached
   end

   local source = read_source(info)
   local linedefined = info.linedefined
   local relative_line = linedefined > 0 and info.currentline - linedefined + 1 or 1

   local ast, err = parse(source)

   if err then
      IceCream.output_function("Failed to parse IceCream arguments: " .. err)
      return nil
   end

   local calls = {}
   local call_count = 0

   traverseTree(ast, function(node)
      if node.type ~= "call" or node.token.lineStart ~= relative_line then
         return
      end

      local callee = node.callee
      local object = callee.object
      local name = object and object.name or callee.name

      if name == "ic" then
         call_count = call_count + 1
         local node_arguments = node.arguments
         local aliases = {}

         for i = 1, #node_arguments do
            local expr = node_arguments[i]
            local expr_type = expr.type
            if expr_type ~= "literal" and expr_type ~= "function" and expr_type ~= "table" then
               aliases[i] = toLua(expr)
            end
         end

         calls[call_count] = aliases
      end
   end)

   aliases_cache[cache_key] = calls
   return calls
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Internal function that formats the output for the icecream debug statement.
--- @param level number Stack level for tracing the caller (2 for direct calls, 3 for ic() calls)
--- @param call_number number Sequential number of ic() call on the current line (for handling multiple calls)
--- @param ... any Variable arguments to be formatted and displayed (supports all Lua types)
--- @return string The fully formatted debug string including context, argument names, and pretty-printed values
function IceCream:_format(level, call_number, ...)
   local info = debug_getinfo(level, "Sln")
   if info.namewhat == "[C]" then
      info = debug_getinfo(level + 1, "Sln")
   end

   local prefix = config.prefix or ""
   local short_src = info.short_src
   local has_source = short_src ~= "stdin" and short_src ~= "(command line)"

   local location = ""
   if config.include_context and has_source then
      location = short_src .. ":" .. info.currentline
      if info.name then
         location = location .. " <" .. info.name .. ">"
      end
      location = location .. ":"
   end

   local header
   if prefix == "" or location == "" then
      header = prefix .. location
   else
      header = prefix .. " " .. location
   end
   header = format_header(header)

   local arg_count = select("#", ...)
   if arg_count == 0 then
      if config.traceback then
         return header .. " " .. (config.traceback("", 3) or "")
      end
      return header
   end

   local should_parse = has_parser and has_source
   local keys = {}
   if should_parse then
      local ok, parsed_calls = pcall(parse_aliases, info)
      if ok and parsed_calls and parsed_calls[call_number] then
         keys = parsed_calls[call_number]
      end
   end

   local pretty_args = {}
   for i = 1, arg_count do
      local key = keys[i]
      local value = select(i, ...)

      if not key or key == tostring(value) then
         key = ""
      else
         key = format_key(key) .. " = "
      end

      pretty_args[i] = key .. self:_prettify(value)
   end

   local output = table_concat(pretty_args, ", ")
   if should_wrap(output) then
      local sep = "\n" .. config.indent
      output = sep .. table_concat(pretty_args, sep)
   else
      header = header .. " "
   end

   return header .. output
end

local FORMAT_LEVEL = (_VERSION == "Lua 5.1" and not jit) and 3 or 2

--- Format arguments for debugging without printing.
---
--- Example:
--- ```lua
--- local ic = require("icecream")
--- local dbg_info = ic:format(my_table, my_function, "test")
--- ```
---@param ... any Values to debug print.
---@return string Formatted
function IceCream:format(...)
   -- For format(), always use call_number 1 since it's used directly
   return self:_format(FORMAT_LEVEL, 1, ...)
end

--- Enhanced debug function that pretty-prints variable names and values with syntax highlighting.
--- Shows call stack when called without arguments. Returns all arguments unchanged for use in expressions.
---
--- Example:
--- ```lua
--- local ic = require("icecream")
--- local t = { x = 1, y = 2 }
--- local result = ic(t, 42, "test") -- Prints ic| test.lua:3: t = { x = 1, y = 2 }, 42, "test"
--- if ic(t.x == 1) then
---    -- code
--- end
--- ic() -- Prints ic| test.lua:7: + stacktrace
--- ```
---@param ... any Values to debug print.
---@return ... The argument(s) passed to ic, allowing ic() to be used in expressions
function IceCream:ic(...)
   if config.enabled then
      -- Get or initialize call counter for this line
      local info = debug.getinfo(2, "Sl")
      local line_key = info.source .. ":" .. info.currentline
      current_line_calls[line_key] = (current_line_calls[line_key] or 0) + 1
      local call_number = current_line_calls[line_key]

      local output = self:_format(3, call_number, ...)
      config.output_function(output)
   end
   return ...
end

--- Enable IceCream debugging output.
--- Has no effect if the NO_ICECREAM environment variable is set.
function IceCream:enable()
   if not is_env_set("NO_ICECREAM") then
      config.enabled = true
   end
end

--- Disable IceCream debugging output.
--- When disabled, ic() calls will silently return their arguments without printing anything.
function IceCream:disable()
   config.enabled = false
end

--- Make ic() available globally without requiring explicit import.
function IceCream:export()
   _G.ic = self
end

local mt = {
   __index = config,
   __newindex = function(_, k, v)
      if k ~= "max_width" and k ~= "traceback" and k ~= "prefix" then
         if config[k] == nil then
            error(k .. " is not a valid config option.")
         end

         if v == nil then
            error(k .. " option cannot be set to nil.")
         end
      end

      config[k] = v

      if k == "color" then
         setup_color()
      end
   end,
   __call = IceCream.ic,
}

-- Initialize
setup_color()
IceCream:enable()

return setmetatable(IceCream, mt)
