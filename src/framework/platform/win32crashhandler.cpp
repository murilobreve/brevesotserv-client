/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "framework/core/application.h"
#if defined(WIN32) && defined(CRASH_HANDLER)

#include <windows.h>
#include <psapi.h>
#ifdef _MSC_VER
#pragma comment(lib, "psapi.lib")
#endif

#include <framework/core/graphicalapplication.h>
#include <framework/core/resourcemanager.h>
#include <framework/graphics/graphics.h>

#ifdef _MSC_VER
#pragma warning (push)
#pragma warning (disable:4091) // warning C4091: 'typedef ': ignored on left of '' when no variable is declared
#include <dbghelp.h>
#pragma warning (pop)
#else
#include <dbghelp.h>
#endif
#include <algorithm>
#include <atomic>
#include <csignal>
#include <filesystem>
#include <cstdlib>
#include <exception>
#include <fstream>
#include <sstream>

const char* getExceptionName(const DWORD exceptionCode)
{
    switch (exceptionCode) {
        case EXCEPTION_ACCESS_VIOLATION:         return "Access violation";
        case EXCEPTION_DATATYPE_MISALIGNMENT:    return "Datatype misalignment";
        case EXCEPTION_BREAKPOINT:               return "Breakpoint";
        case EXCEPTION_SINGLE_STEP:              return "Single step";
        case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:    return "Array bounds exceeded";
        case EXCEPTION_FLT_DENORMAL_OPERAND:     return "Float denormal operand";
        case EXCEPTION_FLT_DIVIDE_BY_ZERO:       return "Float divide by zero";
        case EXCEPTION_FLT_INEXACT_RESULT:       return "Float inexact result";
        case EXCEPTION_FLT_INVALID_OPERATION:    return "Float invalid operation";
        case EXCEPTION_FLT_OVERFLOW:             return "Float overflow";
        case EXCEPTION_FLT_STACK_CHECK:          return "Float stack check";
        case EXCEPTION_FLT_UNDERFLOW:            return "Float underflow";
        case EXCEPTION_INT_DIVIDE_BY_ZERO:       return "Integer divide by zero";
        case EXCEPTION_INT_OVERFLOW:             return "Integer overflow";
        case EXCEPTION_PRIV_INSTRUCTION:         return "Privileged instruction";
        case EXCEPTION_IN_PAGE_ERROR:            return "In page error";
        case EXCEPTION_ILLEGAL_INSTRUCTION:      return "Illegal instruction";
        case EXCEPTION_NONCONTINUABLE_EXCEPTION: return "Noncontinuable exception";
        case EXCEPTION_STACK_OVERFLOW:           return "Stack overflow";
        case EXCEPTION_INVALID_DISPOSITION:      return "Invalid disposition";
        case EXCEPTION_GUARD_PAGE:               return "Guard page";
        case EXCEPTION_INVALID_HANDLE:           return "Invalid handle";
        case 0xC0000409:                         return "Fail fast / stack buffer overrun";
        case 0xC0000374:                         return "Heap corruption";
        case 0xE0000001:                         return "abort()";
        case 0xE0000002:                         return "Uncaught C++ exception (std::terminate)";
        case 0xE0000003:                         return "Invalid parameter to a CRT function";
        case 0xE0000004:                         return "Pure virtual function call";
    }
    return "Unknown exception";
}

void Stacktrace(LPEXCEPTION_POINTERS e, std::stringstream& ss)
{
    STACKFRAME64 sf;
    ZeroMemory(&sf, sizeof(sf));
    // StackWalk64 may change the context, so walk a copy
    CONTEXT context = *e->ContextRecord;
#ifdef _WIN64
    sf.AddrPC.Offset = context.Rip;
    sf.AddrStack.Offset = context.Rsp;
    sf.AddrFrame.Offset = context.Rbp;
    const DWORD machineType = IMAGE_FILE_MACHINE_AMD64;
#else
    sf.AddrPC.Offset = context.Eip;
    sf.AddrStack.Offset = context.Esp;
    sf.AddrFrame.Offset = context.Ebp;
    const DWORD machineType = IMAGE_FILE_MACHINE_I386;
#endif
    sf.AddrPC.Mode = AddrModeFlat;
    sf.AddrStack.Mode = AddrModeFlat;
    sf.AddrFrame.Mode = AddrModeFlat;

    const HANDLE process = GetCurrentProcess();
    const HANDLE thread = GetCurrentThread();

    // the symbol buffer lives on the stack: never free it
    char symBuffer[sizeof(IMAGEHLP_SYMBOL64) + 256];
    auto* pSym = reinterpret_cast<PIMAGEHLP_SYMBOL64>(symBuffer);

    for (int count = 0; count < 64; ++count) {
        if (!StackWalk64(machineType, process, thread, &sf, &context, nullptr, SymFunctionTableAccess64, SymGetModuleBase64, nullptr))
            break;
        if (sf.AddrPC.Offset == 0)
            break;

        char modname[MAX_PATH] = "unknown";
        const DWORD64 modBase = SymGetModuleBase64(process, sf.AddrPC.Offset);
        if (modBase) {
            char path[MAX_PATH];
            if (GetModuleFileNameA(reinterpret_cast<HMODULE>(modBase), path, MAX_PATH)) {
                const char* slash = strrchr(path, '\\');
                strncpy_s(modname, slash ? slash + 1 : path, _TRUNCATE);
            }
        }

        // module+offset can be resolved later with the release's .pdb
        ss << fmt::format("    {}: {}+0x{:x}", count, modname, sf.AddrPC.Offset - modBase);
        DWORD64 disp = 0;
        pSym->SizeOfStruct = sizeof(IMAGEHLP_SYMBOL64);
        pSym->MaxNameLength = 255;
        if (SymGetSymFromAddr64(process, sf.AddrPC.Offset, &disp, pSym))
            ss << fmt::format(" {}+0x{:x}", pSym->Name, disp);
        IMAGEHLP_LINE64 line;
        ZeroMemory(&line, sizeof(line));
        line.SizeOfStruct = sizeof(line);
        DWORD lineDisp = 0;
        if (SymGetLineFromAddr64(process, sf.AddrPC.Offset, &lineDisp, &line) && line.FileName)
            ss << fmt::format(" ({}:{})", line.FileName, line.LineNumber);
        ss << "\n";
    }
}

namespace {
    // the client folder: the next start reads the report from there and sends it
    std::string crashDir()
    {
        std::string dir = g_resources.getWorkDir();
        while (!dir.empty() && (dir.back() == '/' || dir.back() == '\\'))
            dir.pop_back();
        if (!dir.empty())
            return dir;
        char cwd[MAX_PATH];
        const DWORD len = GetCurrentDirectoryA(sizeof(cwd), cwd);
        if (len == 0 || len >= sizeof(cwd))
            return ".";
        return cwd;
    }

    std::string windowsVersion()
    {
        using RtlGetVersionFn = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
        RTL_OSVERSIONINFOW info{};
        info.dwOSVersionInfoSize = sizeof(info);
        if (const HMODULE ntdll = GetModuleHandleA("ntdll.dll")) {
            if (const auto fn = reinterpret_cast<RtlGetVersionFn>(GetProcAddress(ntdll, "RtlGetVersion")); fn && fn(&info) == 0)
                return fmt::format("Windows {}.{} build {}", info.dwMajorVersion, info.dwMinorVersion, info.dwBuildNumber);
        }
        return "Windows (unknown version)";
    }

    std::string memoryInfo()
    {
        MEMORYSTATUSEX mem{};
        mem.dwLength = sizeof(mem);
        if (!GlobalMemoryStatusEx(&mem))
            return "unknown";
        PROCESS_MEMORY_COUNTERS_EX counters{};
        std::string process;
        if (GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters), sizeof(counters)))
            process = fmt::format(", game using {} MB", counters.PrivateUsage / (1024 * 1024));
        return fmt::format("{} MB total, {} MB free{}", mem.ullTotalPhys / (1024 * 1024), mem.ullAvailPhys / (1024 * 1024), process);
    }

    // the end of the log file (flushed every second), read straight from disk
    std::string logTail(const std::size_t maxBytes)
    {
        const std::string& file = g_logger.getLogFile();
        if (file.empty())
            return "(no log file)\n";
        std::ifstream in(stdext::utf8_to_latin1(file), std::ios::binary);
        if (!in.is_open())
            return "(log file not readable)\n";
        in.seekg(0, std::ios::end);
        const std::streamoff size = in.tellg();
        const std::streamoff start = size > static_cast<std::streamoff>(maxBytes) ? size - static_cast<std::streamoff>(maxBytes) : 0;
        in.seekg(start);
        std::string text(static_cast<std::size_t>(size - start), '\0');
        in.read(text.data(), static_cast<std::streamsize>(text.size()));
        if (start > 0) {
            const auto newline = text.find('\n');
            if (newline != std::string::npos)
                text.erase(0, newline + 1);
        }
        return text;
    }

    // dumps are a few MB each: keep the newest few
    void pruneDumps(const std::string& dir, const std::size_t keep)
    {
        std::error_code ec;
        std::vector<std::filesystem::path> dumps;
        for (const auto& entry : std::filesystem::directory_iterator(dir, ec)) {
            const auto name = entry.path().filename().string();
            if (name.starts_with("crash-") && entry.path().extension() == ".dmp")
                dumps.push_back(entry.path());
        }
        if (dumps.size() <= keep)
            return;
        std::ranges::sort(dumps); // crash-YYYYMMDD-HHMMSS.dmp: oldest first
        for (std::size_t i = 0; i + keep < dumps.size(); ++i)
            std::filesystem::remove(dumps[i], ec);
    }

    void writeMiniDump(const LPEXCEPTION_POINTERS e, const std::string& fileName)
    {
        const HANDLE file = CreateFileA(fileName.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE)
            return;
        MINIDUMP_EXCEPTION_INFORMATION info;
        info.ThreadId = GetCurrentThreadId();
        info.ExceptionPointers = e;
        info.ClientPointers = FALSE;
        const auto type = static_cast<MINIDUMP_TYPE>(MiniDumpWithIndirectlyReferencedMemory | MiniDumpWithThreadInfo | MiniDumpWithUnloadedModules);
        MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), file, type, &info, nullptr, nullptr);
        CloseHandle(file);
    }

    std::atomic_bool crashing{ false };
}

LONG CALLBACK ExceptionHandler(const LPEXCEPTION_POINTERS e)
{
    // a second crash while reporting the first one: let Windows end it
    if (crashing.exchange(true))
        return EXCEPTION_CONTINUE_SEARCH;

    const std::string dir = crashDir();
    const std::string stamp = stdext::date_time_string("%Y%m%d-%H%M%S");
    const std::string dumpName = fmt::format("{}\\crash-{}.dmp", dir, stamp);
    const std::string fileName = fmt::format("{}\\crashreport.log", dir);

    // the dump first: it does not depend on anything the crash may have broken
    writeMiniDump(e, dumpName);

    std::stringstream oss;
    oss << fmt::format(
        "== application crashed\n"
        "app name: {}\n"
        "app version: {}\n"
        "build compiler: {} - {}\n"
        "build date: {}\n"
        "build type: {}\n"
        "build revision: {} ({})\n"
        "crash date: {}\n"
        "exception: {} (0x{:08X})\n"
        "exception address: 0x{:X}\n"
        "dump: {}\n"
        "renderer: {}\n"
        "gpu: {} | {} | {}\n"
        "system: {}\n"
        "memory: {}\n"
        "  backtrace:\n",
        g_app.getName(),
        g_app.getVersion(),
        g_app.getBuildCompiler(), g_app.getBuildArch(),
        g_app.getBuildDate(),
        g_app.getBuildType(),
        g_app.getBuildRevision(), g_app.getBuildCommit(),
        stdext::date_time_string(),
        getExceptionName(e->ExceptionRecord->ExceptionCode), e->ExceptionRecord->ExceptionCode,
        reinterpret_cast<std::uintptr_t>(e->ExceptionRecord->ExceptionAddress),
        dumpName,
#ifdef OPENGL_ES
        "DirectX (ANGLE)",
#else
        "OpenGL",
#endif
        g_graphics.getVendor(), g_graphics.getRenderer(), g_graphics.getVersion(),
        windowsVersion(),
        memoryInfo()
    );

    SymSetOptions(SymGetOptions() | SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS);
    SymInitialize(GetCurrentProcess(), nullptr, TRUE);
    Stacktrace(e, oss);
    SymCleanup(GetCurrentProcess());
    oss << "  log of this session (last lines):\n" << g_logger.getRecentLog(60)
        << "  log file (last lines):\n" << logTail(8 * 1024) << "== end of report\n\n";

    std::ofstream fout(fileName, std::ios::out | std::ios::app);
    if (fout.is_open()) {
        fout << oss.str();
        fout.close();
    }
    pruneDumps(dir, 3);

    const std::string msg = fmt::format(
        "O jogo fechou por causa de um erro.\n"
        "O relatorio do erro sera enviado automaticamente para a equipe na proxima vez que voce abrir o jogo.\n\n"
        "The game has crashed.\n"
        "The crash report will be sent to the staff automatically the next time you open the game.\n\n"
        "{}\n{}",
        fileName, dumpName
    );
    MessageBoxA(nullptr, msg.c_str(), "Application crashed", MB_OK | MB_ICONERROR);

    return EXCEPTION_CONTINUE_SEARCH;
}

namespace {
    // Errors the C runtime reports without raising an SEH exception (abort,
    // an uncaught C++ exception, a bad CRT argument, a pure virtual call)
    // end the process silently in a release build: turn them into a report.
    [[noreturn]] void reportAndExit(const DWORD code)
    {
        CONTEXT context;
        RtlCaptureContext(&context);
        EXCEPTION_RECORD record{};
        record.ExceptionCode = code;
#ifdef _WIN64
        record.ExceptionAddress = reinterpret_cast<PVOID>(context.Rip);
#else
        record.ExceptionAddress = reinterpret_cast<PVOID>(context.Eip);
#endif
        EXCEPTION_POINTERS pointers{ &record, &context };
        ExceptionHandler(&pointers);
        TerminateProcess(GetCurrentProcess(), code);
        for (;;) {}
    }

    // custom codes, shown as "Unknown exception" plus the code in the report
    constexpr DWORD CODE_ABORT = 0xE0000001;
    constexpr DWORD CODE_TERMINATE = 0xE0000002;
    constexpr DWORD CODE_INVALID_PARAMETER = 0xE0000003;
    constexpr DWORD CODE_PURE_CALL = 0xE0000004;
}

void installCrashHandler()
{
    SetUnhandledExceptionFilter(ExceptionHandler);

    // room for the handler to run after a stack overflow on this thread
    ULONG guarantee = 64 * 1024;
    SetThreadStackGuarantee(&guarantee);

    signal(SIGABRT, [](int) { reportAndExit(CODE_ABORT); });
    std::set_terminate([] { reportAndExit(CODE_TERMINATE); });
    _set_invalid_parameter_handler([](const wchar_t*, const wchar_t*, const wchar_t*, unsigned int, uintptr_t) { reportAndExit(CODE_INVALID_PARAMETER); });
    _set_purecall_handler([] { reportAndExit(CODE_PURE_CALL); });
#ifdef _MSC_VER
    // abort() would otherwise show its own dialog or skip the handler
    _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
#endif
}

#endif