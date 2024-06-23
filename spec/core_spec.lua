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
      ic.prefix = "ic|"
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
      assert.string_match(s, "^ic| spec/core_spec%.lua:")
   end)

   it("ic(9.9, true, 'foo', function() end)", function()
      local s = ic:format(9.9, true, "foo", function() end)
      assert.string_match(s, '^ic| spec/core_spec%.lua:%d+: 9.9, true, "foo", <function %d+>$')
   end)

   it("ic(x, y, z)", function()
      local x, y, z = 1, 2, 3
      local s = ic:format(x, y, z)
      assert.string_match(s, "^ic| spec/core_spec%.lua:%d+: x = 1, y = 2, z = 3$")
   end)

   it("ic(math.abs(x))", function()
      local x = 42
      local s = ic:format(math.abs(x))
      assert.string_match(s, "^ic| spec/core_spec%.lua:%d+: math%.abs%(x%) = 42$")
   end)

   it("ic({ _true = false, __call = function() end})", function()
      local x = { _true = false, __call = function() end }
      local s = ic:format(x)
      assert.string_match(
         s,
         "^ic| spec/core_spec%.lua:%d+: x = { __call = <function %d+>, _true = false }$"
      )
   end)

   local function count_lines(str)
      local count = #str > 0 and 1 or 0
      for _ in string.gmatch(str, "\n") do
         count = count + 1
      end
      return count
   end

   it("ic.max_width", function()
      local t = { a = 1, b = 2, c = 3, d = 4 }
      local s = ic:format(t)
      assert.is_true(count_lines(s) == 1)

      ic.max_width = nil
      s = ic:format(t)
      assert.is_true(count_lines(s) == 1)

      local new_width = 10
      ic.max_width = new_width
      s = ic:format(t)
      assert.is_true(ic.max_width == new_width)
      assert.is_true(count_lines(s) > 1)
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
         "^ic| spec/core_spec%.lua:%d+:%s*\n",
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
      assert.string_match(s, "^ic| spec/core_spec%.lua:%d+: x = 42$")
   end)

   it("passthrough", function()
      local expected_i, expected_s, expected_t, expected_b, expected_n = 42, "hello", {}, false, nil
      local i, s, t, b, n = ic(expected_i, expected_s, expected_t, expected_b, expected_n)
      assert.are_equal(expected_i, i)
      assert.are_equal(expected_s, s)
      assert.are_equal(expected_t, t)
      assert.are_equal(expected_b, b)
      assert.are_equal(expected_n, n)
   end)

   it("ic.prefix", function()
      local new_prefix = "TEST"
      ic.prefix = new_prefix
      local s = ic:format("hello")
      assert.string_match(s, "^" .. new_prefix .. ' spec/core_spec%.lua:%d+: "hello"')
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

   it("wrong option", function()
      assert.has_error(function()
         ic.foo = 1
      end, "foo is not a valid config option.")

      for _, opt in pairs({ "indent", "color", "prefix", "traceback", "output_function" }) do
         assert.has_error(function()
            ic[opt] = nil
         end, opt .. " option cannot be set to nil.")
      end
   end)
end)
