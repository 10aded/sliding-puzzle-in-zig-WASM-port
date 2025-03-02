//#version 330

precision mediump float;

uniform float time;

varying vec3 Color;

const float PI = 3.1415926535897932384626433832795;

void main() 
{
    gl_FragColor = vec4(Color, 1);
}
