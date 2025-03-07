#version 100
// Version above obtained by looking at the table at:
// https://en.wikipedia.org/w/index.php?title=OpenGL_Shading_Language&oldid=1270723503

precision mediump float;

varying vec3  Color;
varying vec2  TexCoord;
varying float Lambda;

uniform sampler2D pluto_texture;

void main() {
  vec4 flat_color         = vec4(Color, 1);
  vec4 texture_color      = texture2D(pluto_texture, TexCoord);
  vec4 interpolated_color = Lambda * texture_color + (1.0 - Lambda) * flat_color;
  gl_FragColor = interpolated_color;
}
