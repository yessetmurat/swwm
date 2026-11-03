// swwm Dock module loader: injects osax/payload into Dock.
//
// Based on yabai's src/osax/loader.m (MIT License, Copyright (c) 2019
// Åsmund Vikane; see LICENSE.yabai). Changes for swwm: the payload path comes
// from the command line, Dock is found by process name (this runs as a
// system LaunchDaemon, outside the GUI session), and --watch re-injects after
// every Dock restart.
#include <Cocoa/Cocoa.h>
#include <libproc.h>
#include <sys/event.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

#ifdef __arm64__
#include <ptrauth.h>
kern_return_t (*_thread_convert_thread_state)(thread_act_t thread, int direction, thread_state_flavor_t flavor, thread_state_t in_state, mach_msg_type_number_t in_stateCnt, thread_state_t out_state, mach_msg_type_number_t *out_stateCnt);
#endif

static const char *payload_path;

//
// :Attribution
//
// The arm64e injection path is based on work by Jeremy Legendre (https://github.com/jslegendre)
//

static char shell_code[] =
#ifdef __x86_64__
"\x55"                             // push       rbp
"\x48\x89\xE5"                     // mov        rbp, rsp
"\x48\x83\xEC\x10"                 // sub        rsp, 0x10
"\x48\x8D\x7D\xF8"                 // lea        rdi, qword [rbp+var_8]
"\x31\xC0"                         // xor        eax, eax
"\x89\xC1"                         // mov        ecx, eax
"\x48\x8D\x15\x1E\x00\x00\x00"     // lea        rdx, qword ptr [rip+0x1E]
"\x48\x89\xCE"                     // mov        rsi, rcx
"\x48\xB8"                         // movabs     rax, pthread_create_from_mach_thread
"\x00\x00\x00\x00\x00\x00\x00\x00" //
"\xFF\xD0"                         // call       rax
"\x48\x83\xC4\x10"                 // add        rsp, 0x10
"\x5D"                             // pop        rbp
"\x48\xC7\xC0\x65\x62\x61\x79"     // mov        rax, 0x79616265
"\xEB\xFE"                         // jmp        0x0
"\xC3"                             // ret
"\x55"                             // push       rbp
"\x48\x89\xE5"                     // mov        rbp, rsp
"\xBE\x01\x00\x00\x00"             // mov        esi, 0x1
"\x48\x8D\x3D\x16\x00\x00\x00"     // lea        rdi, qword ptr [rip+0x16]
"\x48\xB8"                         // movabs     rax, dlopen
"\x00\x00\x00\x00\x00\x00\x00\x00" //
"\xFF\xD0"                         // call       rax
"\x31\xF6"                         // xor        esi, esi
"\x89\xF7"                         // mov        edi, esi
"\x48\x89\xF8"                     // mov        rax, rdi
"\x5D"                             // pop        rbp
"\xC3"                             // ret
#elif __arm64__
"\xFF\xC3\x00\xD1"                 // sub        sp, sp, #0x30
"\xFD\x7B\x02\xA9"                 // stp        x29, x30, [sp, #0x20]
"\xFD\x83\x00\x91"                 // add        x29, sp, #0x20
"\xA0\xC3\x1F\xB8"                 // stur       w0, [x29, #-0x4]
"\xE1\x0B\x00\xF9"                 // str        x1, [sp, #0x10]
"\xE0\x23\x00\x91"                 // add        x0, sp, #0x8
"\x08\x00\x80\xD2"                 // mov        x8, #0
"\xE8\x07\x00\xF9"                 // str        x8, [sp, #0x8]
"\xE1\x03\x08\xAA"                 // mov        x1, x8
"\xE2\x01\x00\x10"                 // adr        x2, #0x3C
"\xE2\x23\xC1\xDA"                 // paciza     x2
"\xE3\x03\x08\xAA"                 // mov        x3, x8
"\x49\x01\x00\x10"                 // adr        x9, #0x28 ; pthread_create_from_mach_thread
"\x29\x01\x40\xF9"                 // ldr        x9, [x9]
"\x20\x01\x3F\xD6"                 // blr        x9
"\xA0\x4C\x8C\xD2"                 // movz       x0, #0x6265
"\x20\x2C\xAF\xF2"                 // movk       x0, #0x7961, lsl #16
"\x09\x00\x00\x10"                 // adr        x9, #0
"\x20\x01\x1F\xD6"                 // br         x9
"\xFD\x7B\x42\xA9"                 // ldp        x29, x30, [sp, #0x20]
"\xFF\xC3\x00\x91"                 // add        sp, sp, #0x30
"\xC0\x03\x5F\xD6"                 // ret
"\x00\x00\x00\x00\x00\x00\x00\x00" //
"\x7F\x23\x03\xD5"                 // pacibsp
"\xFF\xC3\x00\xD1"                 // sub        sp, sp, #0x30
"\xFD\x7B\x02\xA9"                 // stp        x29, x30, [sp, #0x20]
"\xFD\x83\x00\x91"                 // add        x29, sp, #0x20
"\xA0\xC3\x1F\xB8"                 // stur       w0, [x29, #-0x4]
"\xE1\x0B\x00\xF9"                 // str        x1, [sp, #0x10]
"\x21\x00\x80\xD2"                 // mov        x1, #1
"\x60\x01\x00\x10"                 // adr        x0, #0x2c ; payload_path
"\x09\x01\x00\x10"                 // adr        x9, #0x20 ; dlopen
"\x29\x01\x40\xF9"                 // ldr        x9, [x9]
"\x20\x01\x3F\xD6"                 // blr        x9
"\x09\x00\x80\x52"                 // mov        w9, #0
"\xE0\x03\x09\xAA"                 // mov        x0, x9
"\xFD\x7B\x42\xA9"                 // ldp        x29, x30, [sp, #0x20]
"\xFF\xC3\x00\x91"                 // add        sp, sp, #0x30
"\xFF\x0F\x5F\xD6"                 // retab
"\x00\x00\x00\x00\x00\x00\x00\x00" //
#endif
"\x00\x00\x00\x00\x00\x00\x00\x00" // empty space for payload_path
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00";

// The console user's Dock.
static pid_t get_dock_pid(void)
{
    uid_t console = 0;
    CFStringRef user = SCDynamicStoreCopyConsoleUser(NULL, &console, NULL);
    if (!user) return 0;
    CFRelease(user);

    int count = proc_listallpids(NULL, 0);
    if (count <= 0) return 0;
    pid_t *pids = calloc((size_t) count * 2, sizeof(pid_t));
    count = proc_listallpids(pids, count * 2 * (int) sizeof(pid_t));

    pid_t result = 0;
    for (int i = 0; i < count && !result; ++i) {
        char name[64] = {0};
        struct proc_bsdshortinfo info;
        if (proc_name(pids[i], name, sizeof(name)) > 0 && strcmp(name, "Dock") == 0 &&
            proc_pidinfo(pids[i], PROC_PIDT_SHORTBSDINFO, 0, &info, sizeof(info)) == sizeof(info) &&
            info.pbsi_uid == console) {
            result = pids[i];
        }
    }
    free(pids);
    return result;
}

static int inject(pid_t pid)
{
    int result = 0;
    mach_port_t task = 0;
    thread_act_t thread = 0;
    mach_vm_address_t code = 0;
    mach_vm_address_t stack = 0;
    vm_size_t stack_size = 16 * 1024;
    uint64_t stack_contents = 0x00000000CAFEBABE;
    if (task_for_pid(mach_task_self(), pid, &task) != KERN_SUCCESS) {
        fprintf(stderr, "could not retrieve task port for pid: %d\n", pid);
        return 1;
    }

    if (mach_vm_allocate(task, &stack, stack_size, VM_FLAGS_ANYWHERE) != KERN_SUCCESS) {
        fprintf(stderr, "could not allocate stack segment\n");
        return 1;
    }

    if (mach_vm_write(task, stack, (vm_address_t) &stack_contents, sizeof(uint64_t)) != KERN_SUCCESS) {
        fprintf(stderr, "could not copy dummy return address into stack segment\n");
        return 1;
    }

    if (vm_protect(task, stack, stack_size, 1, VM_PROT_READ | VM_PROT_WRITE) != KERN_SUCCESS) {
        fprintf(stderr, "could not change protection for stack segment\n");
        return 1;
    }

    if (mach_vm_allocate(task, &code, sizeof(shell_code), VM_FLAGS_ANYWHERE) != KERN_SUCCESS) {
        fprintf(stderr, "could not allocate code segment\n");
        return 1;
    }

#ifdef __x86_64__
    uint64_t pcfmt_address = (uint64_t) dlsym(RTLD_DEFAULT, "pthread_create_from_mach_thread");
    uint64_t dlopen_address = (uint64_t) dlsym(RTLD_DEFAULT, "dlopen");

    memcpy(shell_code + 28, &pcfmt_address, sizeof(uint64_t));
    memcpy(shell_code + 71, &dlopen_address, sizeof(uint64_t));
    memcpy(shell_code + 90, payload_path, strlen(payload_path));
#elif __arm64__
    uint64_t pcfmt_address = (uint64_t) ptrauth_strip(dlsym(RTLD_DEFAULT, "pthread_create_from_mach_thread"), ptrauth_key_function_pointer);
    uint64_t dlopen_address = (uint64_t) ptrauth_strip(dlsym(RTLD_DEFAULT, "dlopen"), ptrauth_key_function_pointer);

    memcpy(shell_code + 88, &pcfmt_address, sizeof(uint64_t));
    memcpy(shell_code + 160, &dlopen_address, sizeof(uint64_t));
#endif

    if (mach_vm_write(task, code, (vm_address_t) shell_code, sizeof(shell_code)) != KERN_SUCCESS) {
        fprintf(stderr, "could not copy shellcode into code segment\n");
        return 1;
    }

    if (vm_protect(task, code, sizeof(shell_code), 0, VM_PROT_EXECUTE | VM_PROT_READ) != KERN_SUCCESS) {
        fprintf(stderr, "could not change protection for code segment\n");
        return 1;
    }

#ifdef __x86_64__
    x86_thread_state64_t thread_state = {};
    thread_state_flavor_t thread_flavor = x86_THREAD_STATE64;
    mach_msg_type_number_t thread_flavor_count = x86_THREAD_STATE64_COUNT;

    thread_state.__rip = (uint64_t) code;
    thread_state.__rsp = (uint64_t) stack + (stack_size / 2);

    kern_return_t error = thread_create_running(task, thread_flavor, (thread_state_t)&thread_state, thread_flavor_count, &thread);
    if (error != KERN_SUCCESS) {
        fprintf(stderr, "could not spawn remote thread: %s\n", mach_error_string(error));
        return 1;
    }
#elif __arm64__
    void *handle = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_GLOBAL | RTLD_LAZY);
    if (handle) {
        _thread_convert_thread_state = dlsym(handle, "thread_convert_thread_state");
        dlclose(handle);
    }

    if (!_thread_convert_thread_state) {
        fprintf(stderr, "could not load symbol: thread_convert_thread_state\n");
        return 1;
    }

    arm_thread_state64_t thread_state = {}, machine_thread_state = {};
    thread_state_flavor_t thread_flavor = ARM_THREAD_STATE64;
    mach_msg_type_number_t thread_flavor_count = ARM_THREAD_STATE64_COUNT, machine_thread_flavor_count = ARM_THREAD_STATE64_COUNT;

    __darwin_arm_thread_state64_set_pc_fptr(thread_state, ptrauth_sign_unauthenticated((void *) code, ptrauth_key_asia, 0));
    __darwin_arm_thread_state64_set_sp(thread_state, stack + (stack_size / 2));

    kern_return_t error = thread_create(task, &thread);
    if (error != KERN_SUCCESS) {
        fprintf(stderr, "could not create remote thread: %s\n", mach_error_string(error));
        return 1;
    }

    error = _thread_convert_thread_state(thread, 2, thread_flavor, (thread_state_t) &thread_state, thread_flavor_count, (thread_state_t) &machine_thread_state, &machine_thread_flavor_count);
    if (error != KERN_SUCCESS) {
        fprintf(stderr, "could not convert thread state: %s\n", mach_error_string(error));
        return 1;
    }

    NSOperatingSystemVersion os_version = [[NSProcessInfo processInfo] operatingSystemVersion];
    if ((os_version.majorVersion == 14 && os_version.minorVersion >= 4) ||
        (os_version.majorVersion >= 15)) {
        thread_terminate(thread);
        error = thread_create_running(task, thread_flavor, (thread_state_t)&machine_thread_state, machine_thread_flavor_count, &thread);
        if (error != KERN_SUCCESS) {
            fprintf(stderr, "could not spawn remote thread: %s\n", mach_error_string(error));
            return 1;
        }
    } else {
        error = thread_set_state(thread, thread_flavor, (thread_state_t)&machine_thread_state, machine_thread_flavor_count);
        if (error != KERN_SUCCESS) {
            fprintf(stderr, "could not set thread state: %s\n", mach_error_string(error));
            return 1;
        }

        error = thread_resume(thread);
        if (error != KERN_SUCCESS) {
            fprintf(stderr, "could not resume remote thread: %s\n", mach_error_string(error));
            return 1;
        }
    }
#endif

    usleep(10000);

    for (int i = 0; i < 10; ++i) {
        kern_return_t error = thread_get_state(thread, thread_flavor, (thread_state_t)&thread_state, &thread_flavor_count);

        if (error != KERN_SUCCESS) {
            result = 1;
            goto terminate;
        }

#ifdef __x86_64__
        if (thread_state.__rax == 0x79616265) {
#elif __arm64__
        if (thread_state.__x[0] == 0x79616265) {
#endif
            result = 0;
            goto terminate;
        }

        usleep(20000);
    }

terminate:
    error = thread_terminate(thread);
    if (error != KERN_SUCCESS) {
        fprintf(stderr, "failed to terminate remote thread: %s\n", mach_error_string(error));
    }

    return result;
}

// Injects into every new Dock: at start, then after each Dock exit. Failures
// back off from 2 s up to 60 s.
static int watch(void)
{
    pid_t loaded = 0;
    unsigned delay = 2;

    for (;;) {
        pid_t pid = get_dock_pid();
        if (pid && pid != loaded) {
            sleep(2); // let a new Dock finish launching
            if (inject(pid) == 0) {
                fprintf(stderr, "swwm: payload loaded into Dock (pid %d)\n", pid);
                loaded = pid;
                delay = 2;
            } else {
                fprintf(stderr, "swwm: loading into Dock (pid %d) failed, retrying in %u s\n", pid, delay);
                sleep(delay);
                delay = delay * 2 > 60 ? 60 : delay * 2;
                continue;
            }
        }

        if (loaded && loaded == pid) {
            int kq = kqueue();
            struct kevent ev;
            EV_SET(&ev, loaded, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
            if (kq >= 0 && kevent(kq, &ev, 1, NULL, 0, NULL) == 0) {
                kevent(kq, NULL, 0, &ev, 1, NULL); // until this Dock exits
            }
            if (kq >= 0) close(kq);
        }
        sleep(1);
    }
}

int main(int argc, char **argv)
{
    bool watching = argc == 3 && strcmp(argv[1], "--watch") == 0;
    if (!(argc == 2 || watching)) {
        fprintf(stderr, "usage: loader [--watch] <payload path>\n");
        return 64;
    }

    payload_path = argv[argc - 1];
    if (strlen(payload_path) >= 104) {
        fprintf(stderr, "payload path too long (max 103 bytes)\n");
        return 64;
    }
    memcpy(shell_code + 168, payload_path, strlen(payload_path) + 1);

    if (watching) return watch();

    pid_t pid = get_dock_pid();
    if (!pid) {
        fprintf(stderr, "could not locate Dock pid\n");
        return 1;
    }
    return inject(pid);
}
