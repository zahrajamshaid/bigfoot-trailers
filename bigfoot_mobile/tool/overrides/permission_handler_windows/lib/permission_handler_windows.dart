// Intentionally empty.
//
// This is a no-op stand-in for the real `permission_handler_windows` plugin.
// It exists only so a `dependency_overrides` entry can keep that plugin's
// native DLL out of the Windows build (see this package's pubspec for why).
// Nothing imports this library; the desktop app never calls permission_handler.
