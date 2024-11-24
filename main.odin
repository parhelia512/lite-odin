package main
import "base:runtime"
import "core:c/libc"
import "core:encoding/ansi"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:os/os2"
import "core:strings"

import lua "vendor:lua/5.2"
import sdl "vendor:sdl2"

foreign import liblite "liblite.a"

foreign liblite {
	api_load_libs :: proc(state: ^lua.State) ---
	ren_init :: proc(window: ^sdl.Window) ---
}

// global tracking allocator to be used in atexit handler
when ODIN_DEBUG {
	track: mem.Tracking_Allocator
}

@(export, link_name = "window")
window: ^sdl.Window

get_exe_filename :: proc() -> cstring {
	info, err := os2.current_process_info(
		os2.Process_Info_Fields{os2.Process_Info_Field.Executable_Path},
		context.temp_allocator,
	)
	defer os2.free_process_info(info, context.temp_allocator)
	if err != nil {
		return "./main"
	}
	return strings.clone_to_cstring(info.executable_path, context.temp_allocator)
}

get_scale :: proc() -> f64 {
	dpi: f32
	_ = sdl.GetDisplayDPI(0, nil, &dpi, nil)
	when ODIN_OS == .Windows {
		return dpi / 96.0
	}
	return 1.0
}

blue :: #force_inline proc($s: string) -> string {
	return ansi.CSI + ansi.FG_BLUE + ansi.SGR + s + ansi.CSI + ansi.RESET + ansi.SGR
}

run_at_exit :: proc "c" () {
	context = runtime.default_context()
	fmt.println(blue("Exiting..."))
	sdl.Quit()

	when ODIN_DEBUG {
		red :: proc($s: string) -> string {
			return ansi.CSI + ansi.FG_BRIGHT_RED + ansi.SGR + s + ansi.CSI + ansi.RESET + ansi.SGR
		}

		if len(track.allocation_map) > 0 {
			fmt.eprintf(red("=== %v allocations not freed: ===\n"), len(track.allocation_map))
			for _, entry in track.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		if len(track.bad_free_array) > 0 {
			fmt.eprintf(red("=== %v incorrect frees: ===\n"), len(track.bad_free_array))
			for entry in track.bad_free_array {
				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&track)
	}
}

main :: proc() {
	fmt.println(blue("is ODIN_DEBUG: "), ODIN_DEBUG)
	when ODIN_DEBUG {
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		// no defer, lua just exits the app
	}

	if sdl.Init(sdl.INIT_VIDEO) != 0 {
		fmt.println("Unable to get SDL_GetCurrentDisplayMode: %s\n", sdl.GetError())
		return
	}
	libc.atexit(run_at_exit)

	defer sdl.Quit()

	sdl.EnableScreenSaver()
	// ret value can be ignored as it just returns the previous state
	sdl.EventState(sdl.EventType.DROPFILE, sdl.ENABLE)

	sdl.SetHint(sdl.HINT_MOUSE_FOCUS_CLICKTHROUGH, "1")
	sdl.SetHint(sdl.HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0")

	dm: sdl.DisplayMode
	if (sdl.GetCurrentDisplayMode(0, &dm) != 0) {
		sdl.Log("Unable to get SDL_GetCurrentDisplayMode: %s\n", sdl.GetError())
	}

	window = sdl.CreateWindow(
		"",
		sdl.WINDOWPOS_UNDEFINED,
		sdl.WINDOWPOS_UNDEFINED,
		cast(i32)(cast(f32)dm.w * 0.8),
		cast(i32)(cast(f32)dm.h * 0.8),
		sdl.WINDOW_RESIZABLE | sdl.WINDOW_ALLOW_HIGHDPI | sdl.WINDOW_HIDDEN,
	)

	ren_init(window)

	L := lua.L_newstate()
	defer lua.close(L)

	lua.L_openlibs(L)

	api_load_libs(L)

	lua.newtable(L)
	for arg, idx in os.args {
		lua.pushstring(L, strings.clone_to_cstring(arg, context.temp_allocator))
		lua.rawseti(L, -2, cast(i32)idx + 1)
	}
	lua.setglobal(L, "ARGS")

	lua.pushstring(L, "1.11")
	lua.setglobal(L, "VERSION")

	lua.pushstring(L, sdl.GetPlatform())
	lua.setglobal(L, "PLATFORM")

	lua.pushnumber(L, cast(lua.Number)get_scale())
	lua.setglobal(L, "SCALE")

	lua.pushstring(L, get_exe_filename())
	lua.setglobal(L, "EXEFILE")

	lua_code :: `local core
        xpcall(function()
          SCALE = tonumber(os.getenv("LITE_SCALE")) or SCALE
          PATHSEP = package.config:sub(1, 1)
          EXEDIR = EXEFILE:match("^(.+)[/\\].*$")
          package.path = EXEDIR .. '/data/?.lua;' .. package.path
          package.path = EXEDIR .. '/data/?/init.lua;' .. package.path
          core = require('core')
          core.init()
          core.run()
        end, function(err)
          print('Error: ' .. tostring(err))
          print(debug.traceback(nil, 2))
          if core and core.on_error then
            pcall(core.on_error, err)
          end
          os.exit(1)
        end)`

	lua.L_dostring(L, lua_code)
}

