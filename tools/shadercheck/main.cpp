// shadercheck <gles2.shader.glsl> <outdir>: the GLES2 shader template rendered by prism the way libultraship's
// gfx_opengl.cpp renders it (the same context names, the same append_formula), for a few thousand random but
// consistent combiner setups plus the corner cases. Writes NNNN.vert / NNNN.frag for glslangValidator -l, which
// compiles and links each pair as GLSL ES 1.00. The game itself compiles them on the console, where a failure is
// an abort(): this finds them in CI instead.
#include <prism/processor.h>

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <random>
#include <sstream>
#include <string>

enum {
    SHADER_0,
    SHADER_INPUT_1,
    SHADER_INPUT_2,
    SHADER_INPUT_3,
    SHADER_INPUT_4,
    SHADER_INPUT_5,
    SHADER_INPUT_6,
    SHADER_INPUT_7,
    SHADER_TEXEL0,
    SHADER_TEXEL0A,
    SHADER_TEXEL1,
    SHADER_TEXEL1A,
    SHADER_1,
    SHADER_COMBINED,
    SHADER_NOISE,
    SHADER_LOD_FRAC
};
enum { FILTER_THREE_POINT, FILTER_LINEAR, FILTER_NONE };

using prism::ContextTypes;

// From libultraship's gfx_opengl.cpp (6b861a64)
#define RAND_NOISE "((random(vec3(floor(gl_FragCoord.xy * noise_scale), float(frame_count))) + 1.0) / 2.0)"

static const char* shader_item_to_str(uint32_t item, bool with_alpha, bool only_alpha, bool inputs_have_alpha,
                                      bool first_cycle, bool hint_single_element) {
    if (!only_alpha) {
        switch (item) {
            case SHADER_0:
                return with_alpha ? "vec4(0.0, 0.0, 0.0, 0.0)" : "vec3(0.0, 0.0, 0.0)";
            case SHADER_1:
                return with_alpha ? "vec4(1.0, 1.0, 1.0, 1.0)" : "vec3(1.0, 1.0, 1.0)";
            case SHADER_INPUT_1:
                return with_alpha ? "uInputs[0]" : "uInputs[0].rgb";
            case SHADER_INPUT_2:
                return with_alpha ? "uInputs[1]" : "uInputs[1].rgb";
            case SHADER_INPUT_3:
                return with_alpha ? "uInputs[2]" : "uInputs[2].rgb";
            case SHADER_INPUT_4:
                return with_alpha ? "uInputs[3]" : "uInputs[3].rgb";
            case SHADER_INPUT_5:
                return with_alpha ? "uInputs[4]" : "uInputs[4].rgb";
            case SHADER_INPUT_6:
                return with_alpha ? "uInputs[5]" : "uInputs[5].rgb";
            case SHADER_INPUT_7:
                return with_alpha || !inputs_have_alpha ? "vShade" : "vShade.rgb";
            case SHADER_TEXEL0:
                return first_cycle ? (with_alpha ? "texVal0" : "texVal0.rgb")
                                   : (with_alpha ? "texVal1" : "texVal1.rgb");
            case SHADER_TEXEL0A:
                return first_cycle
                           ? (hint_single_element ? "texVal0.a"
                                                  : (with_alpha ? "vec4(texVal0.a, texVal0.a, texVal0.a, texVal0.a)"
                                                                : "vec3(texVal0.a, texVal0.a, texVal0.a)"))
                           : (hint_single_element ? "texVal1.a"
                                                  : (with_alpha ? "vec4(texVal1.a, texVal1.a, texVal1.a, texVal1.a)"
                                                                : "vec3(texVal1.a, texVal1.a, texVal1.a)"));
            case SHADER_TEXEL1A:
                return first_cycle
                           ? (hint_single_element ? "texVal1.a"
                                                  : (with_alpha ? "vec4(texVal1.a, texVal1.a, texVal1.a, texVal1.a)"
                                                                : "vec3(texVal1.a, texVal1.a, texVal1.a)"))
                           : (hint_single_element ? "texVal0.a"
                                                  : (with_alpha ? "vec4(texVal0.a, texVal0.a, texVal0.a, texVal0.a)"
                                                                : "vec3(texVal0.a, texVal0.a, texVal0.a)"));
            case SHADER_TEXEL1:
                return first_cycle ? (with_alpha ? "texVal1" : "texVal1.rgb")
                                   : (with_alpha ? "texVal0" : "texVal0.rgb");
            case SHADER_COMBINED:
                return with_alpha ? "texel" : "texel.rgb";
            case SHADER_NOISE:
                return with_alpha ? "vec4(" RAND_NOISE ", " RAND_NOISE ", " RAND_NOISE ", " RAND_NOISE ")"
                                  : "vec3(" RAND_NOISE ", " RAND_NOISE ", " RAND_NOISE ")";
            case SHADER_LOD_FRAC:
                return hint_single_element ? "lodFrac"
                                           : (with_alpha ? "vec4(lodFrac, lodFrac, lodFrac, lodFrac)"
                                                         : "vec3(lodFrac, lodFrac, lodFrac)");
        }
    } else {
        switch (item) {
            case SHADER_0:
                return "0.0";
            case SHADER_1:
                return "1.0";
            case SHADER_INPUT_1:
                return "uInputs[0].a";
            case SHADER_INPUT_2:
                return "uInputs[1].a";
            case SHADER_INPUT_3:
                return "uInputs[2].a";
            case SHADER_INPUT_4:
                return "uInputs[3].a";
            case SHADER_INPUT_5:
                return "uInputs[4].a";
            case SHADER_INPUT_6:
                return "uInputs[5].a";
            case SHADER_INPUT_7:
                return "vShade.a";
            case SHADER_TEXEL0:
                return first_cycle ? "texVal0.a" : "texVal1.a";
            case SHADER_TEXEL0A:
                return first_cycle ? "texVal0.a" : "texVal1.a";
            case SHADER_TEXEL1:
                return first_cycle ? "texVal1.a" : "texVal0.a";
            case SHADER_TEXEL1A:
                return first_cycle ? "texVal1.a" : "texVal0.a";
            case SHADER_COMBINED:
                return "texel.a";
            case SHADER_NOISE:
                return RAND_NOISE;
            case SHADER_LOD_FRAC:
                return "lodFrac";
        }
    }
    return "";
}

static bool get_bool(ContextTypes* value) {
    if (std::holds_alternative<int>(*value)) {
        return std::get<int>(*value) == 1;
    }
    return false;
}

static ContextTypes* append_formula(ContextTypes* _, ContextTypes* a_arg, ContextTypes* a_single, ContextTypes* a_mult,
                                    ContextTypes* a_mix, ContextTypes* a_with_alpha, ContextTypes* a_only_alpha,
                                    ContextTypes* a_alpha, ContextTypes* a_first_cycle) {
    auto c = std::get<prism::MTDArray<int>>(*a_arg);
    bool do_single = get_bool(a_single);
    bool do_multiply = get_bool(a_mult);
    bool do_mix = get_bool(a_mix);
    bool with_alpha = get_bool(a_with_alpha);
    bool only_alpha = get_bool(a_only_alpha);
    bool opt_alpha = get_bool(a_alpha);
    bool first_cycle = get_bool(a_first_cycle);
    std::string out = "";
    if (do_single) {
        out += shader_item_to_str(c.at(only_alpha, 3), with_alpha, only_alpha, opt_alpha, first_cycle, false);
    } else if (do_multiply) {
        out += shader_item_to_str(c.at(only_alpha, 0), with_alpha, only_alpha, opt_alpha, first_cycle, false);
        out += " * ";
        out += shader_item_to_str(c.at(only_alpha, 2), with_alpha, only_alpha, opt_alpha, first_cycle, true);
    } else if (do_mix) {
        out += "mix(";
        out += shader_item_to_str(c.at(only_alpha, 1), with_alpha, only_alpha, opt_alpha, first_cycle, false);
        out += ", ";
        out += shader_item_to_str(c.at(only_alpha, 0), with_alpha, only_alpha, opt_alpha, first_cycle, false);
        out += ", ";
        out += shader_item_to_str(c.at(only_alpha, 2), with_alpha, only_alpha, opt_alpha, first_cycle, true);
        out += ")";
    } else {
        out += "(";
        out += shader_item_to_str(c.at(only_alpha, 0), with_alpha, only_alpha, opt_alpha, first_cycle, false);
        out += " - ";
        out += shader_item_to_str(c.at(only_alpha, 1), with_alpha, only_alpha, opt_alpha, first_cycle, false);
        out += ") * ";
        out += shader_item_to_str(c.at(only_alpha, 2), with_alpha, only_alpha, opt_alpha, first_cycle, true);
        out += " + ";
        out += shader_item_to_str(c.at(only_alpha, 3), with_alpha, only_alpha, opt_alpha, first_cycle, false);
    }
    return new ContextTypes{ out };
}

static size_t numFloats = 0;
static ContextTypes* UpdateFloats(ContextTypes* _, ContextTypes* num) {
    numFloats += std::get<int>(*num);
    return nullptr;
}

struct Features {
    int c[2][2][4];
    bool opt_alpha, opt_fog, opt_texture_edge, opt_noise, opt_2cyc, opt_alpha_threshold, opt_invisible, opt_grayscale;
    bool opt_prim_depth, opt_mip_lod, opt_tex_lod, uses_lod_frac, opt_shade, opt_lighting, opt_point_lighting;
    bool opt_texgen, opt_texgen_linear, three_point;
    bool usedTextures[2], used_palette[2], used_masks[2], used_blend[2], clamp[2][2];
    bool do_mix[2][2], do_single[2][2], do_multiply[2][2], color_alpha_same[2];
    int numInputs;
};

static std::string Render(const std::string& tpl, Features& f, bool vertex) {
    prism::Processor processor;
    prism::ContextItems ctx;
    if (vertex) {
        numFloats = 4;
        ctx = { { "BACKEND", "opengl" },
                { "BACKEND_OPENGL", true },
                { "BACKEND_VULKAN", false },
                { "BACKEND_METAL", false },
                { "BACKEND_DIRECTX", false },
                { "VERTEX_SHADER", true },
                { "o_textures", M_ARRAY(f.usedTextures, bool, 2) },
                { "o_clamp", M_ARRAY(f.clamp, bool, 2, 2) },
                { "o_fog", f.opt_fog },
                { "o_grayscale", f.opt_grayscale },
                { "o_alpha", f.opt_alpha },
                { "o_inputs", f.numInputs },
                { "o_has_inputs", f.numInputs > 0 },
                { "o_shade", f.opt_shade },
                { "o_lighting", f.opt_lighting },
                { "o_point_lighting", f.opt_point_lighting },
                { "o_texgen", f.opt_texgen },
                { "o_texgen_linear", f.opt_texgen_linear },
                { "update_floats", (InvokeFunc)UpdateFloats },
                { "gles2", true },
                { "GLSL_VERSION", "#version 100" },
                { "attr", "attribute" },
                { "out", "varying" },
                { "opengles", true } };
    } else {
        ctx = {
            { "BACKEND", "opengl" },
            { "BACKEND_OPENGL", true },
            { "BACKEND_VULKAN", false },
            { "BACKEND_METAL", false },
            { "BACKEND_DIRECTX", false },
            { "VERTEX_SHADER", false },
            { "o_c", M_ARRAY(f.c, int, 2, 2, 4) },
            { "o_alpha", f.opt_alpha },
            { "o_fog", f.opt_fog },
            { "o_texture_edge", f.opt_texture_edge },
            { "o_noise", f.opt_noise },
            { "o_2cyc", f.opt_2cyc },
            { "o_alpha_threshold", f.opt_alpha_threshold },
            { "o_invisible", f.opt_invisible },
            { "o_grayscale", f.opt_grayscale },
            { "o_prim_depth", f.opt_prim_depth },
            { "o_mip_lod", f.opt_mip_lod },
            { "o_uses_lod",
              f.opt_mip_lod || f.uses_lod_frac || (f.opt_tex_lod && f.usedTextures[0] && f.usedTextures[1]) },
            { "o_two_tile_lod", f.opt_tex_lod && !f.opt_mip_lod && f.usedTextures[0] && f.usedTextures[1] },
            { "o_shade", f.opt_shade },
            { "o_textures", M_ARRAY(f.usedTextures, bool, 2) },
            { "o_palette", M_ARRAY(f.used_palette, bool, 2) },
            { "o_masks", M_ARRAY(f.used_masks, bool, 2) },
            { "o_blend", M_ARRAY(f.used_blend, bool, 2) },
            { "o_clamp", M_ARRAY(f.clamp, bool, 2, 2) },
            { "o_inputs", f.numInputs },
            { "o_has_inputs", f.numInputs > 0 },
            { "o_do_mix", M_ARRAY(f.do_mix, bool, 2, 2) },
            { "o_do_single", M_ARRAY(f.do_single, bool, 2, 2) },
            { "o_do_multiply", M_ARRAY(f.do_multiply, bool, 2, 2) },
            { "o_color_alpha_same", M_ARRAY(f.color_alpha_same, bool, 2) },
            { "FILTER_THREE_POINT", FILTER_THREE_POINT },
            { "FILTER_LINEAR", FILTER_LINEAR },
            { "FILTER_NONE", FILTER_NONE },
            { "SHADER_0", SHADER_0 },
            { "SHADER_INPUT_1", SHADER_INPUT_1 },
            { "SHADER_INPUT_2", SHADER_INPUT_2 },
            { "SHADER_INPUT_3", SHADER_INPUT_3 },
            { "SHADER_INPUT_4", SHADER_INPUT_4 },
            { "SHADER_INPUT_5", SHADER_INPUT_5 },
            { "SHADER_INPUT_6", SHADER_INPUT_6 },
            { "SHADER_INPUT_7", SHADER_INPUT_7 },
            { "SHADER_TEXEL0", SHADER_TEXEL0 },
            { "SHADER_TEXEL0A", SHADER_TEXEL0A },
            { "SHADER_TEXEL1", SHADER_TEXEL1 },
            { "SHADER_TEXEL1A", SHADER_TEXEL1A },
            { "SHADER_1", SHADER_1 },
            { "SHADER_COMBINED", SHADER_COMBINED },
            { "SHADER_NOISE", SHADER_NOISE },
            { "o_three_point_filtering", f.three_point },
            { "append_formula", (InvokeFunc)append_formula },
            { "gles2", true },
            { "GLSL_VERSION", "#version 100\nprecision mediump float;" },
            { "attr", "varying" },
            { "opengles", true },
            { "core_opengl", false },
            { "texture", "texture2D" },
            { "vOutColor", "gl_FragColor" },
        };
    }
    processor.populate(ctx);
    processor.load(tpl);
    return processor.process();
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: shadercheck <gles2.shader.glsl> <outdir>\n");
        return 2;
    }
    std::ifstream in(argv[1]);
    std::stringstream ss;
    ss << in.rdbuf();
    const std::string tpl = ss.str();
    std::mt19937 rng(64);
    auto coin = [&](int pct) { return (int)(rng() % 100) < pct; };

    int n = 0;
    for (int iter = 0; iter < 3000; iter++) {
        Features f = {};
        f.usedTextures[0] = coin(70);
        f.usedTextures[1] = coin(35);
        f.opt_mip_lod = f.usedTextures[0] && coin(10);
        if (f.opt_mip_lod) f.usedTextures[1] = false;
        for (int i = 0; i < 2; i++) {
            f.used_palette[i] = f.usedTextures[i] && !(i == 0 && f.opt_mip_lod) && coin(25);
            f.used_masks[i] = f.usedTextures[i] && !f.used_palette[i] && coin(10);
            f.used_blend[i] = f.used_masks[i] && coin(50);
            f.clamp[i][0] = f.usedTextures[i] && coin(40);
            f.clamp[i][1] = f.usedTextures[i] && coin(40);
        }
        f.opt_alpha = coin(60);
        f.opt_fog = coin(30);
        f.opt_texture_edge = coin(15);
        f.opt_noise = coin(10);
        f.opt_2cyc = coin(40);
        f.opt_alpha_threshold = coin(15);
        f.opt_invisible = coin(5);
        f.opt_grayscale = coin(10);
        f.opt_prim_depth = coin(10);
        f.opt_tex_lod = coin(15);
        f.uses_lod_frac = coin(10);
        f.opt_shade = coin(60);
        f.opt_lighting = coin(30);
        f.opt_point_lighting = f.opt_lighting && f.opt_shade && coin(30);
        f.opt_texgen = f.opt_lighting && coin(30);
        f.opt_texgen_linear = f.opt_texgen && coin(50);
        f.three_point = coin(30);
        f.numInputs = rng() % 7;
        bool uses_lod = f.opt_mip_lod || f.uses_lod_frac || (f.opt_tex_lod && f.usedTextures[0] && f.usedTextures[1]);

        std::vector<int> items = { SHADER_0, SHADER_1, SHADER_NOISE };
        for (int i = 0; i < f.numInputs; i++) items.push_back(SHADER_INPUT_1 + i);
        if (f.opt_shade) items.push_back(SHADER_INPUT_7);
        if (f.usedTextures[0]) {
            items.push_back(SHADER_TEXEL0);
            items.push_back(SHADER_TEXEL0A);
        }
        if (f.usedTextures[1] || f.opt_mip_lod) {
            items.push_back(SHADER_TEXEL1);
            items.push_back(SHADER_TEXEL1A);
        }
        if (uses_lod) items.push_back(SHADER_LOD_FRAC);
        // the second cycle swaps TEXEL0 and TEXEL1: it needs both when either is used
        const bool both = f.usedTextures[0] == (f.usedTextures[1] || f.opt_mip_lod);
        for (int c = 0; c < 2; c++) {
            for (int a = 0; a < 2; a++) {
                for (int k = 0; k < 4; k++) {
                    int v;
                    do {
                        v = items[rng() % items.size()];
                    } while (c == 1 && !both && v >= SHADER_TEXEL0 && v <= SHADER_TEXEL1A);
                    if (c == 1 && coin(25)) v = SHADER_COMBINED;
                    f.c[c][a][k] = v;
                }
                const int kind = rng() % 4;
                f.do_single[c][a] = kind == 0;
                f.do_multiply[c][a] = kind == 1;
                f.do_mix[c][a] = kind == 2;
            }
            f.color_alpha_same[c] = coin(30);
        }

        const std::string vs = Render(tpl, f, true);
        const std::string fs = Render(tpl, f, false);
        char name[64];
        snprintf(name, sizeof(name), "%s/%04d", argv[2], n++);
        std::ofstream(std::string(name) + ".vert") << vs;
        std::ofstream(std::string(name) + ".frag") << fs;
    }
    printf("%d shader pairs in %s\n", n, argv[2]);
    return 0;
}
