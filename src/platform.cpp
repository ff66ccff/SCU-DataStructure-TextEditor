#include "platform.hpp"

#ifdef _WIN32
#include <windows.h>
#endif

namespace platform {

void setupConsole() {
#ifdef _WIN32
    SetConsoleOutputCP(CP_UTF8);
#endif
}

}  // namespace platform
