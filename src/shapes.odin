package main

import sdl "vendor:sdl3"

// TODO: add texture coord scaling

generate_plane_mesh :: proc(copy_pass: ^sdl.GPUCopyPass, width, depth: f32, segments_x: int = 1, segments_z: int = 1) -> Mesh {
	num_vertices := get_plane_num_vertices(segments_x, segments_z)
	num_indices := get_plane_num_indices(segments_x, segments_z)

	vertices := make([]Vertex_Data, num_vertices)
	indices := make([]u16, num_indices)
	defer {
		delete(vertices)
		delete(indices)
	}

	xLeft := -width * 0.5
	zFront := depth * 0.5

	xRight := width * 0.5
	zBack := -depth * 0.5

	dx := width / f32(segments_x)
	dz := -depth / f32(segments_z)

	ctx := Shape_Context {
		vertices = vertices,
		indices = indices,
	}

	build_plane(&ctx,
		start_pos = {xLeft, 0, zFront},
		start_uv = {0, 1},
		normal = {0, 1, 0},
		row = {segments_x, {dx, 0, 0}, {1 / f32(segments_x), 0}},
		col = {segments_z, {0, 0, dz}, {0, -1 / f32(segments_z)}},
	)

	return upload_mesh(copy_pass, vertices, indices)
}

generate_box_mesh :: proc(copy_pass: ^sdl.GPUCopyPass, width, height, depth: f32, segments_x: int = 1, segments_y: int = 1, segments_z: int = 1) -> Mesh {
	num_vertices := (
		get_plane_num_vertices(segments_x, segments_y) * 2 + // front/back
		get_plane_num_vertices(segments_x, segments_z) * 2 + // top/bottom
		get_plane_num_vertices(segments_z, segments_y) * 2)  // left/right
	num_indices := (
		get_plane_num_indices(segments_x, segments_y) * 2 + // front/back
		get_plane_num_indices(segments_x, segments_z) * 2 + // top/bottom
		get_plane_num_indices(segments_z, segments_y) * 2)  // left/right

	vertices := make([]Vertex_Data, num_vertices)
	indices := make([]u16, num_indices)
	defer {
		delete(vertices)
		delete(indices)
	}

	xLeft := -width * 0.5
	yTop := height * 0.5
	zFront := depth * 0.5

	xRight := width * 0.5
	yBottom := -height * 0.5
	zBack := -depth * 0.5

	dx := width / f32(segments_x)
	dy := -height / f32(segments_y)
	dz := -depth / f32(segments_z)

	ctx := Shape_Context {
		vertices = vertices,
		indices = indices
	}

	// top
	build_plane(&ctx,
		start_pos = {xLeft, yTop, zFront},
		start_uv = {0, 1},
		normal = {0, 1, 0},
		row = {segments_x, {dx, 0, 0}, {1 / f32(segments_x), 0}},
		col = {segments_z, {0, 0, dz}, {0, -1 / f32(segments_z)}},
	)

	// bottom
	build_plane(&ctx,
		start_pos = {xRight, yBottom, zFront},
		start_uv = {0, 1},
		normal = {0, -1, 0},
		row = {segments_x, {-dx, 0, 0}, {1 / f32(segments_x), 0}},
		col = {segments_z, {0, 0, dz}, {0, -1 / f32(segments_z)}},
	)

	// left
	build_plane(&ctx,
		start_pos = {xLeft, yTop, zFront},
		start_uv = {1, 0},
		normal = {-1, 0, 0},
		row = {segments_z, {0, 0, dz}, {-1 / f32(segments_z), 0}},
		col = {segments_y, {0, dy, 0}, {0, 1 / f32(segments_y)}},
	)

	// right
	build_plane(&ctx,
		start_pos = {xRight, yTop, zBack},
		start_uv = {1, 0},
		normal = {1, 0, 0},
		row = {segments_z, {0, 0, -dz}, {-1 / f32(segments_z), 0}},
		col = {segments_y, {0, dy, 0}, {0, 1 / f32(segments_y)}},
	)

	// front
	build_plane(&ctx,
		start_pos = {xLeft, yTop, zFront},
		start_uv = {0, 0},
		normal = {0, 0, 1},
		row = {segments_y, {0, dy, 0}, {0, 1 / f32(segments_y)}},
		col = {segments_x, {dx, 0, 0}, {1 / f32(segments_x), 0}},
	)

	// back
	build_plane(&ctx,
		start_pos = {xRight, yTop, zBack},
		start_uv = {0, 0},
		normal = {0, 0, -1},
		row = {segments_y, {0, dy, 0}, {0, 1 / f32(segments_y)}},
		col = {segments_x, {-dx, 0, 0}, {1 / f32(segments_x), 0}},
	)

	return upload_mesh(copy_pass, vertices, indices)
}

@(private)
Shape_Context :: struct {
	vertices: []Vertex_Data,
	indices: []u16,
	next_vertex_id: int,
	next_index_id: int,
}

@(private)
add_vertex :: proc(ctx: ^Shape_Context, vertex: Vertex_Data) {
	ctx.vertices[ctx.next_vertex_id] = vertex
	ctx.next_vertex_id += 1
}

@(private)
add_triangle :: proc(ctx: ^Shape_Context, a, b, c: u16) {
	ctx.indices[ctx.next_index_id + 0] = a
	ctx.indices[ctx.next_index_id + 1] = b
	ctx.indices[ctx.next_index_id + 2] = c
	ctx.next_index_id += 3
}

@(private)
Plane_Side :: struct {
	segments: int,
	pos_step: Vec3,
	uv_step: Vec2,
}

@(private)
build_plane :: proc(ctx: ^Shape_Context, start_pos: Vec3, start_uv: Vec2, normal: Vec3, row: Plane_Side, col: Plane_Side) {
	start_index := u16(ctx.next_vertex_id)

	row_pos := start_pos
	row_uv := start_uv
	for _ in 0 ..= row.segments {
		col_pos := row_pos
		col_uv := row_uv
		for _ in 0 ..= col.segments {
			add_vertex(ctx, {
				pos = col_pos,
				normal = normal,
				uv = col_uv,
				color = WHITE,
			})
			col_pos += col.pos_step
			col_uv += col.uv_step
		}
		row_pos += row.pos_step
		row_uv += row.uv_step
	}

	for r in 0 ..< u16(row.segments) {
		for c in 0 ..< u16(col.segments) {
			i00 := start_index + r * u16(col.segments + 1) + c
			i10 := i00 + 1
			i01 := i00 + u16(col.segments + 1)
			i11 := i01 + 1
			add_triangle(ctx, i00, i01, i10)
			add_triangle(ctx, i01, i11, i10)
		}
	}
}

@(private)
get_plane_num_vertices :: proc(row_segments, col_segments: int) -> int {
	return (row_segments + 1) * (col_segments + 1)
}

@(private)
get_plane_num_indices :: proc(row_segments, col_segments: int) -> int {
	return row_segments * col_segments * 3 * 2
}

