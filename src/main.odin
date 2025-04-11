package main

import "base:runtime"
import "core:log"
import "core:math/linalg"
import sdl "vendor:sdl3"
import im "shared:imgui"
import im_sdl "shared:imgui/imgui_impl_sdl3"
import im_sdlgpu "shared:imgui/imgui_impl_sdlgpu3"

sdl_log :: proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
	context = (transmute(^runtime.Context)userdata)^
	level: log.Level
	switch priority {
	case .INVALID, .TRACE, .VERBOSE, .DEBUG: level = .Debug
	case .INFO: level = .Info
	case .WARN: level = .Warning
	case .ERROR: level = .Error
	case .CRITICAL: level = .Fatal
	}
	log.logf(level, "SDL {}: {}", category, message)
}

init_sdl :: proc() {
	@static sdl_log_context: runtime.Context
	sdl_log_context = context
	sdl_log_context.logger.options -= {.Short_File_Path, .Line, .Procedure}
	sdl.SetLogPriorities(.VERBOSE)
	sdl.SetLogOutputFunction(sdl_log, &sdl_log_context)

	ok := sdl.Init({.VIDEO}); sdl_assert(ok)

	g.window = sdl.CreateWindow("Hello SDL3", 1280, 780, {}); sdl_assert(g.window != nil)

	g.gpu = sdl.CreateGPUDevice({.SPIRV, .DXIL, .MSL}, true, nil); sdl_assert(g.gpu != nil)

	ok = sdl.ClaimWindowForGPUDevice(g.gpu, g.window); sdl_assert(ok)

	ok = sdl.SetGPUSwapchainParameters(g.gpu, g.window, .SDR_LINEAR, .VSYNC); sdl_assert(ok)

	g.swapchain_texture_format = sdl.GetGPUSwapchainTextureFormat(g.gpu, g.window)

	ok = sdl.GetWindowSize(g.window, &g.window_size.x, &g.window_size.y); sdl_assert(ok)

	g.depth_texture_format = .D16_UNORM
	try_depth_format :: proc(format: sdl.GPUTextureFormat) {
		if sdl.GPUTextureSupportsFormat(g.gpu, format, .D2, {.DEPTH_STENCIL_TARGET}) {
			g.depth_texture_format = format
		}
	}
	try_depth_format(.D32_FLOAT)
	try_depth_format(.D24_UNORM)

	g.depth_texture = sdl.CreateGPUTexture(g.gpu, {
		format = g.depth_texture_format,
		usage = {.DEPTH_STENCIL_TARGET},
		width = u32(g.window_size.x),
		height = u32(g.window_size.y),
		layer_count_or_depth = 1,
		num_levels = 1,
	})

	_ = sdl.SetWindowRelativeMouseMode(g.window, true)
}

init_imgui :: proc() {
	im.CHECKVERSION()
	im.CreateContext()
	im_sdl.InitForSDLGPU(g.window)
	im_sdlgpu.Init(&{
		Device = g.gpu,
		ColorTargetFormat = g.swapchain_texture_format,
	})

	// since we're using the LINEAR swapchain composition mode,
	// the colors are expected to be in linear space. the imgui shaders don't
	// do any tranfering, and the original style values are in sRGB, so we convert them here
	style := im.GetStyle()
	for &color in style.Colors {
		color.rgb = linalg.pow(color.rgb, 2.2)
	}
}

main :: proc() {
	context.logger = log.create_console_logger()

	init_sdl()
	init_imgui()

	game_init()

	last_ticks := sdl.GetTicks()
	im_io := im.GetIO()

	main_loop: for {
		free_all(context.temp_allocator)
		g.mouse_move = {}

		new_ticks := sdl.GetTicks()
		delta_time := f32(new_ticks - last_ticks) / 1000
		last_ticks = new_ticks

		ui_input_mode := !sdl.GetWindowRelativeMouseMode(g.window)

		// process events
		ev: sdl.Event
		for sdl.PollEvent(&ev) {
			if ui_input_mode do im_sdl.ProcessEvent(&ev)

			#partial switch ev.type {
				case .QUIT:
					break main_loop
				case .KEY_DOWN:
					if ev.key.scancode == .ESCAPE && !im_io.WantCaptureKeyboard do break main_loop
					if !ui_input_mode {
						g.key_down[ev.key.scancode] = true
					}
				case .KEY_UP:
					g.key_down[ev.key.scancode] = false
				case .MOUSE_MOTION:
					if !ui_input_mode {
						g.mouse_move += {ev.motion.xrel, ev.motion.yrel}
					}
				case .MOUSE_BUTTON_DOWN:
					if ev.button.button == 2 {
						ui_input_mode = !ui_input_mode
						_ = sdl.SetWindowRelativeMouseMode(g.window, !ui_input_mode)
					}
			}
		}

		im_sdlgpu.NewFrame()
		im_sdl.NewFrame()
		im.NewFrame()

		game_update(delta_time)

		// render
		cmd_buf := sdl.AcquireGPUCommandBuffer(g.gpu)
		swapchain_tex: ^sdl.GPUTexture
		ok := sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, g.window, &swapchain_tex, nil, nil); sdl_assert(ok)

		im.Render()
		im_draw_data := im.GetDrawData()

		if swapchain_tex != nil {
			game_render(cmd_buf, swapchain_tex)

			if im_draw_data.DisplaySize.x > 0 && im_draw_data.DisplaySize.y > 0 {
				im_sdlgpu.PrepareDrawData(im_draw_data, cmd_buf)
				im_color_target := sdl.GPUColorTargetInfo {
					texture = swapchain_tex,
					load_op = .LOAD,
					store_op = .STORE
				}
				im_render_pass := sdl.BeginGPURenderPass(cmd_buf, &im_color_target, 1, nil)
				im_sdlgpu.RenderDrawData(im_draw_data, cmd_buf, im_render_pass)
				sdl.EndGPURenderPass(im_render_pass)
			}
		}

		ok = sdl.SubmitGPUCommandBuffer(cmd_buf); sdl_assert(ok)
	}
}

