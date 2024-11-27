package main

import lua "vendor:lua/5.4"

API_TYPE_FONT :: "Font"

// odinfmt: disable
@(private="file")
libs := [?]lua.L_Reg {
  { "system",    luaopen_system     },
  { "renderer",  luaopen_renderer   },
}
// odinfmt: enable

api_load_libs :: proc(L: ^lua.State) {
	for lib in libs {
		lua.L_requiref(L, lib.name, lib.func, 1)
	}
}

