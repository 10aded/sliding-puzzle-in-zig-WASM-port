//#version 300 es
attribute vec2 aPos;
attribute vec3 aColor;
varying   vec3 Color;

void main() {
  gl_Position = vec4(aPos, 0, 1);
  Color = aColor;
}
