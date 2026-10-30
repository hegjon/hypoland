#version 100

#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
uniform sampler2D tex;
uniform vec2      halfpixel; // the size of one texel of tex: 1 / width, 1 / height

// Whether the 8x8 block of tex that this pixel stands for has any alpha, for CHyprOpenGLImpl::analyzeLayerAlpha(): the
// target is an eighth of the texture's size and gl_FragCoord picks the block, so the target's rows follow the
// texture's rows whatever the projection does. The texture is sampled with linear filtering at the points between four
// texels, so 16 taps read the block's 64 (past the edge the texture repeats its edge texel). A tap is a quarter of the
// smallest alpha among its four at least, and the result is scaled so that any alpha at all leaves a nonzero pixel.
void main() {
    vec2  block = floor(gl_FragCoord.xy) * 8.0;
    float m     = 0.0;
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            m = max(m, texture2D(tex, (block + vec2(float(x), float(y)) * 2.0 + 1.0) * halfpixel).a);
        }
    }
    gl_FragColor = vec4(min(1.0, m * 1020.0));
}
