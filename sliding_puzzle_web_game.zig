// A web port of a desktop sliding puzzle game made in Zig.
// 
// At no stage in this port was any native .js code written,
// (but .js browser functions are called), this is acheived
// by using the zjb library.
//
// As such, the entire game is basically contained within the
// .WASM that this code (together with the Zig build system)
// generates. (The build system automatically generates the
// binding .js .WASM code needed to call functions from outside
// the .WASM.)
//
// Created by 10aded throughout March 2025. 
//
// Build this example with the command:
//
//     zig build looping_fractal -Doptimize=Fast
//
// run in the top directory of the project.
//
// NOTE: In Zig 0.13.0, compiling the project in .Debug mode FAILS!
//
// (A runtime "index out of bounds" error ensures. This, bizarrely,
// does not occur when compiler in .ReleaseSafe or .ReleaseFast.)
//
// By reducing the size of the .qoi files enough, the project
// can compile in .Debug mode.
//
// This creates a static webpage in ./zig-out/bin ; to run the
// webpage spawn a web server from within ./zig-out/bin (e.g.
// with python via
//
//     python -m http.server
//
// and then access the url localhost:8000 in a web browser.
//
// Building the project requires a Zig compiler of at least
// version 0.13.0. It can be easily and freely downloaded at:
//
//     https://ziglang.org/download/
//
// The entire source code of this project is available on GitHub at:
//
//     https://github.com/10aded/Zig-WebGL-WASM-Examples
//
// This code heavily relies on Scott Redig's Zig Javascript
// Bridge library (zjb), available at:
//
//     https://github.com/scottredig/zig-javascript-bridge
//
// Zjb has a MIT license, see the link / included dependency
// for more details.
//
// These example and others were developed (almost) entirely
// on the Twitch channel 10aded; copies of the stream are
// on YouTube at the @10aded channel.

var temp = true;

const std = @import("std");
const zjb = @import("zjb");
const qoi = @import("./Dependencies/qoi.zig");

const vertex_background_source   = @embedFile("./Shaders/vertex-background.glsl");
const fragment_background_source = @embedFile("./Shaders/fragment-background.glsl");

const vertex_color_texture_source   = @embedFile("./Shaders/vertex-color-texture.glsl");
const fragment_color_texture_source = @embedFile("./Shaders/fragment-color-texture.glsl");

const PI : f32 = std.math.pi;

// On itch, when games are uploaded as a zipped website,
// the dimensions of the window are set; we choose the
// values below.
const CANVAS_DIMS : @Vector(2, i32) = .{800, 800};

const GRID_DIMENSION = 3;

// Constants
const TILE_NUMBER = GRID_DIMENSION * GRID_DIMENSION;

// Colors
const WHITE       = Color{255,   255,  255, 255};
const MAGENTA     = Color{255,     0,  255, 255};
const GRID_BLUE   = Color{0x3e, 0x48, 0x5f, 255};
const SPACE_BLACK = Color{0x03, 0x03, 0x05, 255};

const DEBUG_COLOR       = MAGENTA;
const GRID_BACKGROUND   = WHITE;
const TILE_BORDER       = GRID_BLUE;

// Shader
const BACKGROUND_SHADER_SHAPE_CHANGE_TIME = 200;

// Grid geometry.
// NOTE: It is assumed that the window dimensions of the game
// will NOT change.
const TILE_WIDTH : f32  = 0.125 * canvas_dims_f32[0];
const TILE_BORDER_WIDTH = 0.05  * TILE_WIDTH;
const TILE_SPACING      = 0.02  * TILE_WIDTH;

const canvas_dims_f32 : Vec2 = @floatFromInt(CANVAS_DIMS);
const half_splat      : Vec2 = @splat(0.5);
const CENTER = half_splat * canvas_dims_f32;

const GRID_WIDTH = GRID_DIMENSION * TILE_WIDTH + (GRID_DIMENSION + 1) * TILE_SPACING + 2 * GRID_DIMENSION * TILE_BORDER_WIDTH;


// Type aliases.
const Vec2  = @Vector(2, f32);
const Vec4  = @Vector(4, f32);
const Color = @Vector(4, u8);

// WebGL constants obtained from the WebGL specification at:
// https://registry.khronos.org/webgl/specs/1.0.0/
const gl_FLOAT            : i32 = 0x1406; 
const gl_ARRAY_BUFFER     : i32 = 0x8892;
const gl_STATIC_DRAW      : i32 = 0x88E4;
const gl_DYNAMIC_DRAW     : i32 = 0x88E8;
const gl_COLOR_BUFFER_BIT : i32 = 0x4000;
const gl_TRIANGLES        : i32 = 0x0004;

const gl_VERTEX_SHADER    : i32 = 0x8B31;
const gl_FRAGMENT_SHADER  : i32 = 0x8B30;
const gl_COMPILE_STATUS   : i32 = 0x8B81;
const gl_LINK_STATUS      : i32 = 0x8B82;

const gl_TEXTURE0           : i32 = 0x84C0;
const gl_TEXTURE_2D         : i32 = 0x0DE1;
const gl_TEXTURE_WRAP_S     : i32 = 0x2802;
const gl_TEXTURE_WRAP_T     : i32 = 0x2803;
const gl_CLAMP_TO_EDGE      : i32 = 0x812F;
const gl_TEXTURE_MAG_FILTER : i32 = 0x2800;
const gl_TEXTURE_MIN_FILTER : i32 = 0x2801;
const gl_NEAREST            : i32 = 0x2600;

const gl_RGBA               : i32 = 0x1908;
const gl_UNSIGNED_BYTE      : i32 = 0x1401; // NOTE below!

// NOTE: in WebGL specification,  UNSIGNED_BYTE is commented out in
// /* PixelType */, the constant still seems to work though.

// Globals
// Game logic.
var is_won = false;

// WebGL
var glcontext  : zjb.Handle = undefined;
var global_vbo : zjb.Handle = undefined;

var background_shader_program    : zjb.Handle = undefined;
var color_texture_shader_program : zjb.Handle = undefined;

var blue_marble_texture  : zjb.Handle = undefined;
var quote_texture        : zjb.Handle = undefined;

// Grid
// Convention: the left to right array layout represents the grid
// per row from left to right, top to bottom.
var grid : [TILE_NUMBER] u8 = undefined;

// Grid movement
const GridMovementDirection = enum (u8) {
    NONE,
    UP,
    LEFT,
    DOWN,
    RIGHT,
};

var current_tile_movement_direction : GridMovementDirection = .NONE;

// Random number generator
var global_prng : XorShiftPRNG = undefined;

// Animation
const ANIMATION_SLIDING_TILE_TIME : f32 = 0.15;
const ANIMATION_WON_TIME          : f32 = 3;
const ANIMATION_QUOTE_TIME        : f32 = 3;

var animating_tile : u8 = 0;
var animation_direction : GridMovementDirection = undefined;

var animation_tile_fraction  : f32 = 0;
var animation_won_fraction   : f32 = 0;
var animation_quote_fraction : f32 = 0;

// Keyboard
const KeyState = packed struct (u8) {
    w           : bool,
    a           : bool,
    s           : bool,
    d           : bool,
    up_arrow    : bool,
    left_arrow  : bool,
    down_arrow  : bool,
    right_arrow : bool,
};

var keyDownLastFrame : KeyState = @bitCast(@as(u8, 0));
var keyDown          : KeyState = @bitCast(@as(u8, 0));
var keyPress         : KeyState = @bitCast(@as(u8, 0));

// Timestamp
var initial_seconds         : f64 = undefined;
var current_seconds         : f64 = undefined;
var animation_start_seconds : f32 = undefined;
var won_start_seconds       : f32 = undefined;

fn log(v: anytype) void {
    zjb.global("console").call("log", .{v}, void);
}

fn logStr(str: []const u8) void {
    const handle = zjb.string(str);
    defer handle.release();
    zjb.global("console").call("log", .{handle}, void);
}

// The photo of Pluto below was taken by the New Horizons spacecraft,
// see the header of this file for more information.
const blue_marble_qoi = @embedFile("./Assets/blue_marble_480.qoi");
const blue_marble_header = qoi.comptime_header_parser(blue_marble_qoi);
const blue_marble_width  = blue_marble_header.image_width;
const blue_marble_height = blue_marble_header.image_height;
var blue_marble_pixel_bytes : [4 * blue_marble_width * blue_marble_height] u8 = undefined;

const quote_qoi = @embedFile("./Assets/quote.qoi");
const quote_header = qoi.comptime_header_parser(quote_qoi);
const quote_width  = quote_header.image_width;
const quote_height = quote_header.image_height;
var quote_pixel_bytes : [4 * quote_width * quote_height] u8 = undefined;

// Note for above:
// In order to call gl.texImage2D to make a texture,
// the bytes need to be in a Uint8Array (when gl.UNSIGNED_BYTE) is
// called. (See: https://developer.mozilla.org/en-US/docs/Web/API/WebGLRenderingContext/texImage2D)
// So, without knowing if the WASM will store @Vector(4, u8) in the
// packed way as in x86_64, here were first decompress the .qoi
// into an array of @Vector(4, u8), then convert it to a [] u8.
// It would be EASY to modify the qoi decompressor to directly
// convert it to [] u8 but this is what we're doing for now!

// NOTE: As of Zig 0.13.0, upon trying to @ptrCast([] Vec(4, u8)) to
// [] u8 ... if this is even sensible to begin with... we get a
// TODO: implement @ptrCast between slices changing the length compile error.

// Geometry
const ColorTextureVertex = extern struct {
    x  : f32,
    y  : f32,
    r  : f32,
    g  : f32,
    b  : f32,
    tx : f32,
    ty : f32,
    l  : f32, 
};

fn colorTextureVertex( x : f32, y : f32, r : f32, g : f32, b :f32, tx : f32, ty : f32, l : f32) ColorTextureVertex {
    return ColorTextureVertex{.x = x, .y = y, .r = r, .g = g, .b = b, .tx = tx, .ty = ty, .l = l};
}

// Note: The size of the vertex_buffer assumes the game will
// not have a grid larger than 6 x 6.
var vertex_buffer : [500] ColorTextureVertex = undefined;
var vertex_buffer_index : usize = 0;

const Rectangle = struct {
    center : Vec2,
    width  : f32,
    height : f32,
};

fn rectangle(pos : Vec2, width : f32, height : f32) Rectangle {
    return Rectangle{.center = pos, .width = width, .height = height};
}

export fn main() void {
    init_clock();

    init_grid();

    decompress_images();
    
    init_webgl_context();

    compile_shaders();

    create_bind_textures();
    
    animationFrame(initial_seconds);
}

fn animationFrame(timestamp: f64) callconv(.C) void {
    // NOTE: The timestamp is in milliseconds.
    current_seconds = timestamp / 1000;

    process_input();

    update_state();
    
    compute_grid_geometry();

    render();

    zjb.ConstHandle.global.call("requestAnimationFrame", .{zjb.fnHandle("animationFrame", animationFrame)}, void);
}


fn init_grid() void {
    // Initialize PRNG.
    const seed : u64 = @bitCast(initial_seconds);
    global_prng = initialize_xorshiftprng(seed);

    // NOTE: Initializing the grid with a random shuffle will produce
    // a puzzle that is IMPOSSIBLE to solve 50% of the time. (This
    // fact is left as a highly recommended exercise to the reader.)
    //
    // Additionally, from a starting solved state randomly applying
    // grid moves will not in general create a grid that is
    // "sufficiently" shuffled. See, for example:
    //
    //     https://en.wikipedia.org/wiki/Random_walk#Lattice_random_walk
    //
    // As such we apply a SMALL number of pre-generated shuffles that
    // make the grid appear "randomly" shuffled.

    // File the grid with 0, 1, 2, ... , TILE_NUMBER - 1.
    grid = std.simd.iota(u8, TILE_NUMBER);

    // Some prerecorded tile shuffles.
    const shuffle1 = [_] u8 {2, 1, 4, 1, 2, 3, 2, 1, 4, 1, 2, 3, 4, 2, 2, 1, 4, 4, 3, 2, 3, 2, 1, 4, 3, 3, 4, 1, 1, 1, 4, 3, 2, 2, 3, 4, 1, 2, 1, 4, 3, 2, 3, 4, 3, 2, 1, 2, 3, 4, 4, 1, 1, 4, 3, 2, 1, 3, 1, 4, 1, 2, 2, 2, 3, 4, 4, 3, 2, 1, 4, 4, 3, 2, 2, 2, 3, 4, 1, 1, 4, 3, 3, 4, 1, 1, 2, 2, 3, 4, 1, 4, 1, 2, 2, 3, 4, 3, 2, 1, 2, 1, 4, 3, 3, 4, 3, 2, 2, 1, 4, 3, 4, 4, 2, 2, 1, 1, 2, 1, 4, 4, 3, 3, 2, 1, 4, 3, 2, 1, 4, 3, 4, 3, 2, 3, 1, 2, 3, 4, 1, 2, 3, 4, 1, 1, 4, 3, 2, 3, 4};

    const shuffle2 = [_] u8 {2, 2, 1, 4, 4, 2, 1, 1, 2, 3, 4, 3, 2, 2, 4, 3, 4, 1, 1, 1, 4, 3, 3, 2, 1, 4, 3, 2, 2, 1, 4, 3, 2, 2, 1, 4, 1, 2, 3, 4, 4, 1, 3, 3, 2, 1, 4, 3, 3, 2, 1, 4, 3, 4, 1, 1, 2, 1, 2, 3, 4, 3, 2, 2, 3, 4, 1, 1, 4, 2, 1, 2, 3, 4, 4, 3, 4, 1, 3, 2, 3, 4, 1, 1, 2, 1, 4, 3, 2, 2, 3, 4, 1, 2, 3, 2, 1, 4, 3, 3, 4, 4, 1, 1, 1, 2, 3, 4, 2, 2, 3, 4, 1, 2, 3, 4, 4, 3, 2, 2, 2, 1, 1, 1, 4, 3, 3, 2, 3, 4, 1, 2, 1, 4, 1, 2, 3, 4, 4, 3, 4, 3};

    const shuffles = [2] [] const u8 {shuffle1[0..], shuffle2[0..]};
    // Apply these each a couple of times, randomly.
    
    const NUMBER_OF_SHUFFLES = 10;
    
    var shuffle_index : usize = 0;
    while (shuffle_index < NUMBER_OF_SHUFFLES) : (shuffle_index += 1) {
        const random_int = get_randomish_byte_up_to(2);
        const random_shuffle = shuffles[random_int];

        for (random_shuffle) |dir| {
            const move_direction : GridMovementDirection = @enumFromInt(dir);
            try_grid_update(move_direction);
        }
    }
}

fn compute_grid_geometry() void {

    // Reset the vertex_buffer.
    vertex_buffer_index = 0;
    
    const lambda = animation_won_fraction;
        
    // Compute the tile rectangles.
    const background_grid_rectangle = rectangle(CENTER, GRID_WIDTH, GRID_WIDTH);

    var grid_tile_rectangles : [TILE_NUMBER] Rectangle = undefined;

    const TOP_LEFT_TILE_POSX = CENTER[0] - 0.5 * GRID_WIDTH + TILE_SPACING + TILE_BORDER_WIDTH + 0.5 * TILE_WIDTH;
    const TOP_LEFT_TILE_POSY = TOP_LEFT_TILE_POSX;

    for (0..GRID_DIMENSION) |j| {
        const posy = TOP_LEFT_TILE_POSX + @as(f32, @floatFromInt(j)) * (TILE_SPACING + 2 * TILE_BORDER_WIDTH + TILE_WIDTH);
        for (0..GRID_DIMENSION) |i| {
            const posx = TOP_LEFT_TILE_POSY + @as(f32, @floatFromInt(i)) * (TILE_SPACING + 2 * TILE_BORDER_WIDTH + TILE_WIDTH);
            const tile_rect = rectangle(.{posx, posy}, TILE_WIDTH, TILE_WIDTH);
            grid_tile_rectangles[j * GRID_DIMENSION + i] = tile_rect;
        }
    }

    // Draw the grid background.
    draw_color_texture_rectangle(background_grid_rectangle, GRID_BACKGROUND, .{0, 0}, .{1, 1}, lambda);

    const TILE_BORDER_RECT_WIDTH = 2 * TILE_BORDER_WIDTH + TILE_WIDTH;

    const tile_border_width_splat : Vec2 = @splat(TILE_BORDER_WIDTH);
    const tile_width_splat        : Vec2 = @splat(TILE_WIDTH);
    const grid_width_splat        : Vec2 = @splat(GRID_WIDTH);
    
    // Draw the tiles.
    for (grid, 0..) |tile, i| {
        if (tile == 0 or tile == animating_tile) { continue; }

        const rect = grid_tile_rectangles[i];
        const tile_border_rect = rectangle(rect.center, TILE_BORDER_RECT_WIDTH, TILE_BORDER_RECT_WIDTH);

        // Calculate the texture tl of the tile (that is, the thing inside the border).
        const tilex : f32 = @floatFromInt(tile % GRID_DIMENSION);
        const tiley : f32 = @floatFromInt(tile / GRID_DIMENSION);
        
        const tl_x = (2 * tilex + 1) * TILE_BORDER_WIDTH + (tilex + 1 ) * TILE_SPACING + tilex * TILE_WIDTH;
        const tl_y = (2 * tiley + 1) * TILE_BORDER_WIDTH + (tiley + 1 ) * TILE_SPACING + tiley * TILE_WIDTH;

        const tl_inner = Vec2{tl_x, tl_y};
        const tl_outer = tl_inner - tile_border_width_splat;
        const br_inner = tl_inner + tile_width_splat;
        const br_outer = br_inner + tile_border_width_splat;

        const tl_inner_st = tl_inner / grid_width_splat;
        const tl_outer_st = tl_outer / grid_width_splat;
        const br_inner_st = br_inner / grid_width_splat;
        const br_outer_st = br_outer / grid_width_splat;
        
        draw_color_texture_rectangle(tile_border_rect, TILE_BORDER, tl_outer_st, br_outer_st, lambda);
        draw_color_texture_rectangle(rect,             DEBUG_COLOR, tl_inner_st, br_inner_st, 1);
    }

    // Draw the animating tile (if non-zero).
    if (animating_tile != 0) {
        
        const animating_tile_index_tilde = find_tile_index(animating_tile);
        const animating_tile_index : u8 = @intCast(animating_tile_index_tilde.?);

        const final_tile_rect = grid_tile_rectangles[animating_tile_index];
        const final_tile_pos = final_tile_rect.center;

        const ANIMATION_DISTANCE = TILE_WIDTH + 2 * TILE_BORDER_WIDTH + TILE_SPACING;
        const AD = ANIMATION_DISTANCE;
        
        const animation_splat : Vec2 = @splat(1 - animation_tile_fraction
                                              );
        const animation_offset_vec : Vec2 = switch(animation_direction) {
            .NONE => unreachable,
            .UP   => .{0, AD},
            .LEFT => .{AD, 0},
            .DOWN => .{0, -AD},
            .RIGHT => .{-AD, 0},
        };
        const animating_tile_pos = final_tile_pos + animation_splat * animation_offset_vec;

        const animating_tile_rect        = rectangle(animating_tile_pos, final_tile_rect.width, final_tile_rect.height);
        const animating_tile_border_rect = rectangle(animating_tile_pos, TILE_BORDER_RECT_WIDTH, TILE_BORDER_RECT_WIDTH);

        // Calculate the texture tl of the tile.
        // A partial copy from above.
        const tilex : f32 = @floatFromInt(animating_tile % GRID_DIMENSION);
        const tiley : f32 = @floatFromInt(animating_tile / GRID_DIMENSION);
        
        const tl_x = (2 * tilex + 1) * TILE_BORDER_WIDTH + (tilex + 1 ) * TILE_SPACING + tilex * TILE_WIDTH;
        const tl_y = (2 * tiley + 1) * TILE_BORDER_WIDTH + (tiley + 1 ) * TILE_SPACING + tiley * TILE_WIDTH;

        const tl_inner = Vec2{tl_x, tl_y};
        const br_inner = tl_inner + tile_width_splat;
        
        const tl_inner_st    = tl_inner / grid_width_splat;
        const br_inner_st    = br_inner / grid_width_splat;

        draw_color_texture_rectangle(animating_tile_border_rect, TILE_BORDER, .{0, 0}, .{1, 1}, lambda);
        draw_color_texture_rectangle(animating_tile_rect,        DEBUG_COLOR, tl_inner_st, br_inner_st, 1);
    }
}

// Figure out and store the GPU data that will draw a rectangle
// interpolating a single specified color and a portion of a texture.
fn draw_color_texture_rectangle( rect : Rectangle , color : Color, top_left_texture_coord : Vec2, bottom_right_texture_coord : Vec2, lambda : f32 ) void {

    const tltc = top_left_texture_coord;
    const brtc = bottom_right_texture_coord;

    // Compute the rectangle corner coordinates.
    const xleft   = rect.center[0] - 0.5 * rect.width;
    const xright  = rect.center[0] + 0.5 * rect.width;
    const ytop    = rect.center[1] - 0.5 * rect.height;
    const ybottom = rect.center[1] + 0.5 * rect.height;

    const color_f32 : Vec4 = @floatFromInt(color);
    const splat255  : Vec4 = @splat(255);
    const color_norm = color_f32 / splat255;
    const r = color_norm[0];
    const g = color_norm[1];
    const b = color_norm[2];

    // Compute the coordinates of the texture.
    const sleft   = tltc[0];
    const sright  = brtc[0];
    const ttop    = tltc[1];
    const tbottom = brtc[1];
    
    // Compute nodes we will push to the GPU.
    const v0 = colorTextureVertex(xleft,  ytop,    r, g, b, sleft,  ttop,    lambda);
    const v1 = colorTextureVertex(xright, ytop,    r, g, b, sright, ttop,    lambda);
    const v2 = colorTextureVertex(xleft,  ybottom, r, g, b, sleft,  tbottom, lambda);
    const v3 = v1;
    const v4 = v2;
    const v5 = colorTextureVertex(xright, ybottom, r, g, b, sright, tbottom, lambda);

    // Set the vertex buffer with the data.
    const buffer = &vertex_buffer;
    const i      = vertex_buffer_index;

    buffer[i + 0] = v0;
    buffer[i + 1] = v1;
    buffer[i + 2] = v2;
    buffer[i + 3] = v3;
    buffer[i + 4] = v4;
    buffer[i + 5] = v5;
    
    vertex_buffer_index += 6;
}


fn init_clock() void {
    const timeline = zjb.global("document").get("timeline", zjb.Handle);
    defer timeline.release();
    
    initial_seconds = timeline.get("currentTime", f64);
}

fn decompress_images() void {
    logStr("DEBUG: Attempting decompression...");

    var blue_marble_pixels : [blue_marble_width * blue_marble_height] Color = undefined;
    var quote_pixels : [quote_width * quote_height] Color = undefined;
    
    qoi.qoi_to_pixels(blue_marble_qoi, blue_marble_width * blue_marble_height, &blue_marble_pixels);
    qoi.qoi_to_pixels(quote_qoi, quote_width * quote_height, &quote_pixels);
    
    for (blue_marble_pixels, 0..) |pixel, i| {
        blue_marble_pixel_bytes[4 * i + 0] = pixel[0];
        blue_marble_pixel_bytes[4 * i + 1] = pixel[1];
        blue_marble_pixel_bytes[4 * i + 2] = pixel[2];
        blue_marble_pixel_bytes[4 * i + 3] = pixel[3];
    }

    for (quote_pixels, 0..) |pixel, i| {
        quote_pixel_bytes[4 * i + 0] = pixel[0];
        quote_pixel_bytes[4 * i + 1] = pixel[1];
        quote_pixel_bytes[4 * i + 2] = pixel[2];
        quote_pixel_bytes[4 * i + 3] = pixel[3];
    }

    logStr("DEBUG: Decompressed!");
}


fn init_webgl_context() void {
    const canvas = zjb.global("document").call("getElementById", .{zjb.constString("canvas")}, zjb.Handle);
    defer canvas.release();

    canvas.set("width",  CANVAS_DIMS[0]);
    canvas.set("height", CANVAS_DIMS[1]);

    // Deal with the super offensive keyboard event API. Thank you Web API committes.
    zjb.global("document").call("addEventListener", .{ zjb.constString("keydown"), zjb.fnHandle("keydownCallback", keydownCallback) }, void);
    
    glcontext = canvas.call("getContext", .{zjb.constString("webgl")}, zjb.Handle);

    // Create a WebGLBuffer.
    // Since there is not VAO in WebGL, there is (seeming?) no way to save attribute
    // state... everything seems to be global so just make one VBO to get reused everywhere.
    global_vbo = glcontext.call("createBuffer", .{}, zjb.Handle);
    glcontext.call("bindBuffer", .{gl_ARRAY_BUFFER, global_vbo}, void);
}

var keyPressEvent : KeyState = undefined;

fn keydownCallback(event: zjb.Handle) callconv(.C) void {
    defer event.release();

    // Note: the .keyCode property is depreciated, but is
    // also not a bloody string.
    // Clearly, creating a i32 enum that represented keyboard
    // keys being pressed was too difficult for the WebAPI committees
    // who designed fthis. (Maybe none of them had even used an
    // enum when programming!)
    // We refuse to do a string comparison to figure out what
    // keys have been pressed, so will use depreciated way of
    // doing this, which just passes an integer.
    
    const keyCode : i32 = event.get("keyCode", i32);

    switch (keyCode) {
        87 => { keyPressEvent.w = true; },
        65 => { keyPressEvent.a = true; },
        83 => { keyPressEvent.s = true; },
        68 => { keyPressEvent.d = true; },
        38 => { keyPressEvent.up_arrow = true; },
        37 => { keyPressEvent.left_arrow = true; },
        40 => { keyPressEvent.down_arrow = true; },
        39 => { keyPressEvent.right_arrow = true; },
        else => {},
    }
}

fn compile_shaders() void {
    const background_shader_attributes    : [1] [:0] const u8 = .{"aPos"};
    const color_texture_shader_attributes : [4] [:0] const u8 = .{"aPos", "aColor", "aTexCoord", "aLambda"};
    background_shader_program = compile_shader(vertex_background_source,
                                               fragment_background_source,
                                               background_shader_attributes[0..]);

    color_texture_shader_program = compile_shader( vertex_color_texture_source,
                                                  fragment_color_texture_source,
                                                  color_texture_shader_attributes[0..]);
}

fn compile_shader( comptime vertex_shader_source : [:0] const u8, comptime fragment_shader_source : [:0] const u8, attribute_list : [] const [:0] const u8) zjb.Handle {
        // Try compiling the vertex and fragment shaders.
    const vertex_shader_source_handle   = zjb.constString(vertex_shader_source);
    const fragment_shader_source_handle = zjb.constString(fragment_shader_source);

    const vertex_shader   = glcontext.call("createShader", .{gl_VERTEX_SHADER},   zjb.Handle);
    const fragment_shader = glcontext.call("createShader", .{gl_FRAGMENT_SHADER}, zjb.Handle);

    glcontext.call("shaderSource", .{vertex_shader, vertex_shader_source_handle}, void);
    glcontext.call("shaderSource", .{fragment_shader, fragment_shader_source_handle}, void);
    
    glcontext.call("compileShader", .{vertex_shader},   void);
    glcontext.call("compileShader", .{fragment_shader}, void);

    // Check to see that the vertex and fragment shaders compiled.
    const vs_comp_ok = glcontext.call("getShaderParameter", .{vertex_shader,   gl_COMPILE_STATUS}, bool);
    const fs_comp_ok = glcontext.call("getShaderParameter", .{fragment_shader, gl_COMPILE_STATUS}, bool);

    if (! vs_comp_ok) {
        logStr("ERROR: vertex shader failed to compile!");
        const info_log : zjb.Handle = glcontext.call("getShaderInfoLog", .{vertex_shader}, zjb.Handle);
        log(info_log);
    } else {
        logStr("DEBUG: vertex shader compiled!");
    }
    
    if (! fs_comp_ok) {
        const info_log : zjb.Handle = glcontext.call("getShaderInfoLog", .{fragment_shader}, zjb.Handle);
        log(info_log);
        logStr("ERROR: fragment shader failed to compile!");
    } else {
        logStr("DEBUG: fragment shader compiled!");
    }
    
    // Try and link the vertex and fragment shaders.
    const shader_program = glcontext.call("createProgram", .{}, zjb.Handle);
    glcontext.call("attachShader", .{shader_program, vertex_shader},   void);
    glcontext.call("attachShader", .{shader_program, fragment_shader}, void);

    // NOTE: Before we link the program, we need to manually choose the locations
    // for the vertex attributes, otherwise the linker chooses for us. See, e.g:
    // https://webglfundamentals.org/webgl/lessons/webgl-attributes.html
    for (attribute_list, 0..) |attrib, i| {
        glcontext.call("bindAttribLocation", .{shader_program, @as(i32, @intCast(i)), zjb.string(attrib)}, void);
    }

    glcontext.call("linkProgram",  .{shader_program}, void);

    // Check that the shaders linked.
    const shader_linked_ok = glcontext.call("getProgramParameter", .{shader_program, gl_LINK_STATUS}, bool);

    if (shader_linked_ok) {
        logStr("Debug: Shader linked successfully!");
    } else {
        logStr("ERROR: Shader failed to link!");
    }
    return shader_program;
}

fn create_bind_textures() void {
    // Setup blue marble texture.
    blue_marble_texture = glcontext.call("createTexture", .{}, zjb.Handle);
    glcontext.call("bindTexture", .{gl_TEXTURE_2D, blue_marble_texture}, void);

    // NOTE: The WebGL specification does NOT define CLAMP_TO_BORDER... weird.
    glcontext.call("texParameteri", .{gl_TEXTURE_2D, gl_TEXTURE_WRAP_S, gl_CLAMP_TO_EDGE}, void);
    glcontext.call("texParameteri", .{gl_TEXTURE_2D, gl_TEXTURE_WRAP_T, gl_CLAMP_TO_EDGE}, void);
    glcontext.call("texParameteri", .{gl_TEXTURE_2D, gl_TEXTURE_MIN_FILTER, gl_NEAREST}, void);
    glcontext.call("texParameteri", .{gl_TEXTURE_2D, gl_TEXTURE_MAG_FILTER, gl_NEAREST}, void);
        
    // Note: The width and height have type "GLsizei"... i.e. a i32.
    const bm_width  : i32 = @intCast(blue_marble_width);
    const bm_height : i32 = @intCast(blue_marble_height);

    // !!! VERY IMPORTANT !!!
    // gl.texImage2D accepts a pixel source ONLY with type "Uint8Array". As such,
    // applying a zjb.dataView() to the pixels will result in NO texture being drawn.
    // Instead, use zjb.u8ArrayView().
    //
    // We spent something like 2 hours debugging this. Worst debugging experience of 2025 so far.
    
    const bm_pixel_data_obj = zjb.u8ArrayView(&blue_marble_pixel_bytes);
    
    glcontext.call("texImage2D", .{gl_TEXTURE_2D, 0, gl_RGBA, bm_width, bm_height, 0, gl_RGBA, gl_UNSIGNED_BYTE, bm_pixel_data_obj}, void);

    // Setup quote texture.
    quote_texture = glcontext.call("createTexture", .{}, zjb.Handle);
    glcontext.call("bindTexture", .{gl_TEXTURE_2D, quote_texture}, void);

    // NOTE: The WebGL specification does NOT define CLAMP_TO_BORDER... weird.
    glcontext.call("texParameteri", .{gl_TEXTURE_2D, gl_TEXTURE_WRAP_S, gl_CLAMP_TO_EDGE}, void);
    glcontext.call("texParameteri", .{gl_TEXTURE_2D, gl_TEXTURE_WRAP_T, gl_CLAMP_TO_EDGE}, void);
    glcontext.call("texParameteri", .{gl_TEXTURE_2D, gl_TEXTURE_MIN_FILTER, gl_NEAREST}, void);
    glcontext.call("texParameteri", .{gl_TEXTURE_2D, gl_TEXTURE_MAG_FILTER, gl_NEAREST}, void);
        
    // Note: The width and height have type "GLsizei"... i.e. a i32.
    const q_width  : i32 = @intCast(quote_width);
    const q_height : i32 = @intCast(quote_height);
    const q_pixel_data_obj = zjb.u8ArrayView(&quote_pixel_bytes);
    
    glcontext.call("texImage2D", .{gl_TEXTURE_2D, 0, gl_RGBA, q_width, q_height, 0, gl_RGBA, gl_UNSIGNED_BYTE, q_pixel_data_obj}, void);

    glcontext.call("activeTexture", .{gl_TEXTURE0}, void);
}

fn setup_background_VBO() void {
    // Define an rectangle to draw the fractal shader on.
    const background_triangle_gpu_data : [6 * 2] f32 = .{
        // xpos, ypos
         1,  1,  // RT
        -1,  1,  // LT
         1, -1,  // RB
        -1,  1,  // LT
         1, -1,  // RB
        -1, -1,  // LB
    };

    const gpu_data_obj = zjb.dataView(&background_triangle_gpu_data);
    glcontext.call("bufferData", .{gl_ARRAY_BUFFER, gpu_data_obj, gl_STATIC_DRAW}, void); //, 0, @sizeOf(@TypeOf(background_triangle_gpu_data))}, void);

    // Set the VBO attributes.
    // NOTE: The index (locations) were specified just before linking the vertex and fragment shaders. 
    glcontext.call("enableVertexAttribArray", .{0}, void);
    glcontext.call("vertexAttribPointer", .{
        0,                // index
        2,                // number of components
        gl_FLOAT,         // type
        false,            // normalize
        2 * @sizeOf(f32), // stride
        0 * @sizeOf(f32), // offset
        }, void);
}

fn setup_color_vertex_VBO() void {
    glcontext.call("bufferData", .{gl_ARRAY_BUFFER, 4000 * @sizeOf(f32), gl_DYNAMIC_DRAW}, void);

    // Set the VBO attributes.
    // NOTE: The index (locations) were specified just before linking the vertex and fragment shaders.
    glcontext.call("enableVertexAttribArray", .{0}, void);
    glcontext.call("enableVertexAttribArray", .{1}, void);
    glcontext.call("enableVertexAttribArray", .{2}, void);
    glcontext.call("enableVertexAttribArray", .{3}, void);

    glcontext.call("vertexAttribPointer", .{0, 2, gl_FLOAT, false, 8 * @sizeOf(f32), 0 * @sizeOf(f32)}, void);
    glcontext.call("vertexAttribPointer", .{1, 3, gl_FLOAT, false, 8 * @sizeOf(f32), 2 * @sizeOf(f32)}, void);
    glcontext.call("vertexAttribPointer", .{2, 2, gl_FLOAT, false, 8 * @sizeOf(f32), 5 * @sizeOf(f32)}, void);
    glcontext.call("vertexAttribPointer", .{3, 1, gl_FLOAT, false, 8 * @sizeOf(f32), 7 * @sizeOf(f32)}, void);
}

fn process_input() void {

    keyDownLastFrame = keyDown;
    
    // Check our (basically another thread) keyPressEvent to see if
    // buttons have been mashed!
    // If not, continue.
    // If so, save the updates, and then clear.
    if (@as(u8, @bitCast(keyPressEvent)) != 0) {
        keyDown = keyPressEvent;
        keyPressEvent = @bitCast(@as(u8, 0));
    } else {
        keyDown = @bitCast(@as(u8, 0));
    }

    keyPress = @bitCast(@as(u8, @bitCast(keyDown)) & ~ @as(u8, @bitCast(keyDownLastFrame)));
}

fn update_state() void {

    // Reset tile movement.
    current_tile_movement_direction = .NONE;
    
    // Determine if a tile movement attempt has been made. 
    if (keyPress.w or keyPress.up_arrow)    { current_tile_movement_direction = .UP; }
    if (keyPress.a or keyPress.left_arrow)  { current_tile_movement_direction = .LEFT; }
    if (keyPress.s or keyPress.down_arrow)  { current_tile_movement_direction = .DOWN; }
    if (keyPress.d or keyPress.right_arrow) { current_tile_movement_direction = .RIGHT; }

    // Reset animation if key press.
    if (@as(u8, @bitCast(keyPress)) != 0) {
        animation_start_seconds = @floatCast(current_seconds);
    }

    // Check if animation over. Otherwise calculate animation fraction.
    const secs_since_animation_start = current_seconds - animation_start_seconds;
    if (secs_since_animation_start > ANIMATION_SLIDING_TILE_TIME) {
        animation_direction = .NONE;
        animating_tile = 0;
        animation_tile_fraction = 0;
    } else {
        animation_tile_fraction = @floatCast(secs_since_animation_start / ANIMATION_SLIDING_TILE_TIME);
    }
    
    // Try a move!
    try_grid_update(current_tile_movement_direction);

    // Check if the puzzle is solved (if not already won).
    if (! is_won ) {
        is_won = @reduce(.And, grid == std.simd.iota(u8, TILE_NUMBER));
        if (is_won) {
            won_start_seconds = @floatCast(current_seconds);
        }
    }

    // Calculate the animation_won_fraction.
    if (is_won) {
        const secs_since_won : f32 = @floatCast(current_seconds - won_start_seconds);
        animation_won_fraction   = std.math.clamp(secs_since_won, 0, ANIMATION_WON_TIME) / ANIMATION_WON_TIME;
        animation_quote_fraction = std.math.clamp(secs_since_won - ANIMATION_WON_TIME + 1, 0, ANIMATION_QUOTE_TIME) / ANIMATION_QUOTE_TIME;
    }
}
// Try and move and calculate the new grid configuration (if it changes).
fn try_grid_update(tile_movement_direction : GridMovementDirection) void {
    // E.g.
    //
    // 0 1  -- LEFT -->  1 0
    // 2 3               2 3

    // 1 2               1 0
    // 3 0  -- DOWN -->  3 2
    
    // Find empty tile.
    const empty_tile_index_tilde = find_tile_index(0);
    const empty_tile_index : u8 = @intCast(empty_tile_index_tilde.?);

    const empty_tile_posx = empty_tile_index % GRID_DIMENSION;
    const empty_tile_posy = empty_tile_index / GRID_DIMENSION;

    // Determine if the grid needs to be updated.
    const no_grid_update : bool = switch(tile_movement_direction) {
        .NONE  => true,
        .UP    => empty_tile_posy == GRID_DIMENSION - 1,
        .LEFT  => empty_tile_posx == GRID_DIMENSION - 1,
        .DOWN  => empty_tile_posy == 0,
        .RIGHT => empty_tile_posx == 0,
    };

    // Cancel any existing animation if a movement key was pressed
    // but the grid cannot be updated.
    if (no_grid_update and tile_movement_direction != .NONE) {
        animating_tile = 0;
    }

    // Update the grid.
    if (! no_grid_update and ! is_won) {
        const swap_tile_index : usize = switch(tile_movement_direction) {
            .NONE  => unreachable,
            .UP    => empty_tile_index + GRID_DIMENSION,
            .LEFT  => empty_tile_index + 1,
            .DOWN  => empty_tile_index - GRID_DIMENSION,
            .RIGHT => empty_tile_index - 1,
        };

        grid[empty_tile_index] = grid[swap_tile_index];
        grid[swap_tile_index] = 0;
        animating_tile = grid[empty_tile_index];
        animation_direction = tile_movement_direction;
    }
}

fn render() void {
    // Render the background color.
    glcontext.call("clearColor", .{0.2, 0.2, 0.2, 1}, void);
    glcontext.call("clear",      .{gl_COLOR_BUFFER_BIT}, void);

    // Render the background pattern.
    setup_background_VBO();
    glcontext.call("useProgram", .{background_shader_program}, void);

    // Calculate background_shader uniforms.
    const program_secs : f32 = @floatCast(current_seconds);    
    const lp_value = 1.5 + 0.5 * @cos(PI * program_secs / BACKGROUND_SHADER_SHAPE_CHANGE_TIME);
    
    const radius_value : f32 = 0.018571486 * switch(is_won) {
        false => 1,
        true  => 1 - animation_won_fraction,
    };

    const lp_uniform_location = glcontext.call("getUniformLocation", .{background_shader_program, zjb.constString("lp")}, zjb.Handle);
    const radius_uniform_location = glcontext.call("getUniformLocation", .{background_shader_program, zjb.constString("radius")}, zjb.Handle);
    
    glcontext.call("uniform1f", .{lp_uniform_location, lp_value}, void);
    glcontext.call("uniform1f", .{radius_uniform_location, radius_value}, void);
    
    glcontext.call("drawArrays", .{gl_TRIANGLES, 0, 6}, void);

    // Render the tiles.
    setup_color_vertex_VBO();
    glcontext.call("useProgram", .{color_texture_shader_program}, void);
    glcontext.call("bindTexture", .{gl_TEXTURE_2D, blue_marble_texture}, void);    

    // Convert the bufferdata into a [] f32
    var vertex_buffer_f32 : [8 * 4000] f32 = undefined;

    for (0..vertex_buffer_index) |i| {
        vertex_buffer_f32[8 * i + 0] = vertex_buffer[i].x;
        vertex_buffer_f32[8 * i + 1] = vertex_buffer[i].y;
        vertex_buffer_f32[8 * i + 2] = vertex_buffer[i].r;
        vertex_buffer_f32[8 * i + 3] = vertex_buffer[i].g;
        vertex_buffer_f32[8 * i + 4] = vertex_buffer[i].b;
        vertex_buffer_f32[8 * i + 5] = vertex_buffer[i].tx;
        vertex_buffer_f32[8 * i + 6] = vertex_buffer[i].ty;
        vertex_buffer_f32[8 * i + 7] = vertex_buffer[i].l;
    }

    const tile_gpu_data = vertex_buffer_f32[0..8 * vertex_buffer_index];
    
    const tile_gpu_data_obj = zjb.dataView(tile_gpu_data);

    glcontext.call("bufferSubData", .{gl_ARRAY_BUFFER, 0, tile_gpu_data_obj}, void);
    glcontext.call("drawArrays", .{gl_TRIANGLES, 0, @as(i32, @intCast(vertex_buffer_index))}, void);
    
    // Reset the vertex_buffer.
    vertex_buffer_index = 0;

    // Draw the quote.
    glcontext.call("bindTexture", .{gl_TEXTURE_2D, quote_texture}, void);

    const quote_width_f32  : f32 = @floatFromInt(quote_width);
    const quote_height_f32 : f32 = @floatFromInt(quote_height);
    const quote_pos_relative : Vec2 = .{1.12, 1.65};
    const quote_pos : Vec2 = quote_pos_relative * CENTER;
    const quote_rectangle = rectangle(quote_pos, quote_width_f32, quote_height_f32);

    draw_color_texture_rectangle(quote_rectangle, SPACE_BLACK, .{0,0}, .{1, 1}, animation_quote_fraction);

    for (0..vertex_buffer_index) |i| {
        vertex_buffer_f32[8 * i + 0] = vertex_buffer[i].x;
        vertex_buffer_f32[8 * i + 1] = vertex_buffer[i].y;
        vertex_buffer_f32[8 * i + 2] = vertex_buffer[i].r;
        vertex_buffer_f32[8 * i + 3] = vertex_buffer[i].g;
        vertex_buffer_f32[8 * i + 4] = vertex_buffer[i].b;
        vertex_buffer_f32[8 * i + 5] = vertex_buffer[i].tx;
        vertex_buffer_f32[8 * i + 6] = vertex_buffer[i].ty;
        vertex_buffer_f32[8 * i + 7] = vertex_buffer[i].l;
    }

    const quote_gpu_data = vertex_buffer_f32[0..8 * vertex_buffer_index];
    
    const quote_gpu_data_obj = zjb.dataView(quote_gpu_data);
    
    glcontext.call("bufferSubData", .{gl_ARRAY_BUFFER, 0, quote_gpu_data_obj}, void);
    glcontext.call("drawArrays", .{gl_TRIANGLES, 0, @as(i32, @intCast(vertex_buffer_index))}, void);

    vertex_buffer_index = 0;
}


fn find_tile_index( wanted_tile : u8) ?usize {
    for (grid, 0..) |tile, i| {
        if (tile == wanted_tile) { return i; }
    }
    return null;
}

fn get_randomish_byte( prng : *XorShiftPRNG) u8 {
    // Pick a byte near the 'middle'.
    const byte : u8 = @truncate(prng.state >> 32);
    prng.update_state();
    return byte;
}

// Return a random number from 0..<limit <= 255.
fn get_randomish_byte_up_to(limit : u8) u8 {
    const remainder = 255 % limit;
    const modulo_limit = (255 - remainder) - 1;
    var random_byte : u8 = 0;
    while (true) {
        random_byte = get_randomish_byte(&global_prng);
        if (random_byte <= modulo_limit) {
            break;
        }
    }
    const final_byte = random_byte % limit;
    return final_byte;
}

const XorShiftPRNG = struct {
    state : u64,

    fn update_state(self : *XorShiftPRNG) void {
        const x1 = self.state; 
        const x2 = x1 ^ (x1 << 13);
        const x3 = x2 ^ (x2 >> 7);
        const x4 = x3 ^ (x3 << 17);
        self.state = x4;
    }
};

fn initialize_xorshiftprng( seed : u64 ) XorShiftPRNG {
    var xorshiftprng = XorShiftPRNG{ .state = seed };
    for (0..10) |i| {
        _ = i;
        xorshiftprng.update_state();
    }
    return xorshiftprng;
}
