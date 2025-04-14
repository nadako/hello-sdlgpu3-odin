package main

import "core:log"
import sdl "vendor:sdl3"

CONTENT_DIR :: "content"

Vec3 :: [3]f32
Vec2 :: [2]f32
Mat4 :: matrix[4, 4]f32
Quat :: quaternion128

WHITE :: sdl.FColor { 1, 1, 1, 1 }

sdl_assert :: proc(ok: bool) {
	if !ok do log.panicf("SDL Error: {}", sdl.GetError())
}

Globals :: struct {
	gpu: ^sdl.GPUDevice,
	window: ^sdl.Window,
	window_size: [2]i32,
	depth_texture: ^sdl.GPUTexture,
	depth_texture_format: sdl.GPUTextureFormat,
	swapchain_texture_format: sdl.GPUTextureFormat,

	key_down: #sparse[sdl.Scancode]bool,
	mouse_move: Vec2,

	using game: Game_State,
}

g: Globals

