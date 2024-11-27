package main

import "base:runtime"

import lua "vendor:lua/5.4"

f_load :: proc "c" (L: ^lua.State) -> i32 {
	context = runtime.default_context()
	filename: cstring = lua.L_checkstring(L, 1)
	size: f32 = cast(f32)lua.L_checknumber(L, 2)
	self: ^^RenFont = cast(^^RenFont)lua.newuserdata(L, size_of(^RenFont))
	lua.L_setmetatable(L, API_TYPE_FONT)
	self^ = ren_load_font(filename, size)
	if (self^ == nil) {
		lua.L_error(L, "failed to load font")
	}
	return 1
}

f_set_tab_width :: proc "c" (L: ^lua.State) -> i32 {
	context = runtime.default_context()
	self: ^^RenFont = cast(^^RenFont)lua.L_checkudata(L, 1, API_TYPE_FONT)
	n := lua.L_checknumber(L, 2)
	ren_set_font_tab_width(self^, i32(n))
	return 0
}

f_gc :: proc "c" (L: ^lua.State) -> i32 {
	self: ^^RenFont = cast(^^RenFont)lua.L_checkudata(L, 1, API_TYPE_FONT)
	context = runtime.default_context()
	if (self^ != nil) {rencache_free_font(self^)}
	return 0
}


f_get_width :: proc "c" (L: ^lua.State) -> i32 {
	self: ^^RenFont = cast(^^RenFont)lua.L_checkudata(L, 1, API_TYPE_FONT)
	text: cstring = lua.L_checkstring(L, 2)
	context = runtime.default_context()
	lua.pushnumber(L, cast(lua.Number)ren_get_font_width(self^, text))
	return 1
}


f_get_height :: proc "c" (L: ^lua.State) -> i32 {
	self: ^^RenFont = cast(^^RenFont)lua.L_checkudata(L, 1, API_TYPE_FONT)
	lua.pushnumber(L, cast(lua.Number)ren_get_font_height(self^))
	return 1
}


// odinfmt: disable
@(private="file")
lib := []lua.L_Reg {
  { "__gc",          f_gc            },
  { "load",          f_load          },
  { "set_tab_width", f_set_tab_width },
  { "get_width",     f_get_width     },
  { "get_height",    f_get_height    },
}
// odinfmt: enable

luaopen_renderer_font :: proc "c" (L: ^lua.State) -> i32 {
	lua.L_newmetatable(L, API_TYPE_FONT)
	lua.L_setfuncs(L, raw_data(lib), 0)
	lua.pushvalue(L, -1)
	lua.setfield(L, -2, "__index")
	return 1
}

