package main

import "core:path/filepath"
import "core:strings"
import "core:slice"
import stbi "vendor:stb/image"
import sdl "vendor:sdl3"

load_texture_file :: proc(copy_pass: ^sdl.GPUCopyPass, texture_file: string) -> ^sdl.GPUTexture {
	texture_path := filepath.join({CONTENT_DIR, "textures", texture_file}, context.temp_allocator)

	texture_file := strings.clone_to_cstring(texture_path, context.temp_allocator)

	img_size: [2]i32
	pixels := stbi.load(texture_file, &img_size.x, &img_size.y, nil, 4); assert(pixels != nil)
	pixels_byte_size := img_size.x * img_size.y * 4

	texture := upload_texture(copy_pass, slice.bytes_from_ptr(pixels, int(pixels_byte_size)), u32(img_size.x), u32(img_size.y))

	stbi.image_free(pixels)

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

load_model :: proc(copy_pass: ^sdl.GPUCopyPass, mesh_file: string, texture_file: string) -> Model {
	texture := load_texture_file(copy_pass, texture_file)
	mesh := load_obj_file(copy_pass, mesh_file)
	return {
		mesh = mesh,
		texture = texture,
	}
}

