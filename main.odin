package main

import "base:runtime"
import "core:log"
import "core:math/linalg"
import sdl "vendor:sdl3"

default_context: runtime.Context

frag_shader_code := #load("shader.spv.frag")
vert_shader_code := #load("shader.spv.vert")

main :: proc() {
	context.logger = log.create_console_logger()
	default_context = context

	sdl.SetLogPriorities(.VERBOSE)
	sdl.SetLogOutputFunction(proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
		context = default_context
		log.debugf("SDL {} [{}]: {}", category, priority, message)
	}, nil)

	ok := sdl.Init({.VIDEO}); assert(ok)

	window := sdl.CreateWindow("Hello SDL3", 1280, 780, {}); assert(window != nil)

	gpu := sdl.CreateGPUDevice({.SPIRV}, true, nil); assert(gpu != nil)

	ok = sdl.ClaimWindowForGPUDevice(gpu, window); assert(ok)

	vert_shader := load_shader(gpu, vert_shader_code, .VERTEX, 1)
	frag_shader := load_shader(gpu, frag_shader_code, .FRAGMENT, 0)

	pipeline := sdl.CreateGPUGraphicsPipeline(gpu, {
		vertex_shader = vert_shader,
		fragment_shader = frag_shader,
		primitive_type = .TRIANGLELIST,
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = &(sdl.GPUColorTargetDescription {
				format = sdl.GetGPUSwapchainTextureFormat(gpu, window)
			})
		}
	})

	sdl.ReleaseGPUShader(gpu, vert_shader)
	sdl.ReleaseGPUShader(gpu, frag_shader)

	win_size: [2]i32
	ok = sdl.GetWindowSize(window, &win_size.x, &win_size.y); assert(ok)

	ROTATION_SPEED := linalg.to_radians(f32(90)) 
	rotation := f32(0)

	proj_mat := linalg.matrix4_perspective_f32(linalg.to_radians(f32(70)), f32(win_size.x) / f32(win_size.y), 0.0001, 1000)

	UBO :: struct {
		mvp: matrix[4,4]f32,
	}

	last_ticks := sdl.GetTicks()

	main_loop: for {
		new_ticks := sdl.GetTicks()
		delta_time := f32(new_ticks - last_ticks) / 1000
		last_ticks = new_ticks

		// process events
		ev: sdl.Event
		for sdl.PollEvent(&ev) {
			#partial switch ev.type {
				case .QUIT:
					break main_loop
				case .KEY_DOWN:
					if ev.key.scancode == .ESCAPE do break main_loop
			}
		}

		// update game state

		// render
		cmd_buf := sdl.AcquireGPUCommandBuffer(gpu)
		swapchain_tex: ^sdl.GPUTexture
		ok = sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, window, &swapchain_tex, nil, nil); assert(ok)

		rotation += ROTATION_SPEED * delta_time 
		model_mat := linalg.matrix4_translate_f32({0, 0, -5}) * linalg.matrix4_rotate_f32(rotation, {0,1,0})

		ubo := UBO {
			mvp = proj_mat * model_mat,
		}

		if swapchain_tex != nil {
			color_target := sdl.GPUColorTargetInfo {
				texture = swapchain_tex,
				load_op = .CLEAR,
				clear_color = {0, 0.2, 0.4, 1},
				store_op = .STORE
			}
			render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil)
			sdl.BindGPUGraphicsPipeline(render_pass, pipeline)
			sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo, size_of(ubo))
			sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)
			sdl.EndGPURenderPass(render_pass)
		}

		ok = sdl.SubmitGPUCommandBuffer(cmd_buf); assert(ok)
	}
}

load_shader :: proc(device: ^sdl.GPUDevice, code: []u8, stage: sdl.GPUShaderStage, num_uniform_buffers: u32) -> ^sdl.GPUShader {
	return sdl.CreateGPUShader(device, {
		code_size = len(code),
		code = raw_data(code),
		entrypoint = "main",
		format = {.SPIRV},
		stage = stage,
		num_uniform_buffers = num_uniform_buffers,
	})
}