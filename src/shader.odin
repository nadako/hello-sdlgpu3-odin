package main

import "core:strings"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:encoding/json"
import sdl "vendor:sdl3"

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
	filename := strings.concatenate({shaderfile, format_ext}, context.temp_allocator)
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
