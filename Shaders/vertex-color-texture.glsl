#version 100
// Version above obtained by looking at the table at:
// https://en.wikipedia.org/w/index.php?title=OpenGL_Shading_Language&oldid=1270723503#version 330 core

attribute vec2 aPos;
attribute vec3 aColor;
attribute vec2 aTexCoord;
attribute float aLambda;

varying vec3  Color;
varying vec2  TexCoord;
varying float Lambda;

void main() {
  // Note: CANVAS_WIDTH defined to be 800;
  vec2 unit_square_pos = aPos / 800.0;
  vec2 normalized = 2.0 * unit_square_pos - 1.0;
  vec2 inverted   = vec2(normalized.x, -normalized.y);
  gl_Position     = vec4(inverted, 0, 1);

  Color    = aColor;
  TexCoord = aTexCoord;
  Lambda   = aLambda;
}
