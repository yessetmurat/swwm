// swwm shadow module payload: loaded into Dock by osax/loader.
//
// Dock's WindowServer connection may change any window's tags; tag bit 3
// turns the window's shadow off. swwm sends requests over a Unix socket in
// the user's temporary directory (Dock runs as the same user):
//   int16 length of the rest (little endian), uint8 opcode 0x01,
//   uint32 window id, uint8 shadow (0 off, 1 on)
// and gets one byte back: 1 done, 0 rejected. Mirrors SwwmCore.shadowMessage.
//
// The tag call is the one yabai's payload uses for window_shadow (MIT License,
// see LICENSE.yabai).
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

typedef int (*main_connection_fn)(void);
typedef int (*tags_fn)(int cid, uint32_t wid, uint64_t *tags, int size);

static main_connection_fn main_connection;
static tags_fn set_tags, clear_tags;
static int server_fd = -1;

static void handle(int c)
{
    int on = 1;
    setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on)); // a SIGPIPE would kill Dock
    struct timeval tv = { .tv_sec = 1 };
    setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    // Frame: int16 length of the rest, then that many bytes. Read the length
    // first, then exactly the body; a fixed MSG_WAITALL size would block for
    // the whole timeout when the client sends fewer bytes.
    uint8_t buf[16];
    uint8_t ok = 0;
    int16_t length = 0;
    if (recv(c, &length, sizeof(length), MSG_WAITALL) == (ssize_t) sizeof(length) &&
        length == 6 && recv(c, buf, (size_t) length, MSG_WAITALL) == (ssize_t) length &&
        buf[0] == 0x01) {
        uint32_t wid;
        memcpy(&wid, buf + 1, sizeof(wid));
        if (wid != 0) {
            uint64_t tags = 1ull << 3;
            (buf[5] ? clear_tags : set_tags)(main_connection(), wid, &tags, 64);
            ok = 1;
        }
    }
    send(c, &ok, 1, 0);
    close(c);
}

static void *serve(void *unused)
{
    (void) unused;
    for (;;) {
        int c = accept(server_fd, NULL, NULL);
        if (c < 0) {
            if (errno != EINTR) usleep(100000);
            continue;
        }
        handle(c);
    }
    return NULL;
}

__attribute__((constructor))
static void load_payload(void)
{
    main_connection = (main_connection_fn) dlsym(RTLD_DEFAULT, "SLSMainConnectionID");
    set_tags = (tags_fn) dlsym(RTLD_DEFAULT, "SLSSetWindowTags");
    clear_tags = (tags_fn) dlsym(RTLD_DEFAULT, "SLSClearWindowTags");
    if (!main_connection || !set_tags || !clear_tags) return;

    char dir[PATH_MAX];
    if (!confstr(_CS_DARWIN_USER_TEMP_DIR, dir, sizeof(dir))) return;

    struct sockaddr_un address = { .sun_family = AF_UNIX };
    if (snprintf(address.sun_path, sizeof(address.sun_path), "%sswwm-dock.sock", dir) >= (int) sizeof(address.sun_path)) return;

    unlink(address.sun_path);
    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0 ||
        bind(server_fd, (struct sockaddr *) &address, sizeof(address)) != 0 ||
        chmod(address.sun_path, 0600) != 0 ||
        listen(server_fd, 16) != 0) {
        return;
    }

    pthread_t thread;
    if (pthread_create(&thread, NULL, serve, NULL) == 0) pthread_detach(thread);
}
