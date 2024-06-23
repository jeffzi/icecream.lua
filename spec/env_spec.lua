local sys = require("system")
local function require_uncached(module_name)
   package.loaded[module_name] = nil
   return require(module_name)
end

describe("environment", function()
   before_each(function()
      sys.setenv("NO_COLOR", nil)
      sys.setenv("NO_ICECREAM", nil)
   end)

   it("NO_COLOR", function()
      sys.setenv("NO_COLOR", 1)
      local ic = require_uncached("icecream")

      assert.is_false(ic.color)
      assert.string_match(ic:format("hello"), '^ic| spec/env_spec%.lua:%d+: "hello"$')
   end)

   it("NO_ICECREAM", function()
      sys.setenv("NO_ICECREAM", 1)
      local ic = require_uncached("icecream")

      local spy_output = spy.new(function(s)
         return s
      end)
      ic.output_function = spy_output

      ic:disable()
      ic("hello")
      assert.spy(spy_output).was.called(0)

      ic:enable()
      ic("hello")
      assert.spy(spy_output).was.called(0)
   end)
end)
