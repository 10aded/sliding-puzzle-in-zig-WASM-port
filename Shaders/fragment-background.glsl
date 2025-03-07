#version 100
// Version above obtained by looking at the table at:
// https://en.wikipedia.org/w/index.php?title=OpenGL_Shading_Language&oldid=1270723503

precision mediump float;

uniform float time;

const float PI = 3.1415926535897932384626433832795;

uniform float lp;
uniform float radius; // Should be around 0.08095238.

//const int reps = 10;
const int reps = 2;

const float SMOOTHSTEP_WIDTH = 0.010;
const float SHAPE_CHANGE_PERIOD = 100.0;

const vec2 CENTER1 = vec2(0.25, 0.25);
const vec2 CENTER2 = vec2(0.75, 0.75);

const vec4 SPACE_BLACK = vec4(0.012, 0.012, 0.020, 1.000); // #030305

const vec4 WHITE      = vec4(1, 1, 1, 1);
const vec4 KUSAMA_RED = vec4(0.843, 0.059, 0.102, 1);
const vec4 BLUE_BLACK = vec4(0.008, 0.02, 0.125, 1);
const vec4 URANIUM_CAT_GREEN = vec4(0.235, 1.000, 0.286, 1.000);
  
//const vec4 BACKGROUND = URANIUM_CAT_GREEN;
const vec4 BACKGROUND = SPACE_BLACK;
const vec4 DISK_COLOR = WHITE; 

void main(void)
{
    // JUST USING MAGIC (NUMBER) COORDS FOR THE MOMENT...
    vec2 normalized_coords = gl_FragCoord.xy / 1000.0;
    vec2 unit_coord = 2.0 * normalized_coords - 1.0;
    
    vec2 scaled = float(reps) * unit_coord;
    vec2 coord = fract(scaled);
    
    vec2 diff1 = abs(coord - CENTER1);
    vec2 diff2 = abs(coord - CENTER2);
    
    // Apply a Lp norm, where p varies between 1 and 2.
    float dot1_lp = pow(pow(diff1.x, lp) + pow(diff1.y, lp), 1.0 / lp);
    float dot2_lp = pow(pow(diff2.x, lp) + pow(diff2.y, lp), 1.0 / lp);
    
    float dot1 = 1.0 - smoothstep(radius, radius + SMOOTHSTEP_WIDTH, dot1_lp);
    float dot2 = 1.0 - smoothstep(radius, radius + SMOOTHSTEP_WIDTH, dot2_lp);
    
    float in_disk = dot1 + dot2;
    
    vec4 final_color = (1.0 - in_disk) * BACKGROUND + in_disk * DISK_COLOR;
    
    gl_FragColor = final_color;
}
