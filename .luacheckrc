std = "max"
max_comment_line_length = 100

include_files = {
   "**/*.lua",
   ".busted",
   ".luacheckrc",
}

ignore = {
   "212/self",  -- unused argument self
   "631",       -- line too long
}
