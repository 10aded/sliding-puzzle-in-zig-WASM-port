// An example of how to render a looping fractal in WebGL
// without having to write native .js code using the zjb
// library. (Using the library makes it possbile to call
// .js functions from within Zig when needed.)
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

const std = @import("std");
const zjb = @import("zjb");
const qoi = @import("./Dependencies/qoi.zig");

const vertex_background_source   = @embedFile("./Shaders/vertex-background.glsl");
const fragment_background_source = @embedFile("./Shaders/fragment-background.glsl");

const vertex_color_texture_source   = @embedFile("./Shaders/vertex-color-texture.glsl");
const fragment_color_texture_source = @embedFile("./Shaders/fragment-color-texture.glsl");

const CANVAS_WIDTH  : i32 = 500;
const CANVAS_HEIGHT : i32 = 500;

// Constants
const PI : f32 = std.math.pi;
const BACKGROUND_SHADER_SHAPE_CHANGE_TIME = 200;

// Type aliases.
const Color = @Vector(4, u8);


// WebGL constants obtained from the WebGL specification at:
// https://registry.khronos.org/webgl/specs/1.0.0/
const gl_FLOAT            : i32 = 0x1406; 
const gl_ARRAY_BUFFER     : i32 = 0x8892;
const gl_STATIC_DRAW      : i32 = 0x88E4;
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
var glcontext      : zjb.Handle = undefined;
var triangle_vbo   : zjb.Handle = undefined;
var background_shader_program : zjb.Handle = undefined;

var pluto_shader_program : zjb.Handle = undefined;

var blue_marble_texture  : zjb.Handle = undefined;
var quote_texture  : zjb.Handle = undefined;

// Animation
const ANIMATION_SLIDING_TILE_TIME : f32 = 0.15;
const ANIMATION_WON_TIME          : f32 = 3;
const ANIMATION_QUOTE_TIME        : f32 = 3;

var animating_tile : u8 = 0;
//var animation_direction : GridMovementDirection = undefined;

var animation_tile_fraction  : f32 = 0;
var animation_won_fraction   : f32 = 0;
var animation_quote_fraction : f32 = 0;

// Timestamp
var initial_timestamp      : f64 = undefined;

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

// TODO: In order to call gl.texImage2D to make a texture,
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




export fn main() void {

    logStr("DEBUG: Program start!"); //@debug
    
    init_clock();

    decompress_pluto();
    
    init_webgl_context();

    compile_shaders();
    
    //compile_background_shader();
    //setup_background_array_buffer();

    compile_pluto_shader();

    setup_pluto_array_buffer();
    
    logStr("Debug: Begin main loop.");
    
    animationFrame(initial_timestamp);
}

fn init_clock() void {
    const timeline = zjb.global("document").get("timeline", zjb.Handle);
    defer timeline.release();
    
    initial_timestamp = timeline.get("currentTime", f64);
}

fn decompress_pluto() void {
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

    canvas.set("width",  CANVAS_WIDTH);
    canvas.set("height", CANVAS_HEIGHT);
    
    glcontext = canvas.call("getContext", .{zjb.constString("webgl")}, zjb.Handle);
}

fn compile_shaders() void {
    const background_shader_attributes : [1][:0] const u8 = .{ "aPos"};
    
    background_shader_program = compile_shader(vertex_background_source,
                                               fragment_background_source,
                                               background_shader_attributes[0..]);
    
    //colo_texture_shader_program = compile_shader( ??? ); 
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
    for (attribute_list) |attrib| {
        glcontext.call("bindAttribLocation", .{shader_program, 0, zjb.string(attrib)}, void);
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

fn compile_pluto_shader() void {
    // Try compiling the vertex and fragment shaders.
    const vertex_color_texture_source_handle   = zjb.constString(vertex_color_texture_source);
    const fragment_color_texture_source_handle = zjb.constString(fragment_color_texture_source);

    const vertex_shader   = glcontext.call("createShader", .{gl_VERTEX_SHADER},   zjb.Handle);
    const fragment_shader = glcontext.call("createShader", .{gl_FRAGMENT_SHADER}, zjb.Handle);

    glcontext.call("shaderSource", .{vertex_shader, vertex_color_texture_source_handle}, void);
    glcontext.call("shaderSource", .{fragment_shader, fragment_color_texture_source_handle}, void);
    
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
        logStr("Debug: vertex shader successfully compiled!");        
    }
    
    if (! fs_comp_ok) {
        const info_log : zjb.Handle = glcontext.call("getShaderInfoLog", .{fragment_shader}, zjb.Handle);
        log(info_log);
        logStr("ERROR: fragment shader failed to compile!");
    } else {
        logStr("Debug: fragment shader successfully compiled!");        
    }
    
    // Try and link the vertex and fragment shaders.
    pluto_shader_program = glcontext.call("createProgram", .{}, zjb.Handle);
    glcontext.call("attachShader", .{pluto_shader_program, vertex_shader},   void);
    glcontext.call("attachShader", .{pluto_shader_program, fragment_shader}, void);

    // NOTE: Before we link the program, we need to manually choose the locations
    // for the vertex attributes, otherwise the linker chooses for us. See, e.g:
    // https://webglfundamentals.org/webgl/lessons/webgl-attributes.html

    glcontext.call("bindAttribLocation", .{pluto_shader_program, 0, zjb.constString("aPos")}, void);
    glcontext.call("bindAttribLocation", .{pluto_shader_program, 1, zjb.constString("aColor")}, void);
    glcontext.call("bindAttribLocation", .{pluto_shader_program, 2, zjb.constString("aTexCoord")}, void);
    glcontext.call("bindAttribLocation", .{pluto_shader_program, 3, zjb.constString("aLambda")}, void);
    
    glcontext.call("linkProgram",  .{pluto_shader_program}, void);

    // Check that the shaders linked.
    const shader_linked_ok = glcontext.call("getProgramParameter", .{pluto_shader_program, gl_LINK_STATUS}, bool);

    if (shader_linked_ok) {
        logStr("Debug: Shader linked successfully!");
    } else {
        logStr("ERROR: Shader failed to link!");
    }
}


fn setup_background_array_buffer() void {
    // Define an rectangle to draw the fractal shader on.
    const triangle_gpu_data : [6 * 2] f32 = .{
        // xpos, ypos
         1,  1,  // RT
        -1,  1,  // LT
         1, -1,  // RB
        -1,  1,  // LT
         1, -1,  // RB
        -1, -1,  // LB
    };

    const gpu_data_obj = zjb.dataView(&triangle_gpu_data);
    
    // Create a WebGLBuffer, seems similar to making a VBO via gl.genBuffers in pure OpenGL.
    triangle_vbo = glcontext.call("createBuffer", .{}, zjb.Handle);

    glcontext.call("bindBuffer", .{gl_ARRAY_BUFFER, triangle_vbo}, void);
    glcontext.call("bufferData", .{gl_ARRAY_BUFFER, gpu_data_obj, gl_STATIC_DRAW, 0, @sizeOf(@TypeOf(triangle_gpu_data))}, void);

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


fn setup_pluto_array_buffer() void {
    // Define an equilateral RGB triangle.
        const triangle_gpu_data : [6 * 8] f32 = .{
            // x, y, r, g, b, tx, ty, l,
             1,  0,  0.5, 0.5, 0.5, 1, 0, 0.5, // RT
            -1,  0,  0.5, 0.5, 0.5, 0, 0, 0.5, // LT
             1, -1,  0.5, 0.5, 0.5, 1, 1, 0.5, // RB
            -1,  0,  0.5, 0.5, 0.5, 0, 0, 0.5, // LT
             1, -1,  0.5, 0.5, 0.5, 1, 1, 0.5, // RB
            -1, -1,  0.5, 0.5, 0.5, 0, 1, 0.5, // LB
    };
    
    const gpu_data_obj = zjb.dataView(&triangle_gpu_data);
    
    // Create a WebGLBuffer, seems similar to making a VBO via gl.genBuffers in pure OpenGL.
    triangle_vbo = glcontext.call("createBuffer", .{}, zjb.Handle);

    glcontext.call("bindBuffer", .{gl_ARRAY_BUFFER, triangle_vbo}, void);
    glcontext.call("bufferData", .{gl_ARRAY_BUFFER, gpu_data_obj, gl_STATIC_DRAW, 0, @sizeOf(@TypeOf(triangle_gpu_data))}, void);

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

    // !!! VERY IMPORTANT !!!
    // gl.texImage2D accepts a pixel source ONLY with type "Uint8Array". As such,
    // applying a zjb.dataView() to the pixels will result in NO texture being drawn.
    // Instead, use zjb.u8ArrayView().
    //
    // We spent something like 2 hours debugging this. Worst debugging experience of 2025 so far.
    
    const q_pixel_data_obj = zjb.u8ArrayView(&quote_pixel_bytes);
    
    glcontext.call("texImage2D", .{gl_TEXTURE_2D, 0, gl_RGBA, q_width, q_height, 0, gl_RGBA, gl_UNSIGNED_BYTE, q_pixel_data_obj}, void);
}


fn animationFrame(timestamp: f64) callconv(.C) void {

    // NOTE: The timestamp is in milliseconds.
    const time_seconds = timestamp / 1000;
    
    // Render the background color.
    glcontext.call("clearColor", .{0.2, 0.2, 0.2, 1}, void);
    glcontext.call("clear",      .{gl_COLOR_BUFFER_BIT}, void);

    // Render the background.
    glcontext.call("useProgram", .{background_shader_program}, void);

    // Calculate background_shader uniforms.
    const program_secs : f32 = @floatCast(time_seconds);    
    const lp_value = 1.5 + 0.5 * @cos(PI * program_secs / BACKGROUND_SHADER_SHAPE_CHANGE_TIME);

    //@port, @temp
    animation_won_fraction = 0;
    
    const radius_value : f32 = 0.018571486 * switch(is_won) {
        false => 1,
        true  => 1 - animation_won_fraction,
    };

    const lp_uniform_location = glcontext.call("getUniformLocation", .{background_shader_program, zjb.constString("lp")}, zjb.Handle);
    const radius_uniform_location = glcontext.call("getUniformLocation", .{background_shader_program, zjb.constString("radius")}, zjb.Handle);
    
    glcontext.call("uniform1f", .{lp_uniform_location, lp_value}, void);
    glcontext.call("uniform1f", .{radius_uniform_location, radius_value}, void);
    
    // The Actual Drawing command!
    glcontext.call("drawArrays", .{gl_TRIANGLES, 0, 6}, void);




    // // Render the photo!
    // glcontext.call("useProgram", .{pluto_shader_program}, void);

    // // Let the lambda uniform, which adjusts how gray the image is.    
    // const time_seconds_f32 : f32 = @floatCast(time_seconds);
    // const speed = 4;
    // const osc : f32 = 0.5 * (1 + @sin(speed * time_seconds_f32));
    // const lambda = osc * osc;

    // const lambda_uniform_location = glcontext.call("getUniformLocation", .{pluto_shader_program, zjb.constString("lambda")}, zjb.Handle);

    // glcontext.call("uniform1f", .{lambda_uniform_location, lambda}, void);

    // // Make the GPU use the pluto texture.
    // glcontext.call("activeTexture", .{gl_TEXTURE0}, void);

    // const time_whole_seconds : i32 = @intFromFloat(time_seconds_f32);
    // const curr_texture = if (time_whole_seconds & 1 == 0) blue_marble_texture else quote_texture;
    
    // glcontext.call("bindTexture", .{gl_TEXTURE_2D, curr_texture}, void);

    // const pluto_texture_location = glcontext.call("getUniformLocation", .{pluto_shader_program, zjb.constString("pluto_texture")}, zjb.Handle);
    // glcontext.call("uniform1i", .{pluto_texture_location, 0}, void);
    
    // // Draw the dwarf planet!
    // glcontext.call("drawArrays", .{gl_TRIANGLES, 0, 6}, void);

    zjb.ConstHandle.global.call("requestAnimationFrame", .{zjb.fnHandle("animationFrame", animationFrame)}, void);
}
