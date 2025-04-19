package main

import "core:path/filepath"
import "core:strings"
import "core:slice"
import stbi "vendor:stb/image"
import sdl "vendor:sdl3"

load_pixels :: proc(texture_file: string) -> (pixels: []byte, size: [2]u32) {
	texture_path := filepath.join({CONTENT_DIR, "textures", texture_file}, context.temp_allocator)

	texture_file := strings.clone_to_cstring(texture_path, context.temp_allocator)

	img_size: [2]i32
	pixels_data := stbi.load(texture_file, &img_size.x, &img_size.y, nil, 4); assert(pixels_data != nil)
	pixels_byte_size := img_size.x * img_size.y * 4

	pixels = slice.bytes_from_ptr(pixels_data, int(pixels_byte_size))
	size = {u32(img_size.x), u32(img_size.y)}
	return
}

free_pixels :: proc(pixels: []byte) {
	stbi.image_free(raw_data(pixels))
}

load_texture_file :: proc(copy_pass: ^sdl.GPUCopyPass, texture_file: string) -> ^sdl.GPUTexture {
	pixels, img_size := load_pixels(texture_file)
	texture := upload_texture(copy_pass, pixels, img_size.x, img_size.y)
	free_pixels(pixels)
	return texture
}

load_cubemap_texture_single :: proc(copy_pass: ^sdl.GPUCopyPass, texture_file: string) -> ^sdl.GPUTexture {
	pixels, img_size := load_pixels(texture_file)
	texture := upload_cubemap_texture_single(copy_pass, pixels, img_size.x, img_size.y)
	free_pixels(pixels)
	return texture
}

load_cubemap_texture_files :: proc(copy_pass: ^sdl.GPUCopyPass, texture_files: [sdl.GPUCubeMapFace]string) -> ^sdl.GPUTexture {
	pixels: [sdl.GPUCubeMapFace][]byte
	size: u32
	for texture_file, side in texture_files {
		side_pixels, img_size := load_pixels(texture_file)
		pixels[side] = side_pixels
		assert(img_size.x == img_size.y)
		if size == 0 {
			size = img_size.x
		} else {
			assert(img_size.x == size)
		}
	}

	texture := upload_cubemap_texture_sides(copy_pass, pixels, size)

	for side_pixels in pixels do free_pixels(side_pixels)

	return texture
}

load_obj_file :: proc(copy_pass: ^sdl.GPUCopyPass, mesh_file: string) -> Mesh {
	mesh_path := filepath.join({CONTENT_DIR, "meshes", mesh_file}, context.temp_allocator)
	obj_data := obj_load(mesh_path)

	vertices := make([]Vertex_Data, len(obj_data.faces))
	indices := make([]u16, len(obj_data.faces))

	for face, i in obj_data.faces {
		uv := obj_data.uvs[face.uv]
		vertices[i] = {
			pos = obj_data.positions[face.pos],
			normal = obj_data.normals[face.normal],
			color = WHITE,
			uv = {uv.x, 1-uv.y},
		}
		indices[i] = u16(i)
	}

	obj_destroy(obj_data)

	mesh := upload_mesh(copy_pass, vertices, indices)

	delete(indices)
	delete(vertices)

	return mesh
}
