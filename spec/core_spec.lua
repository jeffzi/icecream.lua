local utils = require("spec.utils")
local require_uncached = utils.require_uncached
local is_luajit, ffi = pcall(require, "ffi")

describe("IceCream", function()
   local HEADER = "^ic| spec/core_spec%.lua:%d+: "
   local ic
   local original_traceback

   setup(function()
      ic = require_uncached("icecream")
      original_traceback = ic.traceback
   end)

   before_each(function()
      ic.prefix = "ic|"
      ic.color = false
      ic.include_context = true
      ic.max_width = 1000
      ic.indent = "  "
      ic.traceback = original_traceback
      ic:enable()
   end)

   it("stderr output", function()
      assert.no_error(function()
         ic("test stderr")
      end)
   end)

   it("ic()", function()
      local s = ic:format()
      assert.string_match(s:lower(), "stack traceback")
      assert.string_match(s, "^ic| spec/core_spec%.lua:")
   end)

   it("types", function()
      local t = { x = 1 }
      local arr = { 1, 2 }
      local function foo() end
      local s = ic:format(9.9, true, "foo", t, { x = 1 }, arr, { 1, 2 }, function() end, foo)
      local args = {
         "9.9",
         "true",
         '"foo"',
         "t = { x = 1 }",
         "{ x = 1 }",
         "arr = { 1, 2 }",
         "{ 1, 2 }",
         "<function %d+>",
         "foo = <function %d+>$",
      }
      assert.string_match(s, HEADER .. table.concat(args, ", "))
   end)

   if is_luajit then
      it("ffi", function()
         local s = ic:format(ffi.new("int", 1), ffi.typeof("int"), ffi.typeof("int")(1))
         local args = {
            'ffi%.new%("int",1%) = cdata<int>: 0x%x+',
            'ffi%.typeof%("int"%) = ctype<int>',
            'ffi%.typeof%("int"%)%(1%) = cdata<int>: 0x%x+',
         }
         assert.string_match(s, HEADER .. table.concat(args, ", "))
      end)
   end

   it("ic(x, y, z)", function()
      local x, y, z = 1, 2, 3
      local s = ic:format(x, y, z)
      assert.string_match(s, HEADER .. "x = 1, y = 2, z = 3$")
   end)

   it("ic(math.abs(x))", function()
      local x = 42
      local s = ic:format(math.abs(x))
      assert.string_match(s, HEADER .. "math%.abs%(x%) = 42$")
   end)

   it("ic({ _true = false, __call = function() end})", function()
      local x = { _true = false, __call = function() end }
      local s = ic:format(x)
      assert.string_match(s, HEADER .. "x = { __call = <function %d+>, _true = false }$")
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
         "^ic| spec/core_spec%.lua:%d+:",
         "9%.9",
         "true",
         '"foo"',
         "t = %{",
         '%["1"%] = "a",',
         '%["2"%] = "aa"',
         "%}%s*$",
      }
      local pattern = table.concat(lines, "%s*\n")

      assert.string_match(s, pattern)
   end)

   it("ic alias", function()
      local x = 42
      local dbg = ic
      local s = dbg:format(x)
      assert.string_match(s, HEADER .. "x = 42$")
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
      assert.string_match(s, expected)

      ic.traceback = nil
      s = ic:format()
      assert.no.string_match(s:lower(), "stack traceback")
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

   it("color", function()
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
         ax2 = 0x0104e1e258,
         b = 1.1,
         c = true,
         _d = false,
         _true = 1,
         [9] = "hello_true",
         __call = function() end,
         x = { subx = -9 },
      })

      -- luacheck: no max line length
      local expected = [[
[0m[4m[37mic|[0m[0m [0m[35m42[0m[0m, [0m[32m"foo"[0m[0m, [0m[33mfalse[0m[0m, [0m[1m[37m{[0m[0m[0m[35m 42[0m[0m, [0m[32m"foo"[0m[0m, [0m[33mfalse[0m[0m, [0m[34m[0][0m[0m = [0m[36m<function 1>[0m[0m, [0m[34m[9][0m[0m = [0m[32m"hello_true"[0m[0m, [0m[34m_d[0m[0m = [0m[33mfalse[0m[0m, [0m[34m_true[0m[0m =[0m[35m 1[0m[0m, [0m[34ma[0m[0m = [0m[32m"b"[0m[0m, [0m[34max2[0m[0m =[0m[35m 4376879704[0m[0m, [0m[34mb[0m[0m =[0m[35m 1.1[0m[0m, [0m[34mc[0m[0m = [0m[33mtrue[0m[0m, [0m[34mx[0m[0m = [0m[1m[37m{[0m[0m [0m[34msubx[0m[0m =[0m[35m -9[0m[0m [0m[1m[37m}[0m[0m, [0m[36m__call[0m[0m = [0m[36m<function 2>[0m[0m [0m[1m[37m}[0m[0m
]]
      assert.spy(spy_output).was.returned_with(expected)
   end)

   it("wrong option", function()
      assert.has_error(function()
         ic.foo = 1
      end, "foo is not a valid config option.")

      for _, opt in pairs({ "indent", "color", "prefix", "output_function" }) do
         assert.has_error(function()
            ic[opt] = nil
         end, opt .. " option cannot be set to nil.")
      end
   end)

   if _VERSION == "LUA 5.1" then
      it("tail call", function()
         assert.has_error(function()
            return ic("tailcall")
         end, "Cannot use IceCream as a return value")
      end)
   end

   describe("parse error message", function()
      local dumbParser, old_parse, fresh_ic, spy_output

      setup(function()
         dumbParser = require("dumbParser")
         old_parse = dumbParser.parse
         dumbParser.parse = function()
            return nil, "Mock parse error"
         end

         fresh_ic = require_uncached("icecream")
         fresh_ic.color = false

         spy_output = spy.new(function(s)
            return s
         end)
         fresh_ic.output_function = spy_output
      end)

      teardown(function()
         dumbParser.parse = old_parse
      end)

      it("should show parse error message", function()
         local formatted = fresh_ic:format("test", 1 + 2)
         assert.string_match(formatted, 'spec/core_spec%.lua:%d+: "test", 3')

         assert.spy(spy_output).was.called(1)
         local err = spy_output.calls[1].refs[1]
         print(err)
         assert.string_match(err, "^Failed to parse IceCream arguments: Mock parse error\n")
      end)
   end)

   it("multiple lines with comment", function()
      local command = [[NO_COLOR=1 lua -e 'local ic = require("src.icecream"); ic(1,
      -- 2,
      3)']]
      print(command)

      local handle = io.popen(command .. " 2>&1")
      local result = assert.is_not_nil(handle:read("*a"))
      local success, _, _ = handle:close()

      assert.is_true(success)
      assert.string_match(result, "^ic| 1, 3")
   end)
end)
