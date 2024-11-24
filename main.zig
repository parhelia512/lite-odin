const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("SDL2/SDL.h");

    @cInclude("lua/lua.h");
    @cInclude("lua/lauxlib.h");
    @cInclude("lua/lualib.h");

    @cInclude("C/renderer.h");
    //     @cInclude("C/api/api.h");
});

export var window: *c.SDL_Window = undefined;

extern "c" fn api_load_libs(L: *c.lua_State) void;

fn get_scale() f64 {
    var dpi: f32 = undefined;
    _ = c.SDL_GetDisplayDPI(0, null, &dpi, null);
    if (comptime builtin.os.tag == .windows) {
        return dpi / 96.0;
    }
    return 1.0;
}

fn init_window_icon() void {
    // TODO
}

pub fn main() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s\n", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    c.SDL_EnableScreenSaver();
    // ret value can be ignored as it just returns the previous state
    _ = c.SDL_EventState(c.SDL_DROPFILE, c.SDL_ENABLE);

    _ = c.SDL_SetHint(c.SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");
    _ = c.SDL_SetHint(c.SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");

    var dm: c.SDL_DisplayMode = undefined;
    if (c.SDL_GetCurrentDisplayMode(0, &dm) != 0) {
        c.SDL_Log("Unable to get SDL_GetCurrentDisplayMode: %s\n", c.SDL_GetError());
    }

    const width = @as(c_int, @intFromFloat(@as(f32, @floatFromInt(dm.w)) * 0.8));
    const height = @as(c_int, @intFromFloat(@as(f32, @floatFromInt(dm.w)) * 0.8));

    window = c.SDL_CreateWindow("", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, width, height, c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_HIDDEN) orelse {
        std.log.err("Failed to create sdl window {s}", .{c.SDL_GetError()});
        return error.SDLInitializationFailed;
    };

    //     init_window_icon();
    c.ren_init(window);

    const L = c.luaL_newstate() orelse {
        std.log.err("Failed to create lua state", .{});
        return error.Failed;
    };
    defer c.lua_close(L);
    c.luaL_openlibs(L);

    api_load_libs(L);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    c.lua_newtable(L);
    var i: i32 = 0;
    while (args.next()) |arg| {
        _ = c.lua_pushstring(L, arg);
        c.lua_rawseti(L, -2, i + 1);
        i = i + 1;
    }
    c.lua_setglobal(L, "ARGS");

    _ = c.lua_pushstring(L, "1.11");
    c.lua_setglobal(L, "VERSION");

    _ = c.lua_pushstring(L, c.SDL_GetPlatform());
    c.lua_setglobal(L, "PLATFORM");

    c.lua_pushnumber(L, get_scale());
    c.lua_setglobal(L, "SCALE");

    var exename: [512]u8 = undefined;
    @memset(&exename, 0);
    _ = std.fs.selfExePath(&exename) catch |err| {
        std.log.info("Failed to get exepath error: {}", .{err});
        return err;
    };
    _ = c.lua_pushstring(L, &exename);
    c.lua_setglobal(L, "EXEFILE");

    std.log.info("Starting up...", .{});

    const code =
        \\local core
        \\xpcall(function()
        \\  SCALE = tonumber(os.getenv("LITE_SCALE")) or SCALE
        \\  PATHSEP = package.config:sub(1, 1)
        \\  EXEDIR = EXEFILE:match("^(.+)[/\\].*$")
        \\  package.path = EXEDIR .. '/data/?.lua;' .. package.path
        \\  package.path = EXEDIR .. '/data/?/init.lua;' .. package.path
        \\  core = require('core')
        \\  core.init()
        \\  core.run()
        \\end, function(err)
        \\  print('Error: ' .. tostring(err))
        \\  print(debug.traceback(nil, 2))
        \\  if core and core.on_error then
        \\    pcall(core.on_error, err)
        \\  end
        \\  os.exit(1)
        \\end)
    ;
    var res = c.luaL_loadstring(L, code);
    if (res != c.LUA_OK) {
        std.log.err("Lua luaL_loadstring failure {}", .{res});
        return error.LuaInitFailure;
    }

    res = c.lua_pcallk(L, 0, c.LUA_MULTRET, 0, 0, null);
    if (res != c.LUA_OK) {
        std.log.err("Lua lua_pcallk failure {}", .{res});
        return error.LuaInitFailure;
    }
}
