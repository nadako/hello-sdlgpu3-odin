package main

import "core:mem"
import "core:slice"
import sdl "vendor:sdl3"

upload_texture :: proc(copy_pass: ^sdl.GPUCopyPass, pixels: []byte, width, height: u32) -> ^sdl.GPUTexture {
	texture := sdl.CreateGPUTexture(g.gpu, {
		type = .D2,
		format = .R8G8B8A8_UNORM_SRGB, // pixels are in sRGB, converted to linear in shaders
		usage = {.SAMPLER},
		width = width,
		height = height,
		layer_count_or_depth = 1,
		num_levels = 1,
	})

	tex_transfer_buf := sdl.CreateGPUTransferBuffer(g.gpu, {
		usage = .UPLOAD,
		size = u32(len(pixels))
	})
	tex_transfer_mem := sdl.MapGPUTransferBuffer(g.gpu, tex_transfer_buf, false)
	mem.copy(tex_transfer_mem, raw_data(pixels), len(pixels))
	sdl.UnmapGPUTransferBuffer(g.gpu, tex_transfer_buf)

	sdl.UploadToGPUTexture(copy_pass,
		{transfer_buffer = tex_transfer_buf},
		{texture = texture, w = width, h = height, d = 1},
		false
	)

	sdl.ReleaseGPUTransferBuffer(g.gpu, tex_transfer_buf)

	return texture
}

upload_cubemap_texture_sides :: proc(copy_pass: ^sdl.GPUCopyPass, pixels: [sdl.GPUCubeMapFace][]byte, size: u32) -> ^sdl.GPUTexture {
	texture := sdl.CreateGPUTexture(g.gpu, {
		type = .CUBE,
		format = .R8G8B8A8_UNORM_SRGB, // pixels are in sRGB, converted to linear in shaders
		usage = {.SAMPLER},
		width = size,
		height = size,
		layer_count_or_depth = 6,
		num_levels = 1,
	})

	side_byte_size := int(size * size * 4) // 4 bytes per pixel
	for side_pixels in pixels do assert(len(side_pixels) == side_byte_size)

	tex_transfer_buf := sdl.CreateGPUTransferBuffer(g.gpu, {
		usage = .UPLOAD,
		size = u32(side_byte_size * 6)
	})
	tex_transfer_mem := transmute([^]byte)sdl.MapGPUTransferBuffer(g.gpu, tex_transfer_buf, false)

	offset := 0
	for side_pixels in pixels {
		mem.copy(tex_transfer_mem[offset:], raw_data(side_pixels), side_byte_size)
		offset += side_byte_size
	}

	sdl.UnmapGPUTransferBuffer(g.gpu, tex_transfer_buf)

	offset = 0
	for side_pixels, side in pixels {
		sdl.UploadToGPUTexture(copy_pass,
			{transfer_buffer = tex_transfer_buf, offset = u32(offset)},
			{texture = texture, layer = u32(side), w = size, h = size, d = 1},
			false
		)
		offset += side_byte_size
	}

	sdl.ReleaseGPUTransferBuffer(g.gpu, tex_transfer_buf)

	return texture
}

upload_mesh :: proc(copy_pass: ^sdl.GPUCopyPass, vertices: []$T, indices: []$S) -> Mesh {
	return upload_mesh_bytes(copy_pass, slice.to_bytes(vertices), slice.to_bytes(indices), len(indices))
}

upload_mesh_bytes :: proc(copy_pass: ^sdl.GPUCopyPass, vertices: []byte, indices: []byte, num_indices: int) -> Mesh {
	vertices_byte_size := len(vertices)
	indices_byte_size := len(indices)

	vertex_buf := sdl.CreateGPUBuffer(g.gpu, {
		usage = {.VERTEX},
		size = u32(vertices_byte_size)
	})

	index_buf := sdl.CreateGPUBuffer(g.gpu, {
		usage = {.INDEX},
		size = u32(indices_byte_size)
	})

	transfer_buf := sdl.CreateGPUTransferBuffer(g.gpu, {
		usage = .UPLOAD,
		size = u32(vertices_byte_size + indices_byte_size)
	})

	transfer_mem := transmute([^]byte)sdl.MapGPUTransferBuffer(g.gpu, transfer_buf, false)
	mem.copy(transfer_mem, raw_data(vertices), vertices_byte_size)
	mem.copy(transfer_mem[vertices_byte_size:], raw_data(indices), indices_byte_size)
	sdl.UnmapGPUTransferBuffer(g.gpu, transfer_buf)

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

	sdl.ReleaseGPUTransferBuffer(g.gpu, transfer_buf)

	return {
		vertex_buf = vertex_buf,
		index_buf = index_buf,
		num_indices = u32(num_indices),
	}
}
