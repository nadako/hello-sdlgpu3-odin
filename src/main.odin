package main

import "base:runtime"
import "core:log"
import "core:strings"
import "core:mem"
import "core:os"
import "core:encoding/json"
import "core:path/filepath"
import "core:math"
import "core:math/linalg"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"
import im "shared:imgui"
import im_sdl "shared:imgui/imgui_impl_sdl3"
import im_sdlgpu "shared:imgui/imgui_impl_sdlgpu3"

CONTENT_DIR :: "content"

default_context: runtime.Context

gpu: ^sdl.GPUDevice
window: ^sdl.Window
win_size: [2]i32
depth_texture: ^sdl.GPUTexture
pipeline: ^sdl.GPUGraphicsPipeline
sampler: ^sdl.GPUSampler
camera: struct {
	position: Vec3,
	target: Vec3,
}
look: struct {
	yaw: f32,
	pitch: f32,
}
key_down: #sparse[sdl.Scancode]bool
mouse_move: Vec2

EYE_HEIGHT :: 1
MOVE_SPEED :: 5
LOOK_SENSITIVITY :: 0.3

Vec3 :: [3]f32
Vec2 :: [2]f32

depth_texture_format := sdl.GPUTextureFormat.D16_UNORM
WHITE :: sdl.FColor { 1, 1, 1, 1 }

Vertex_Data :: struct {
	pos: Vec3,
	color: sdl.FColor,
	uv: Vec2,
}

Model :: struct {
	vertex_buf: ^sdl.GPUBuffer,
	index_buf: ^sdl.GPUBuffer,
	num_indices: u32,
	texture: ^sdl.GPUTexture,
}

init :: proc() {
	sdl.SetLogPriorities(.VERBOSE)
	sdl.SetLogOutputFunction(proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
		context = default_context
		log.debugf("SDL {} [{}]: {}", category, priority, message)
	}, nil)

	ok := sdl.Init({.VIDEO}); assert(ok)

	window = sdl.CreateWindow("Hello SDL3", 1280, 780, {}); assert(window != nil)

	gpu = sdl.CreateGPUDevice({.DXIL, .MSL}, true, nil); assert(gpu != nil)

	ok = sdl.ClaimWindowForGPUDevice(gpu, window); assert(ok)

	ok = sdl.SetGPUSwapchainParameters(gpu, window, .SDR_LINEAR, .VSYNC); assert(ok)

	ok = sdl.GetWindowSize(window, &win_size.x, &win_size.y); assert(ok)

	try_depth_format :: proc(format: sdl.GPUTextureFormat) {
		if sdl.GPUTextureSupportsFormat(gpu, format, .D2, {.DEPTH_STENCIL_TARGET}) {
			depth_texture_format = format
		}
	}
	try_depth_format(.D32_FLOAT)
	try_depth_format(.D24_UNORM)

	depth_texture = sdl.CreateGPUTexture(gpu, {
		format = depth_texture_format,
		usage = {.DEPTH_STENCIL_TARGET},
		width = u32(win_size.x),
		height = u32(win_size.y),
		layer_count_or_depth = 1,
		num_levels = 1,
	})

	camera = {
		position = {0, EYE_HEIGHT, 3},
		target = {0, EYE_HEIGHT, 0}
	}

	_ = sdl.SetWindowRelativeMouseMode(window, true)

	init_imgui()
}

init_imgui :: proc() {
	im.CHECKVERSION()
	im.CreateContext()
	im_sdl.InitForSDLGPU(window)
	im_sdlgpu.Init(&{
		Device = gpu,
		ColorTargetFormat = sdl.GetGPUSwapchainTextureFormat(gpu, window)
	})

	// since we're using the LINEAR swapchain composition mode,
	// the colors are expected to be in linear space. the imgui shaders don't
	// do any tranfering, and the original style values are in sRGB, so we convert them here
	style := im.GetStyle()
	for &color in style.Colors {
		color.rgb = linalg.pow(color.rgb, 2.2)
	}
}

setup_pipeline :: proc() {
	vert_shader := load_shader(gpu, "shader.vert")
	frag_shader := load_shader(gpu, "shader.frag")

	vertex_attrs := []sdl.GPUVertexAttribute {
		{
			location = 0,
			format = .FLOAT3,
			offset = u32(offset_of(Vertex_Data, pos)),
		},
		{
			location = 1,
			format = .FLOAT4,
			offset = u32(offset_of(Vertex_Data, color)),
		},
		{
			location = 2,
			format = .FLOAT2,
			offset = u32(offset_of(Vertex_Data, uv)),
		}
	}

	pipeline = sdl.CreateGPUGraphicsPipeline(gpu, {
		vertex_shader = vert_shader,
		fragment_shader = frag_shader,
		primitive_type = .TRIANGLELIST,
		vertex_input_state = {
			num_vertex_buffers = 1,
			vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
				slot = 0,
				pitch = size_of(Vertex_Data),
			}),
			num_vertex_attributes = u32(len(vertex_attrs)),
			vertex_attributes = raw_data(vertex_attrs)
		},
		depth_stencil_state = {
			enable_depth_test = true,
			enable_depth_write = true,
			compare_op = .LESS,
		},
		rasterizer_state = {
			cull_mode = .BACK,
			// fill_mode = .LINE,
		},
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = &(sdl.GPUColorTargetDescription {
				format = sdl.GetGPUSwapchainTextureFormat(gpu, window)
			}),
			has_depth_stencil_target = true,
			depth_stencil_format = depth_texture_format,
		}
	})

	sdl.ReleaseGPUShader(gpu, vert_shader)
	sdl.ReleaseGPUShader(gpu, frag_shader)

	sampler = sdl.CreateGPUSampler(gpu, {})
}

load_model :: proc(mesh_file: string, texture_file: string) -> Model {
	mesh_path := filepath.join({CONTENT_DIR, "meshes", mesh_file}, context.temp_allocator)
	texture_path := filepath.join({CONTENT_DIR, "textures", texture_file}, context.temp_allocator)

	texture_file := strings.clone_to_cstring(texture_path, context.temp_allocator)

	img_size: [2]i32
	// stbi.set_flip_vertically_on_load(1)
	pixels := stbi.load(texture_file, &img_size.x, &img_size.y, nil, 4); assert(pixels != nil)
	pixels_byte_size := img_size.x * img_size.y * 4

	texture := sdl.CreateGPUTexture(gpu, {
		format = .R8G8B8A8_UNORM_SRGB, // pixels are in sRGB, converted to linear in shaders
		usage = {.SAMPLER},
		width = u32(img_size.x),
		height = u32(img_size.y),
		layer_count_or_depth = 1,
		num_levels = 1,
	})

	obj_data := obj_load(mesh_path)

	vertices := make([]Vertex_Data, len(obj_data.faces))
	indices := make([]u16, len(obj_data.faces))

	for face, i in obj_data.faces {
		uv := obj_data.uvs[face.uv]
		vertices[i] = {
			pos = obj_data.positions[face.pos],
			color = WHITE,
			uv = {uv.x, 1-uv.y},
		}
		indices[i] = u16(i)
	}

	obj_destroy(obj_data)

	num_indices := len(indices)

	vertices_byte_size := len(vertices) * size_of(vertices[0])
	indices_byte_size := len(indices) * size_of(indices[0])

	vertex_buf := sdl.CreateGPUBuffer(gpu, {
		usage = {.VERTEX},
		size = u32(vertices_byte_size)
	})

	index_buf := sdl.CreateGPUBuffer(gpu, {
		usage = {.INDEX},
		size = u32(indices_byte_size)
	})

	transfer_buf := sdl.CreateGPUTransferBuffer(gpu, {
		usage = .UPLOAD,
		size = u32(vertices_byte_size + indices_byte_size)
	})

	transfer_mem := transmute([^]byte)sdl.MapGPUTransferBuffer(gpu, transfer_buf, false)
	mem.copy(transfer_mem, raw_data(vertices), vertices_byte_size)
	mem.copy(transfer_mem[vertices_byte_size:], raw_data(indices), indices_byte_size)
	sdl.UnmapGPUTransferBuffer(gpu, transfer_buf)

	delete(indices)
	delete(vertices)

	tex_transfer_buf := sdl.CreateGPUTransferBuffer(gpu, {
		usage = .UPLOAD,
		size = u32(pixels_byte_size)
	})
	tex_transfer_mem := sdl.MapGPUTransferBuffer(gpu, tex_transfer_buf, false)
	mem.copy(tex_transfer_mem, pixels, int(pixels_byte_size))
	sdl.UnmapGPUTransferBuffer(gpu, tex_transfer_buf)

	copy_cmd_buf := sdl.AcquireGPUCommandBuffer(gpu)

	copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)

	sdl.UploadToGPUBuffer(copy_pass,
		{transfer_buffer = transfer_buf},
		{buffer = vertex_buf, size = u32(vertices_byte_size)},
		false
	)

	sdl.UploadToGPUBuffer(copy_pass,
		{transfer_buffer = transfer_buf, offset = u32(vertices_byte_size)},
		{buffer = index_buf, size = u32(indices_byte_size)},
		false
	)

	sdl.UploadToGPUTexture(copy_pass,
		{transfer_buffer = tex_transfer_buf},
		{texture = texture, w = u32(img_size.x), h = u32(img_size.y), d = 1},
		false
	)

	sdl.EndGPUCopyPass(copy_pass)

	ok := sdl.SubmitGPUCommandBuffer(copy_cmd_buf); assert(ok)

	sdl.ReleaseGPUTransferBuffer(gpu, transfer_buf)
	sdl.ReleaseGPUTransferBuffer(gpu, tex_transfer_buf)

	return {
		vertex_buf = vertex_buf,
		index_buf = index_buf,
		num_indices = u32(num_indices),
		texture = texture,
	}
}

update_camera :: proc(dt: f32) {
	move_input: Vec2
	if key_down[.W] do move_input.y = 1
	else if key_down[.S] do move_input.y = -1
	if key_down[.A] do move_input.x = -1
	else if key_down[.D] do move_input.x = 1

	look_input := mouse_move * LOOK_SENSITIVITY

	look.yaw = math.wrap(look.yaw - look_input.x, 360)
	look.pitch = math.clamp(look.pitch - look_input.y, -89, 89)

	look_mat := linalg.matrix3_from_yaw_pitch_roll_f32(linalg.to_radians(look.yaw), linalg.to_radians(look.pitch), 0)

	forward := look_mat * Vec3 {0,0,-1}
	right := look_mat * Vec3 {1,0,0}
	move_dir := forward * move_input.y + right * move_input.x
	move_dir.y = 0

	motion := linalg.normalize0(move_dir) * MOVE_SPEED * dt

	camera.position += motion
	camera.target = camera.position + forward
}

main :: proc() {
	context.logger = log.create_console_logger()
	default_context = context

	init()
	setup_pipeline()
	model := load_model("tractor-police.obj", "colormap.png")

	ROTATION_SPEED := linalg.to_radians(f32(90))
	rotation := f32(0)
	rotate := true

	proj_mat := linalg.matrix4_perspective_f32(linalg.to_radians(f32(70)), f32(win_size.x) / f32(win_size.y), 0.0001, 1000)

	UBO :: struct {
		mvp: matrix[4,4]f32,
	}

	last_ticks := sdl.GetTicks()
	clear_color := sdl.FColor {0, 0.023, 0.133, 1}

	main_loop: for {
		free_all(context.temp_allocator)
		mouse_move = {}

		new_ticks := sdl.GetTicks()
		delta_time := f32(new_ticks - last_ticks) / 1000
		last_ticks = new_ticks

		ui_input_mode := !sdl.GetWindowRelativeMouseMode(window)

		// process events
		ev: sdl.Event
		for sdl.PollEvent(&ev) {
			if ui_input_mode do im_sdl.ProcessEvent(&ev)

			#partial switch ev.type {
				case .QUIT:
					break main_loop
				case .KEY_DOWN:
					if !ui_input_mode {
						if ev.key.scancode == .ESCAPE do break main_loop
						key_down[ev.key.scancode] = true
					}
				case .KEY_UP:
					if !ui_input_mode {
						key_down[ev.key.scancode] = false
					}
				case .MOUSE_MOTION:
					if !ui_input_mode {
						mouse_move += {ev.motion.xrel, ev.motion.yrel}
					}
				case .MOUSE_BUTTON_DOWN:
					if ev.button.button == 2 {
						ui_input_mode = !ui_input_mode
						_ = sdl.SetWindowRelativeMouseMode(window, !ui_input_mode)
					}
			}
		}

		im_sdlgpu.NewFrame()
		im_sdl.NewFrame()
		im.NewFrame()

		if im.Begin("Inspector") {
			im.Checkbox("Rotate", &rotate)
			im.ColorEdit3("Clear color", transmute(^[3]f32)&clear_color, {.Float})
		}
		im.End()

		// update game state
		if rotate do rotation += ROTATION_SPEED * delta_time
		update_camera(delta_time)

		// render
		cmd_buf := sdl.AcquireGPUCommandBuffer(gpu)
		swapchain_tex: ^sdl.GPUTexture
		ok := sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, window, &swapchain_tex, nil, nil); assert(ok)

		view_mat := linalg.matrix4_look_at_f32(camera.position, camera.target, {0,1,0})
		model_mat := linalg.matrix4_translate_f32({0, 0, 0}) * linalg.matrix4_rotate_f32(rotation, {0,1,0})

		ubo := UBO {
			mvp = proj_mat * view_mat * model_mat,
		}

		im.Render()
		im_draw_data := im.GetDrawData()

		if swapchain_tex != nil {
			color_target := sdl.GPUColorTargetInfo {
				texture = swapchain_tex,
				load_op = .CLEAR,
				clear_color = clear_color,
				store_op = .STORE
			}
			depth_target_info := sdl.GPUDepthStencilTargetInfo {
				texture = depth_texture,
				load_op = .CLEAR,
				clear_depth = 1,
				store_op = .DONT_CARE
			}
			render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, &depth_target_info)
			sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo, size_of(ubo))
			sdl.BindGPUGraphicsPipeline(render_pass, pipeline)
			sdl.BindGPUVertexBuffers(render_pass, 0, &(sdl.GPUBufferBinding { buffer = model.vertex_buf }), 1)
			sdl.BindGPUIndexBuffer(render_pass, { buffer = model.index_buf }, ._16BIT)
			sdl.BindGPUFragmentSamplers(render_pass, 0, &(sdl.GPUTextureSamplerBinding {texture = model.texture, sampler = sampler}), 1)
			sdl.DrawGPUIndexedPrimitives(render_pass, model.num_indices, 1, 0, 0, 0)
			sdl.EndGPURenderPass(render_pass)

			im_sdlgpu.PrepareDrawData(im_draw_data, cmd_buf)
			im_color_target := sdl.GPUColorTargetInfo {
				texture = swapchain_tex,
				load_op = .LOAD,
				store_op = .STORE
			}
			im_render_pass := sdl.BeginGPURenderPass(cmd_buf, &im_color_target, 1, nil)
			im_sdlgpu.RenderDrawData(im_draw_data, cmd_buf, render_pass)
			sdl.EndGPURenderPass(im_render_pass)
		}

		ok = sdl.SubmitGPUCommandBuffer(cmd_buf); assert(ok)
	}
}

load_shader :: proc(device: ^sdl.GPUDevice, shaderfile: string) -> ^sdl.GPUShader {
	stage: sdl.GPUShaderStage
	switch filepath.ext(shaderfile) {
	case ".vert":
		stage = .VERTEX
	case ".frag":
		stage = .FRAGMENT
	}

	format: sdl.GPUShaderFormatFlag
	format_ext: string
	entrypoint: cstring = "main"

	supported_formats := sdl.GetGPUShaderFormats(device)
	if .SPIRV in supported_formats {
		format = .SPIRV
		format_ext = ".spv"
	} else if .MSL in supported_formats {
		format = .MSL
		format_ext = ".msl"
		entrypoint = "main0"
	} else if .DXIL in supported_formats {
		format = .DXIL
		format_ext = ".dxil"
	} else {
		log.panicf("No supported shader format: {}", supported_formats)
	}

	shaderfile := filepath.join({CONTENT_DIR, "shaders", "out", shaderfile}, context.temp_allocator)
	filename := strings.concatenate({shaderfile, format_ext})
	code, ok := os.read_entire_file_from_filename(filename, context.temp_allocator); assert(ok)

	info := load_shader_info(shaderfile)

	return sdl.CreateGPUShader(device, {
		code_size = len(code),
		code = raw_data(code),
		entrypoint = entrypoint,
		format = {format},
		stage = stage,
		num_uniform_buffers = info.uniform_buffers,
		num_samplers = info.samplers,
		num_storage_buffers = info.storage_buffers,
		num_storage_textures = info.storage_textures,
	})
}

Shader_Info :: struct {
	samplers: u32,
	storage_textures: u32,
	storage_buffers: u32,
	uniform_buffers: u32,
}

load_shader_info :: proc(shaderfile: string) -> Shader_Info {
	json_filename := strings.concatenate({shaderfile, ".json"}, context.temp_allocator)
	json_data, ok := os.read_entire_file_from_filename(json_filename, context.temp_allocator); assert(ok)
	result: Shader_Info
	err := json.unmarshal(json_data, &result, allocator = context.temp_allocator); assert(err == nil)
	return result
}
