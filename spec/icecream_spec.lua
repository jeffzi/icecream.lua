local assert = require("luassert")
local say = require("say")

local function string_match(_, arguments)
   local s = arguments[1]
   local pattern = arguments[2]
   return s:find(pattern) ~= nil
end

assert:register(
   "assertion",
   "string_match",
   string_match,
   "assertion.string_match.positive",
   "assertion.string_match.negative"
)
say:set("assertion.string_match.positive", "Expected %s to match %s")
say:set("assertion.string_match.negative", "Expected %s to not match %s")

describe("IceCream", function()
   local ic

   setup(function()
      ic = require("icecream")
   end)

   before_each(function()
      ic.color = false
      ic.include_context = true
      ic.max_width = 80
      ic.indent = "  "
      ic:enable()
   end)

   it("stderr output", function()
      assert.no_error(function()
         ic("test stderr")
      end)
   end)

   it("ic()", function()
      local s = ic:format()
      assert.is_truthy(s:lower():find("stack traceback"))
      assert.string_match(s, "^ic| spec/icecream_spec%.lua:")
   end)

   it("ic(9.9, true, 'foo', function() end)", function()
      local s = ic:format(9.9, true, "foo", function() end)
      assert.string_match(s, '^ic| spec/icecream_spec%.lua:%d+: 9.9, true, "foo", <function %d+>$')
   end)

   it("ic(x, y, z)", function()
      local x, y, z = 1, 2, 3
      local s = ic:format(x, y, z)
      assert.string_match(s, "^ic| spec/icecream_spec%.lua:%d+: x = 1, y = 2, z = 3$")
   end)

   it("ic(math.abs(x))", function()
      local x = 42
      local s = ic:format(math.abs(x))
      assert.string_match(s, "^ic| spec/icecream_spec%.lua:%d+: math%.abs%(x%) = 42$")
   end)

   it("ic({ _true = false, __call = function() end})", function()
      local x = { _true = false, __call = function() end }
      local s = ic:format(x)
      assert.string_match(
         s,
         "^ic| spec/icecream_spec%.lua:%d+: x = { __call = <function %d+>, _true = false }$"
      )
   end)

   it("wrap long", function()
      ic.max_width = 10
      ic.indent = ""

      local t, n = {}, 2
      t["1"] = "a"
      for i = 2, n do
         t[tostring(i)] = t[tostring(i - 1)] .. "a"
      end
      local s = ic:format(9.9, true, "foo", t)

      local lines = {
         "^ic| spec/icecream_spec%.lua:%d+:%s*\n",
         "9%.9%s*\n",
         "true%s*\n",
         '"foo"%s*\n',
         't = %{\n%["1"%] = "a",\n',
         '%["2"%] = "aa"\n',
         "%}%s*$",
      }
      local pattern = table.concat(lines)

      assert.string_match(s, pattern)
   end)

   it("ic alias", function()
      local x = 42
      local dbg = ic
      local s = dbg:format(x)
      assert.string_match(s, "^ic| spec/icecream_spec%.lua:%d+: x = 42$")
   end)

   it("ic.traceback", function()
      local expected = "hello"
      ic.traceback = function()
         return expected
      end

      local s = ic:format()
      assert.string_match(s:lower(), expected)
   end)

   it("ic.enable/disable", function()
      local spy_output = spy.new(function(s)
         return s
      end)
      ic.output_function = spy_output

      ic:disable()
      ic("hello")
      assert.spy(spy_output).was.called(0)

      ic:enable()
      ic("hello")
      assert.spy(spy_output).was.called(1)
   end)

   it("ic.color", function()
      ic.color = true
      ic.include_context = false

      local spy_output = spy.new(function(s)
         return s
      end)
      ic.output_function = spy_output

      ic(42, "foo", false, {
         42,
         "foo",
         false,
         [0] = function() end,
         ["a"] = "b",
         ax2 = 1,
         b = 1.1,
         c = true,
         _d = false,
         _true = 1,
         [9] = "hello_true",
         __call = function() end,
         x = { subx = -9 },
      })

      local expected = [[
[0m[4m[37mic|[0m[0m
  [0m[35m42[0m[0m
  [0m[32m"foo"[0m[0m
  [0m[33mfalse[0m[0m
  [0m[1m[37m{[0m[0m
    [0m[35m42[0m[0m, [0m[32m"foo"[0m[0m, [0m[33mfalse[0m[0m,
    [0m[34m[0][0m[0m = [0m[36m<function 1>[0m[0m,
    [0m[34m[9][0m[0m = [0m[32m"hello_true"[0m[0m,
    [0m[34m_d[0m[0m = [0m[33mfalse[0m[0m,
    [0m[34m_true[0m[0m = [0m[35m1[0m[0m,
    [0m[34ma[0m[0m = [0m[32m"b"[0m[0m,
    [0m[34max2[0m[0m = [0m[35m1[0m[0m,
    [0m[34mb[0m[0m = [0m[35m1.1[0m[0m,
    [0m[34mc[0m[0m = [0m[33mtrue[0m[0m,
    [0m[34mx[0m[0m = [0m[1m[37m{[0m[0m
      [0m[34msubx[0m[0m = [0m[35m-9[0m[0m
    [0m[1m[37m}[0m[0m,
    [0m[36m__call[0m[0m = [0m[36m<function 2>[0m[0m
  [0m[1m[37m}[0m[0m
]]
      assert.spy(spy_output).was.returned_with(expected)
   end)

   describe("environment", function()
      local sys

      setup(function()
         sys = require("system")
         -- luacheck: push ignore
         os.getenv = sys.getenv
         -- luacheck: pop
      end)

      before_each(function()
         sys.setenv("NO_COLOR", nil)
      end)

      it("NO_COLOR", function()
         sys.setenv("NO_COLOR", 1)
         ic = require("icecream")

         assert.is_false(ic.color)
         assert.string_match(ic:format("hello"), '^ic| spec/icecream_spec%.lua:%d+: "hello"$')
      end)

      it("NO_ICECREAM", function()
         sys.setenv("NO_ICECREAM", 1)
         ic = require("icecream")

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
end)
