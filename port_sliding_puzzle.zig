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

const vertex_background_source   = @embedFile("./Shaders/vertex-background.glsl");
const fragment_background_source = @embedFile("./Shaders/fragment-background.glsl");

const CANVAS_WIDTH  : i32 = 500;
const CANVAS_HEIGHT : i32 = 500;

// Constants
const PI : f32 = std.math.pi;
const BACKGROUND_SHADER_SHAPE_CHANGE_TIME = 200;

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

// Globals
// Game logic.
var is_won = false;

// WebGL
var glcontext      : zjb.Handle = undefined;
var triangle_vbo   : zjb.Handle = undefined;
var background_shader_program : zjb.Handle = undefined;

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

export fn main() void {
    init_clock();

    init_webgl_context();

    //compile_background_shader();
    //setup_background_array_buffer();

    // TODO... Pluto example
    
    logStr("Debug: Begin main loop.");
    
    animationFrame(initial_timestamp);
}

fn init_clock() void {
    const timeline = zjb.global("document").get("timeline", zjb.Handle);
    defer timeline.release();
    
    initial_timestamp = timeline.get("currentTime", f64);
}

fn init_webgl_context() void {
    const canvas = zjb.global("document").call("getElementById", .{zjb.constString("canvas")}, zjb.Handle);
    defer canvas.release();

    canvas.set("width",  CANVAS_WIDTH);
    canvas.set("height", CANVAS_HEIGHT);
    
    glcontext = canvas.call("getContext", .{zjb.constString("webgl")}, zjb.Handle);
}

fn compile_background_shader() void {
    // Try compiling the vertex and fragment shaders.
    const vertex_background_source_handle   = zjb.constString(vertex_background_source);
    const fragment_background_source_handle = zjb.constString(fragment_background_source);

    const vertex_background   = glcontext.call("createShader", .{gl_VERTEX_SHADER},   zjb.Handle);
    const fragment_background = glcontext.call("createShader", .{gl_FRAGMENT_SHADER}, zjb.Handle);

    glcontext.call("shaderSource", .{vertex_background, vertex_background_source_handle}, void);
    glcontext.call("shaderSource", .{fragment_background, fragment_background_source_handle}, void);
    
    glcontext.call("compileShader", .{vertex_background},   void);
    glcontext.call("compileShader", .{fragment_background}, void);

    // Check to see that the vertex and fragment shaders compiled.
    const vs_comp_ok = glcontext.call("getShaderParameter", .{vertex_background,   gl_COMPILE_STATUS}, bool);
    const fs_comp_ok = glcontext.call("getShaderParameter", .{fragment_background, gl_COMPILE_STATUS}, bool);

    if (! vs_comp_ok) {
        logStr("ERROR: vertex shader failed to compile!");
        const info_log : zjb.Handle = glcontext.call("getShaderInfoLog", .{vertex_background}, zjb.Handle);
        log(info_log);
    }
    
    if (! fs_comp_ok) {
        const info_log : zjb.Handle = glcontext.call("getShaderInfoLog", .{fragment_background}, zjb.Handle);
        log(info_log);
        logStr("ERROR: fragment shader failed to compile!");
    }
    
    // Try and link the vertex and fragment shaders.
    background_shader_program = glcontext.call("createProgram", .{}, zjb.Handle);
    glcontext.call("attachShader", .{background_shader_program, vertex_background},   void);
    glcontext.call("attachShader", .{background_shader_program, fragment_background}, void);

    // NOTE: Before we link the program, we need to manually choose the locations
    // for the vertex attributes, otherwise the linker chooses for us. See, e.g:
    // https://webglfundamentals.org/webgl/lessons/webgl-attributes.html

    glcontext.call("bindAttribLocation", .{background_shader_program, 0, zjb.constString("aPos")}, void);

    glcontext.call("linkProgram",  .{background_shader_program}, void);

    // Check that the shaders linked.
    const shader_linked_ok = glcontext.call("getProgramParameter", .{background_shader_program, gl_LINK_STATUS}, bool);

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

fn animationFrame(timestamp: f64) callconv(.C) void {

    // NOTE: The timestamp is in milliseconds.
    const time_seconds = timestamp / 1000;
    _ = time_seconds;
    
    // Render the background color.
    glcontext.call("clearColor", .{0.2, 0.2, 0.2, 1}, void);
    glcontext.call("clear",      .{gl_COLOR_BUFFER_BIT}, void);

    // // Render the background.
    // glcontext.call("useProgram", .{background_shader_program}, void);

    // // Calculate background_shader uniforms.
    // const program_secs : f32 = @floatCast(time_seconds);    
    // const lp_value = 1.5 + 0.5 * @cos(PI * program_secs / BACKGROUND_SHADER_SHAPE_CHANGE_TIME);

    // //@port, @temp
    // animation_won_fraction = 0;
    
    // const radius_value : f32 = 0.018571486 * switch(is_won) {
    //     false => 1,
    //     true  => 1 - animation_won_fraction,
    // };

    // const lp_uniform_location = glcontext.call("getUniformLocation", .{background_shader_program, zjb.constString("lp")}, zjb.Handle);
    // const radius_uniform_location = glcontext.call("getUniformLocation", .{background_shader_program, zjb.constString("radius")}, zjb.Handle);
    
    // glcontext.call("uniform1f", .{lp_uniform_location, lp_value}, void);
    // glcontext.call("uniform1f", .{radius_uniform_location, radius_value}, void);
    
    // // The Actual Drawing command!
    // glcontext.call("drawArrays", .{gl_TRIANGLES, 0, 6}, void);

    

    zjb.ConstHandle.global.call("requestAnimationFrame", .{zjb.fnHandle("animationFrame", animationFrame)}, void);
}
