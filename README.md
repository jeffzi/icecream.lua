[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](https://github.com/pre-commit/pre-commit)
[![Busted](https://github.com/jeffzi/icecream.lua/actions/workflows/busted.yml/badge.svg)](https://github.com/jeffzi/icecream.lua/actions/workflows/busted.yml)
[![Luacheck](https://github.com/jeffzi/icecream.lua/actions/workflows/luacheck.yml/badge.svg)](https://github.com/jeffzi/icecream.lua/actions/workflows/luacheck.yml)
[![Luarocks](https://img.shields.io/luarocks/v/jeffzi/icecream?label=Luarocks&logo=Lua)](https://luarocks.org/modules/jeffzi/icecream)

# icecream.lua

`icecream.lua`, a port of the debugging utility [IceCream](https://github.com/gruns/icecream),
enhances print debugging by providing more informative and visually appealing output.

Use `ic()` just like you would use `print()` for debugging:

```lua
local ic = require("icecream")

local foo = function()
   local x = 42
   ic("bar", x, math.abs(-9), {
      greetings = "hello",
      __call = function(self)
         print(self.greetings)
      end,
   })
end

foo()
```

Output:

![](demo.png)

## Installation

### [LuaRocks](https://luarocks.org/)

```shell
luarocks install luamark
```

### Manual Installation

`icecream.lua` is a single file that can be easily integrated into your project.
Download icecream.lua and include it in your project directory.

Ensure that optional dependencies are available for extra features:

- **[dumbParser](https://github.com/ReFreezed/DumbLuaParser/blob/master/dumbParser.lua):** Introspecting expressions and variable names. e.g: `ic| x = 42`
- **[ansicolors](https://github.com/kikito/ansicolors.lua):** Enabling colored output.
- **[inspect](https://github.com/kikito/inspect.lua):** Pretty-printing tables.
- **[luasystem](https://github.com/lunarmodules/luasystem):** Terminal width detection and consistent environment variable reading on Windows.

## Usage

1. **Import IceCream:**

   ```lua
   local ic = require("icecream")
   ```

Assign the result of require to a variable named `ic` to increase robustness when introspecting.

2. **Debugging with `ic()`:**

   Use `ic()` as you would use `print()` for debugging:

   ```lua
    local ic = require("icecream")

    local foo = function()
       local x = -42
       ic(math.abs(x))
    end

    foo()
    -- Output: ic| readme.lua:5 <foo>: math.abs(x) = 42
   ```

<img src="basic_example.png" width="400">

3. **Output format**:

- **Inspection:** `ic()` inspects itself and prints both its arguments and their values.

- **Context**: Each output includes the file, line number, and function.

- **Color:** The output features highlighting.

- **Multi-lines:**: The output wraps on new lines as needed.

- **Stack traceback:** Without arguments, `ic()` prints the stack traceback.

```lua
local ic = require("icecream")

local function foo()
   ic()
end

foo()
-- Output:
-- ic| readme.lua:4 <foo>:
-- stack traceback:
-- 	    readme.lua:4: in function 'foo'
-- 	    readme.lua:7: in main chunk
-- 	    [C]: ?
```

IceCream supports [`StackTracePlus`](https://github.com/ignacio/StackTracePlus).
With StackTracePlus, the previous snippet outputs:

```
ic| readme.lua:4 <foo>
Stack Traceback
===============
(3) Lua local 'foo' at file 'readme.lua:4'
	Local variables:
	 x = number: 1
	 y = number: 2
(4) main chunk of file 'readme.lua' at line 7
(5)  C function 'function: 0x600001aec0c0'
```

## Returning the arguments

`ic()` returns its arguments, so you can easily insert it into pre-existing code.

```lua
local ic = require("icecream")

local x, y = ic(1, 2)
assert(x == 1)
assert(y == 2)

local t = { "hello" }
assert(t == ic(t))
```

## Customize

IceCream allows customization of its output behavior:

```lua
ic.color = false                     -- Disable colorized output.
ic.max_width = 100                   -- Wrap text if longer than 100 characters.
ic.indent = "    "                   -- Indent with 4 spaces.
ic.prefix = "DEBUG"                  -- Change the prefix from 'ic|' to 'DEBUG'.
ic.include_context = false           -- Disable file name, line number, and function name output.
ic.traceback = function() end        -- Custom traceback function (can be nil), defaults to debug.traceback.
ic.output_function = function() end  -- Custom output function, e.g., write to a file.
```

When the following environment variables are present and not empty strings:

- [`NO_COLOR`](https://no-color.org/): Prevents ANSI color when present.
- `NO_ICECREAM`: Disables ic outputs permanently if not an empty string

## Usage without `require`

To make `ic()` available globally, without require, use the `ic:export()` method.

The [`LUA_INIT`](https://www.lua.org/manual/5.1/lua.html) environment variable allows invocation of
`ic:export()` when Lua starts, ensuring global availability of `ic`.

For example, add this to your `.bashrc`:

```bash
export LUA_INIT="local ok, ic = pcall(require, 'icecream'); if ok and ic.export then ic:export() end"
```

## Activate/deactivate dynamically

Activate or deactivate debugging output dynamically with `ic.enable()` and `ic.disable()`. Set the environment variable `NO_ICECREAM` to disable outputs permanently.

## ic:format()

`ic:format()` works like ic() but returns a string instead of printing the output.

## Limitations

IceCream relies on `debug.getinfo`, which provides partial information about function calls, resulting in some limitations:

- **Naming Convention:** Assign the result of require to a variable named ic for robustness. While not mandatory, `ic` might not detect nested calls otherwise.

  ```lua
  local dbg = require("icecream")

  dbg.include_context = false
  -- ic| { hello = "world" }
  dbg({ hello = "world" })
  -- ic| dbg({hello="world"}) = { hello = "world" }
  tostring(dbg({ hello = "world" }))
  ```

- **Single Call Limitation:** `ic` only supports one `ic:format()` or `ic()` per line of code.

  ```lua
    local ic = require("icecream")

    assert(ic(1) == ic(2, 3))-- Error: Failed to parse arguments from source

  ```

- **Return Value Restriction:** In _Lua 5.1_, `ic:format()` or `ic()` can't be directly used as return values from functions.

  ```lua
  local ic = require("icecream")

  local function greetings(name)
     return ic("hello", name)
  end
  local hello, name = greetings("Jeff")  -- Error: Cannot use IceCream as a return value
  ```

## License

`icecream.lua` has the MIT License. See [LICENSE](LICENSE) for more information.

## Acknowledgments

This project is a port of the original [IceCream](https://github.com/gruns/icecream) by [gruns](https://github.com/gruns).
