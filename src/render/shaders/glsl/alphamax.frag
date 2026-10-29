#version 100

#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
uniform sampler2D tex;
uniform vec2      halfpixel; // the size of one texel of tex: 1 / width, 1 / height

// The largest alpha in the 8x8 block of tex that this pixel stands for, for CHyprOpenGLImpl::analyzeLayerAlpha(): the
// target is an eighth of the texture's size and gl_FragCoord picks the block, so the target's rows follow the
// texture's rows whatever the projection does.
void main() {
    vec2  block = floor(gl_FragCoord.xy) * 8.0;
    float m     = 0.0;
    for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
            m = max(m, texture2D(tex, (block + vec2(float(x), float(y)) + 0.5) * halfpixel).a);
        }
    }
    gl_FragColor = vec4(m, m, m, 1.0);
}
