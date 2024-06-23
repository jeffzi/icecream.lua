require("spec.string_match")

describe("optional dependencies", function()
   local ic
   setup(function()
      local original_require = require
      _G.require = function(module_name)
         if module_name == "system" or module_name == "inspect" then
            error(string.format("module '%s' not found", module_name))
         else
            return original_require(module_name)
         end
      end

      ic = require("icecream")
   end)

   before_each(function()
      ic.color = false
   end)

   it("no inspect", function()
      local x = { _true = false, __call = function() end }
      local s = ic:format(x)
      assert.string_match(s, tostring(x))
   end)

   local function count_lines(str)
      local count = #str > 0 and 1 or 0
      for _ in string.gmatch(str, "\n") do
         count = count + 1
      end
      return count
   end

   it("no termsize", function()
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
