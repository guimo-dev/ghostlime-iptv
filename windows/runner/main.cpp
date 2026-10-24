#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdlib>
#include <cwchar>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

// Window origin from GHOSTLIME_WINDOW_ORIGIN ("x,y"), so visual tests can open
// on a secondary monitor. Falls back to the default origin when unset or invalid.
static Win32Window::Point WindowOrigin() {
  Win32Window::Point origin(10, 10);
  wchar_t value[64] = {};
  DWORD length =
      ::GetEnvironmentVariableW(L"GHOSTLIME_WINDOW_ORIGIN", value, 64);
  // 0 means unset; 64 or more means it did not fit (the buffer is untouched).
  if (length > 0 && length < 64) {
    wchar_t *end = nullptr;
    long x = std::wcstol(value, &end, 10);
    if (end != value && *end == L',') {
      wchar_t *y_start = end + 1;
      long y = std::wcstol(y_start, &end, 10);
      if (end != y_start && *end == L'\0') {
        origin = Win32Window::Point(x, y);
      }
    }
  }
  return origin;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // The browser returns from "Continuar con Google" by opening
  // ghostlime://login-callback?code=..., which starts a second copy of the
  // app. Hand the link to the window already open (app_links, the plugin
  // supabase_flutter listens to, via WM_COPYDATA) and quit. Other launches,
  // and a link with no window open, start the app as usual.
  if (std::wcsstr(command_line, L"ghostlime://") != nullptr &&
      SendAppLinkToInstance()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin = WindowOrigin();
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Ghostlime IPTV", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
