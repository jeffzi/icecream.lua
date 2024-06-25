local utils = require("spec.utils")
local require_uncached = utils.require_uncached

describe("optional dependencies", function()
   local ic
   local original_require

   setup(function()
      original_require = require

      -- prevent from loading optional dependencies
      _G.require = function(module_name)
         if
            module_name == "ansicolors"
            or module_name == "dumbParser"
            or module_name == "inspect"
            or module_name == "system"
         then
            error(string.format("module '%s' not found", module_name))
         else
            return original_require(module_name)
         end
      end

      ic = require_uncached("icecream")
   end)

   teardown(function()
      _G.require = original_require
   end)

   it("no color", function()
      ic.color = true
      assert.is_false(ic.color)
      ic("hello")
      assert.string_match(ic:format("hello"), 'ic| spec/deps_spec%.lua:%d+: "hello"$')
   end)

   it("no inspect", function()
      local x = { _true = false, __call = function() end }
      local s = ic:format(x)
      assert.string_match(s, "ic| spec/deps_spec%.lua:%d+: " .. tostring(x))
   end)

   it("no dumbParser", function()
      local x = 42
      local s = ic:format(x)
      assert.string_match(s, "^ic| spec/deps_spec%.lua:%d+: 42$")
   end)

   local function count_lines(str)
      local count = #str > 0 and 1 or 0
      for _ in string.gmatch(str, "\n") do
         count = count + 1
      end
      return count
   end

   it("no system", function()
      local t = { a = 1, b = 2, c = 3, d = 4 }
      local s = ic:format(t)
      assert.is_true(count_lines(s) == 1)

      local new_width = 10
      ic.max_width = new_width
      s = ic:format(t)
      assert.is_true(ic.max_width == new_width)
      assert.is_true(count_lines(s) > 1)
   end)
end)
