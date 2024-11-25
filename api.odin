package main

import lua "vendor:lua/5.2"

foreign import liblite "liblite.a"

foreign liblite {
	luaopen_system :: proc(L: ^lua.State) -> i32 ---
	// luaopen_renderer :: proc(L: ^lua.State) -> i32 ---
}

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

