const std = @import("std");
const zjb = @import("zjb");

const vertex_shader_source   = @embedFile("vertex.glsl");
const fragment_shader_source = @embedFile("fragment.glsl");

const alloc = std.heap.wasm_allocator;

pub const panic = zjb.panic;

// Constants
const PI    = std.math.pi;

// Globals
// Canvas stuff.
var glcontext      : zjb.Handle = undefined;

// Shaders
var triangle_vbo   : zjb.Handle = undefined;
var shader_program : zjb.Handle = undefined;

// GL constants... but because this is "web" programming we cannot just
// look these up at comptime but query them at runtime.
var gl_FLOAT            : i32 = undefined;
var gl_COLOR_BUFFER_BIT : i32 = undefined;
var gl_DEPTH_BUFFER_BIT : i32 = undefined;
var gl_STATIC_DRAW      : i32 = undefined;
var gl_ARRAY_BUFFER     : i32 = undefined;
var gl_DEPTH_TEST       : i32 = undefined;
var gl_LEQUAL           : i32 = undefined;
var gl_TRIANGLES        : i32 = undefined;

// Timestamp
var initial_timestamp      : f64 = undefined;
var last_timestamp_seconds : f64 = undefined;

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

    set_gl_constants();

    init_shaders();

    setup_array_buffers();
    
    logStr("Debug: Begin main loop.");
    
    animationFrame(initial_timestamp);
}

fn init_clock() void {
    const timeline = zjb.global("document").get("timeline", zjb.Handle);
    initial_timestamp = timeline.get("currentTime", f64);
}

fn init_webgl_context() void {
    const canvas = zjb.global("document").call("getElementById", .{zjb.constString("canvas")}, zjb.Handle);
    defer canvas.release();

    canvas.set("width",  500);
    canvas.set("height", 500);
    
    glcontext = canvas.call("getContext", .{zjb.constString("webgl")}, zjb.Handle);
}

fn set_gl_constants() void {
    gl_ARRAY_BUFFER     = glcontext.get("ARRAY_BUFFER",     i32);
    gl_STATIC_DRAW      = glcontext.get("STATIC_DRAW",      i32);
    gl_DEPTH_TEST       = glcontext.get("DEPTH_TEST",       i32);
    gl_LEQUAL           = glcontext.get("LEQUAL",           i32);
    gl_COLOR_BUFFER_BIT = glcontext.get("COLOR_BUFFER_BIT", i32);
    gl_DEPTH_BUFFER_BIT = glcontext.get("DEPTH_BUFFER_BIT", i32);
    gl_TRIANGLES        = glcontext.get("TRIANGLES",        i32);
    gl_FLOAT            = glcontext.get("FLOAT",            i32);
}

fn init_shaders() void {
    // Constant-function args.
    const gl_VERTEX_SHADER    = glcontext.get("VERTEX_SHADER",    i32);
    const gl_FRAGMENT_SHADER  = glcontext.get("FRAGMENT_SHADER",  i32);
    const gl_COMPILE_STATUS   = glcontext.get("COMPILE_STATUS",   i32);
    const gl_LINK_STATUS      = glcontext.get("LINK_STATUS",      i32);

    // Setup vertex shader.
    const vertex_shader_source_handle = zjb.constString(vertex_shader_source);
    const vertex_shader = glcontext.call("createShader", .{gl_VERTEX_SHADER}, zjb.Handle);
    glcontext.call("shaderSource", .{vertex_shader, vertex_shader_source_handle}, void);
    glcontext.call("compileShader", .{vertex_shader}, void);
    
    // Setup fragment Shader
    const fragment_shader_source_handle = zjb.constString(fragment_shader_source);
    const fragment_shader = glcontext.call("createShader", .{gl_FRAGMENT_SHADER}, zjb.Handle);
    glcontext.call("shaderSource", .{fragment_shader, fragment_shader_source_handle}, void);
    glcontext.call("compileShader", .{fragment_shader}, void);

    // Check to see that the vertex shader and fragment shader compiled.
    const vs_comp_ok = glcontext.call("getShaderParameter", .{vertex_shader,   gl_COMPILE_STATUS}, bool);
    const fs_comp_ok = glcontext.call("getShaderParameter", .{fragment_shader, gl_COMPILE_STATUS}, bool);

    if (! vs_comp_ok) {
        logStr("ERROR: vertex shader failed to compile!");
        const info_log : zjb.Handle = glcontext.call("getShaderInfoLog", .{vertex_shader}, zjb.Handle);
        log(info_log);
    }
    if (! fs_comp_ok) {
        const info_log : zjb.Handle = glcontext.call("getShaderInfoLog", .{fragment_shader}, zjb.Handle);
        log(info_log);
        logStr("ERROR: fragment shader failed to compile!");
    }
    
    // Link the vertex and fragment shaders.
    shader_program = glcontext.call("createProgram", .{}, zjb.Handle);
    glcontext.call("attachShader", .{shader_program, vertex_shader}, void);
    glcontext.call("attachShader", .{shader_program, fragment_shader}, void);

    // BEFORE we link the program, manually choose locations for the vertex attributes.
    // https://webglfundamentals.org/webgl/lessons/webgl-attributes.html
    glcontext.call("bindAttribLocation", .{shader_program, 0, zjb.constString("aPos")}, void);
    glcontext.call("bindAttribLocation", .{shader_program, 1, zjb.constString("aColor")}, void);

    glcontext.call("linkProgram",  .{shader_program}, void);

    // Check that the shader_program actually linked.

    const shader_linked_ok = glcontext.call("getProgramParameter", .{shader_program, gl_LINK_STATUS}, bool);

    if (shader_linked_ok) {
        logStr("Shader linked successfully!");
    } else {
        logStr("ERROR: Shader failed to link!");
    }
}

fn setup_array_buffers() void {
    // Define an equilateral RGB triangle.
    const triangle_gpu_data : [3 * 5] f32 = .{
         1,    0,                1, 0, 0,
        -0.5,  0.5 * @sqrt(3.0), 0, 1, 0,
        -0.5, -0.5 * @sqrt(3.0), 0, 0, 1,
    };

    const gpu_data_obj = zjb.dataView(&triangle_gpu_data);
    //    defer positions_obj.release();
    
    // Create (what seems to be?) the WebGL version of a VBO.
    triangle_vbo = glcontext.call("createBuffer", .{}, zjb.Handle);

    glcontext.call("bindBuffer", .{gl_ARRAY_BUFFER, triangle_vbo}, void);
    glcontext.call("bufferData", .{gl_ARRAY_BUFFER, gpu_data_obj, gl_STATIC_DRAW, 0, @sizeOf(@TypeOf(triangle_gpu_data))}, void);

    glcontext.call("enableVertexAttribArray", .{0}, void);
    glcontext.call("vertexAttribPointer", .{
        0,         // vertexAttribNumber
        2,         // number of components
        gl_FLOAT,  // type
        false,     // normalize
        5 * @sizeOf(f32), // stride
        0 * @sizeOf(f32), // offset
        }, void);

    glcontext.call("enableVertexAttribArray", .{1}, void);
    glcontext.call("vertexAttribPointer", .{1, 3, gl_FLOAT, false, 5 * @sizeOf(f32), 2 * @sizeOf(f32)}, void);
}

fn animationFrame(timestamp: f64) callconv(.C) void {

    // NOTE: The timestamp is in milliseconds.
    const time_seconds = timestamp / 1000;
    
//    const oscillating_value = 0.5 * (1 + std.math.sin(2 * PI * time_seconds));

    // Render! 
//    glcontext.call("clearColor", .{oscillating_value,0.5,1,1}, void);
    glcontext.call("clearColor", .{0.2,0.2,0.2,1}, void);
    glcontext.call("clear", .{glcontext.get("COLOR_BUFFER_BIT", i32)}, void);
    glcontext.call("clearDepth", .{1},             void);
    glcontext.call("enable",     .{gl_DEPTH_TEST}, void);
    glcontext.call("depthFunc",  .{gl_LEQUAL},     void);

    glcontext.call("clear", .{gl_COLOR_BUFFER_BIT | gl_DEPTH_BUFFER_BIT}, void);

    // Set the time uniform in fragment.glsl
    const time_uniform_location = glcontext.call("getUniformLocation", .{shader_program, zjb.constString("time")}, zjb.Handle);

    const time_seconds_f32 : f32 = @floatCast(time_seconds);
    glcontext.call("uniform1f", .{time_uniform_location, time_seconds_f32}, void);
    
    glcontext.call("useProgram", .{shader_program}, void);
    
    const offset = 0;
    const vertexCount = 3;

    // The Actual Drawing command!
    glcontext.call("drawArrays", .{gl_TRIANGLES, offset, vertexCount}, void);

    zjb.ConstHandle.global.call("requestAnimationFrame", .{zjb.fnHandle("animationFrame", animationFrame)}, void);
}
