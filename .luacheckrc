std = "max"
max_comment_line_length = 100

include_files = {
   "**/*.lua",
   ".busted",
   ".luacheckrc",
}

files["spec/**/*.lua"] = {
   std = "+busted",
}

ignore = { "212/self" } -- unused argument self
