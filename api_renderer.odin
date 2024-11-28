package main

import "base:runtime"

import lua "vendor:lua/5.4"

@(private = "file")
checkcolor :: proc(L: ^lua.State, idx: i32, default: i32) -> RenColor {
	if (lua.isnoneornil(L, idx)) {
		return RenColor{u8(default), u8(default), u8(default), 255}
	}
	lua.rawgeti(L, idx, 1)
	lua.rawgeti(L, idx, 2)
	lua.rawgeti(L, idx, 3)
	lua.rawgeti(L, idx, 4)
	color: RenColor
	color.r = cast(u8)lua.L_checknumber(L, -4)
	color.g = cast(u8)lua.L_checknumber(L, -3)
	color.b = cast(u8)lua.L_checknumber(L, -2)
	color.a = cast(u8)lua.L_optnumber(L, -1, 255)
	lua.pop(L, 4)
	return color
}

f_show_debug :: proc "c" (L: ^lua.State) -> i32 {
	context = runtime.default_context()
	lua.L_checkany(L, 1)
	rencache_show_debug(cast(bool)lua.toboolean(L, 1))
	return 0
}

f_get_size :: proc "c" (L: ^lua.State) -> i32 {
	w, h: i32
	ren_get_size(&w, &h)
	lua.pushnumber(L, lua.Number(w))
	lua.pushnumber(L, lua.Number(h))
	return 2
}

f_begin_frame :: proc "c" (L: ^lua.State) -> i32 {
	context = runtime.default_context()
	rencache_begin_frame()
	return 0
}

f_end_frame :: proc "c" (L: ^lua.State) -> i32 {
	context = runtime.default_context()
	rencache_end_frame()
	return 0
}

f_set_clip_rect :: proc "c" (L: ^lua.State) -> i32 {
	rect: RenRect
	rect.x = cast(i32)lua.L_checknumber(L, 1)
	rect.y = cast(i32)lua.L_checknumber(L, 2)
	rect.width = cast(i32)lua.L_checknumber(L, 3)
	rect.height = cast(i32)lua.L_checknumber(L, 4)
	context = runtime.default_context()
	rencache_set_clip_rect(rect)
	return 0
}

f_draw_rect :: proc "c" (L: ^lua.State) -> i32 {
	context = runtime.default_context()
	rect: RenRect
	rect.x = cast(i32)lua.L_checknumber(L, 1)
	rect.y = cast(i32)lua.L_checknumber(L, 2)
	rect.width = cast(i32)lua.L_checknumber(L, 3)
	rect.height = cast(i32)lua.L_checknumber(L, 4)
	color: RenColor = checkcolor(L, 5, 255)
	rencache_draw_rect(rect, color)
	return 0
}

f_draw_text :: proc "c" (L: ^lua.State) -> i32 {
	context = runtime.default_context()
	font: ^^RenFont = cast(^^RenFont)lua.L_checkudata(L, 1, API_TYPE_FONT)
	text: cstring = lua.L_checkstring(L, 2)
	x: int = cast(int)lua.L_checknumber(L, 3)
	y: int = cast(int)lua.L_checknumber(L, 4)
	color: RenColor = checkcolor(L, 5, 255)
	x = rencache_draw_text(font^, text, x, y, color)
	lua.pushnumber(L, lua.Number(x))
	return 1
}

// odinfmt: disable
@(private="file")
lib := []lua.L_Reg {
  { "show_debug",    f_show_debug    },
  { "get_size",      f_get_size      },
  { "begin_frame",   f_begin_frame   },
  { "end_frame",     f_end_frame     },
  { "set_clip_rect", f_set_clip_rect },
  { "draw_rect",     f_draw_rect     },
  { "draw_text",     f_draw_text     },
}
// odinfmt: enable

luaopen_renderer :: proc "c" (L: ^lua.State) -> i32 {
	context = runtime.default_context()
	lua.L_newlib(L, lib)
	luaopen_renderer_font(L)
	lua.setfield(L, -2, "font")
	return 1
}

