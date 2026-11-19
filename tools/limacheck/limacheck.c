// limacheck <dir> <count>: compiles and links each NNNN.vert / NNNN.frag pair of tools/shadercheck with the
// lima (Mali-400) driver, its real shader compiler, under Mesa's drm-shim (no GPU needed: the shim answers lima's
// ioctls). A "== NNNN" line before each program, so lima's own messages (gpir:, ppir:) say which one they belong to;
// "FAIL NNNN ..." when GL itself reports a problem. Run with LIMA_DEBUG=shaderdb,precompile.
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <gbm.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char* slurp(const char* path) {
    FILE* f = fopen(path, "rb");
    if (f == NULL) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = malloc(n + 1);
    if (fread(buf, 1, n, f) != (size_t)n) n = 0;
    buf[n] = 0;
    fclose(f);
    return buf;
}

static GLuint compile(GLenum type, const char* src, int idx, int* bad) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[4096] = "";
        glGetShaderInfoLog(s, sizeof(log), NULL, log);
        printf("FAIL %04d %s compile: %s\n", idx, type == GL_VERTEX_SHADER ? "vertex" : "fragment", log);
        *bad = 1;
    }
    return s;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: limacheck <dir> <count>\n");
        return 2;
    }
    int fd = open("/dev/dri/renderD128", O_RDWR);
    if (fd < 0) {
        perror("open /dev/dri/renderD128 (is the drm-shim preloaded?)");
        return 2;
    }
    struct gbm_device* gbm = gbm_create_device(fd);
    PFNEGLGETPLATFORMDISPLAYEXTPROC getPlatformDisplay =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay dpy = getPlatformDisplay(EGL_PLATFORM_GBM_KHR, gbm, NULL);
    if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, NULL, NULL)) {
        fprintf(stderr, "no EGL display\n");
        return 2;
    }
    eglBindAPI(EGL_OPENGL_ES_API);
    EGLint cfgAttr[] = { EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE };
    EGLConfig cfg = NULL;
    EGLint n = 0;
    eglChooseConfig(dpy, cfgAttr, &cfg, 1, &n);
    EGLint ctxAttr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext ctx = eglCreateContext(dpy, n > 0 ? cfg : NULL, EGL_NO_CONTEXT, ctxAttr);
    if (ctx == EGL_NO_CONTEXT || !eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
        fprintf(stderr, "no GLES2 context (0x%x)\n", eglGetError());
        return 2;
    }
    printf("renderer: %s, %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));
    fflush(stdout);

    GLuint fbo, color, depth;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glGenRenderbuffers(1, &color);
    glBindRenderbuffer(GL_RENDERBUFFER, color);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGB565, 64, 64);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, color);
    glGenRenderbuffers(1, &depth);
    glBindRenderbuffer(GL_RENDERBUFFER, depth);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, 64, 64);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depth);
    glViewport(0, 0, 64, 64);
    glEnable(GL_DEPTH_TEST);

    const int count = atoi(argv[2]);
    int failed = 0;
    for (int i = 0; i < count; i++) {
        char vp[512], fp[512];
        snprintf(vp, sizeof(vp), "%s/%04d.vert", argv[1], i);
        snprintf(fp, sizeof(fp), "%s/%04d.frag", argv[1], i);
        char* vs = slurp(vp);
        char* fs = slurp(fp);
        if (vs == NULL || fs == NULL) break;
        printf("== %04d\n", i);
        fflush(stdout);
        fprintf(stderr, "== %04d\n", i);
        int bad = 0;
        GLuint v = compile(GL_VERTEX_SHADER, vs, i, &bad);
        GLuint f = compile(GL_FRAGMENT_SHADER, fs, i, &bad);
        GLuint p = glCreateProgram();
        glAttachShader(p, v);
        glAttachShader(p, f);
        glLinkProgram(p);
        GLint ok = 0;
        glGetProgramiv(p, GL_LINK_STATUS, &ok);
        if (!ok) {
            char log[4096] = "";
            glGetProgramInfoLog(p, sizeof(log), NULL, log);
            printf("FAIL %04d link: %s\n", i, log);
            bad = 1;
        }
        // no draw: with LIMA_DEBUG=precompile lima compiles both shaders at link time, and a draw would wait
        // forever for a fence the noop shim never signals
        glDeleteProgram(p);
        glDeleteShader(v);
        glDeleteShader(f);
        free(vs);
        free(fs);
        failed += bad;
        fflush(stdout);
        fflush(stderr);
    }
    printf("== %d programs, %d failed in GL\n", count, failed);
    return 0;
}
