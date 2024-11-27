package main

import "base:runtime" // memset
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

import stbtt "vendor:stb/truetype"

/* a cache over the software renderer -- all drawing operations are stored as
** commands when issued. At the end of the frame we write the commands to a grid
** of hash values, take the cells that have changed since the previous frame,
** merge them into dirty rectangles and redraw only those regions */

CELLS_X :: 80
CELLS_Y :: 50
CELL_SIZE :: 96
COMMAND_BUF_SIZE :: 1024 * 512

HASH_INITIAL :: 2166136261

@(private)
CommandType :: enum {
	FREE_FONT,
	SET_CLIP,
	DRAW_TEXT,
	DRAW_RECT,
}

Command :: struct {
	type:      CommandType,
	size:      int,
	rect:      RenRect,
	color:     RenColor,
	font:      ^RenFont,
	tab_width: i32,
	text:      string,
}

cells_buf1: [CELLS_X * CELLS_Y]u32
cells_buf2: [CELLS_X * CELLS_Y]u32
cells_prev: []u32 = cells_buf1[:]
cells: []u32 = cells_buf2[:]
rect_buf: [CELLS_X * CELLS_Y / 2]RenRect

commands: [dynamic]Command
frame_temp_arena: runtime.Arena_Temp

screen_rect: RenRect
show_debug: bool


hash :: proc "contextless" (h: u32, data: []u8) -> u32 {
	h := h
	for d in data {
		h = (h ~ u32(d)) * 16777619
	}
	return h
}

cell_idx :: proc "contextless" (x: i32, y: i32) -> i32 {
	return x + y * CELLS_X
}

rects_overlap :: proc "contextless" (a: RenRect, b: RenRect) -> bool {
// odinfmt: disable
  return b.x + b.width  >= a.x && b.x <= a.x + a.width &&
         b.y + b.height >= a.y && b.y <= a.y + a.height;
// odinfmt: enable
}

intersect_rects :: proc "contextless" (a: RenRect, b: RenRect) -> RenRect {
	x1: i32 = math.max(a.x, b.x)
	y1: i32 = math.max(a.y, b.y)
	x2: i32 = math.min(a.x + a.width, b.x + b.width)
	y2: i32 = math.min(a.y + a.height, b.y + b.height)
	return {x1, y1, max(0, x2 - x1), max(0, y2 - y1)}
}

merge_rects :: proc "contextless" (a: RenRect, b: RenRect) -> RenRect {
	x1: i32 = min(a.x, b.x)
	y1: i32 = min(a.y, b.y)
	x2: i32 = max(a.x + a.width, b.x + b.width)
	y2: i32 = max(a.y + a.height, b.y + b.height)
	return {x1, y1, x2 - x1, y2 - y1}
}

rencache_init :: proc () {
	assert(len(commands) == 0)
	commands = make([dynamic]Command, context.temp_allocator)
}

rencache_show_debug :: proc "contextless" (enable: bool) {
	show_debug = enable
}

rencache_free_font :: proc(font: ^RenFont) {
	append(&commands, Command{type = CommandType.FREE_FONT, font = font})
}

rencache_set_clip_rect :: proc(rect: RenRect) {
	append(
		&commands,
		Command{type = CommandType.SET_CLIP, rect = intersect_rects(rect, screen_rect)},
	)
}

rencache_draw_rect :: proc(rect: RenRect, color: RenColor) {
	if (!rects_overlap(screen_rect, rect)) {
		return
	}
	append(&commands, Command{type = CommandType.DRAW_RECT, rect = rect, color = color})
}

rencache_draw_text :: proc(font: ^RenFont, text: cstring, x: int, y: int, color: RenColor) -> int {
	rect: RenRect = ---
	rect.x = cast(i32)x
	rect.y = cast(i32)y
	rect.width = ren_get_font_width(font, text)
	rect.height = ren_get_font_height(font)

	if (rects_overlap(screen_rect, rect)) {
		append(
			&commands,
			Command {
				type = CommandType.DRAW_TEXT,
				text = strings.clone(string(text)),
				color = color,
				rect = rect,
				font = font,
				tab_width = ren_get_font_tab_width(font),
			},
		)
	}

	return x + int(rect.width)
}

@(export)
rencache_invalidate :: proc "c" () {
	runtime.memset(raw_data(cells_prev), 0xff, len(cells_prev) * size_of(u32))
}

rencache_begin_frame :: proc() {
	frame_temp_arena = runtime.default_temp_allocator_temp_begin()
	/* reset all cells if the screen width/height has changed */
	w, h: i32
	ren_get_size(&w, &h)
	if (screen_rect.width != w || h != screen_rect.height) {
		screen_rect.width = w
		screen_rect.height = h
		rencache_invalidate()
	}
}

update_overlapping_cells :: proc "contextless" (r: RenRect, h: u32) {
	x1 := r.x / CELL_SIZE
	y1 := r.y / CELL_SIZE
	x2 := (r.x + r.width) / CELL_SIZE
	y2 := (r.y + r.height) / CELL_SIZE

	h := h

	for y := y1; y <= y2; y += 1 {
		for x := x1; x <= x2; x += 1 {
			idx := cell_idx(x, y)
			cells[idx] = hash(cells[idx], mem.ptr_to_bytes(&h, 1))
		}
	}
}

push_rect :: proc "contextless" (r: RenRect, count: int) -> int {
	/* try to merge with existing rectangle */
	for i := count - 1; i >= 0; i -= 1 {
		rp: ^RenRect = &rect_buf[i]
		if (rects_overlap(rp^, r)) {
			rp^ = merge_rects(rp^, r)
			return count
		}
	}
	/* couldn't merge with previous rectangle: push */
	rect_buf[count] = r

	count := count
	count += 1
	return count
}

rencache_end_frame :: proc() {
	// TODO use arena
	/* update cells from commands */
	cr: RenRect
	for &cmd in commands {
		if cmd.type == CommandType.SET_CLIP {
			cr = cmd.rect
		}
		r := intersect_rects(cmd.rect, cr)
		if (r.width == 0 || r.height == 0) {
			continue
		}
		h: u32 = HASH_INITIAL
		h = hash(h, mem.ptr_to_bytes(&cmd, 1))
		if (cmd.type == .DRAW_TEXT) {
			h = hash(h, transmute([]u8)cmd.text)
		}
		update_overlapping_cells(r, h)
	}

	/* push rects for all cells changed from last frame, reset cells */
	rect_count := 0
	max_x := screen_rect.width / CELL_SIZE + 1
	max_y := screen_rect.height / CELL_SIZE + 1
	for y: i32 = 0; y < max_y; y += 1 {
		for x: i32 = 0; x < max_x; x += 1 {
			/* compare previous and current cell for change */
			idx := cell_idx(x, y)
			if (cells[idx] != cells_prev[idx]) {
				rect_count = push_rect(RenRect{x, y, 1, 1}, rect_count)
			}
			cells_prev[idx] = HASH_INITIAL
		}
	}

	/* expand rects from cells to pixels */
	for i := 0; i < rect_count; i += 1 {
		r: ^RenRect = &rect_buf[i]
		r^.x *= CELL_SIZE
		r^.y *= CELL_SIZE
		r^.width *= CELL_SIZE
		r^.height *= CELL_SIZE
		r^ = intersect_rects(r^, screen_rect)
	}

	/* redraw updated regions */
	has_free_commands := false
	for i := 0; i < rect_count; i += 1 {
		/* draw */
		r: RenRect = rect_buf[i]
		ren_set_clip_rect(r)

		for cmd in commands {
			switch cmd.type {
			case .FREE_FONT:
				has_free_commands = true
			case .SET_CLIP:
				ren_set_clip_rect(intersect_rects(cmd.rect, r))
			case .DRAW_RECT:
				ren_draw_rect(cmd.rect, cmd.color)
			case .DRAW_TEXT:
				ren_set_font_tab_width(cmd.font, cmd.tab_width)
				ren_draw_text(cmd.font, cmd.text, cmd.rect.x, cmd.rect.y, cmd.color)
			}
		}
		if (show_debug) {
			color := RenColor{0, 0, 255, 50} // red(bgra)
			ren_draw_rect(r, color)
		}
	}

	/* update dirty rects */
	if rect_count > 0 {
		ren_update_rects(raw_data(&rect_buf), i32(rect_count))
	}

	// /* free fonts */
	if has_free_commands {
		for cmd in commands {
			if (cmd.type == CommandType.FREE_FONT) {
				ren_free_font(cmd.font)
			}
		}
	}

	clear(&commands)

	/* swap cell buffer and reset */
	cells, cells_prev = cells_prev, cells

	// free everything
	runtime.default_temp_allocator_temp_end(frame_temp_arena)
}

