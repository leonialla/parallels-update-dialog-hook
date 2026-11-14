#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>

// Minimal Qt 5 ABI declarations. QObject::metaObject() is its first virtual
// method, supplied by Q_OBJECT in the Parallels dialog class.
struct QMetaObjectShim;
struct QObjectShim {
  virtual const QMetaObjectShim* metaObject() const;
};

using ClassNameFn = const char* (*)(const QMetaObjectShim*);

static void trace(const char* message) {
  const char* path = std::getenv("PRL_HOOK_LOG");
  if (!path) return;
  if (FILE* file = std::fopen(path, "a")) {
    std::fprintf(file, "%s\n", message);
    std::fclose(file);
  }
}

extern "C" int original_dialog_exec(void*)
    __asm__("__ZN7QDialog4execEv");

extern "C" int block_update_dialog(void* self) {
  const auto* meta = reinterpret_cast<QObjectShim*>(self)->metaObject();
  auto class_name = reinterpret_cast<ClassNameFn>(
      dlsym(RTLD_DEFAULT, "_ZNK11QMetaObject9classNameEv"));
  const char* name = meta && class_name ? class_name(meta) : nullptr;
  if (name && std::strcmp(name, "CUpdateDialog") == 0) {
    trace("blocked CUpdateDialog");
    return 0; // QDialog::Rejected, the same result as cancelling the dialog.
  }
  return original_dialog_exec(self);
}

__attribute__((constructor)) static void hook_loaded() {
  trace("loaded Parallels update hook");
}

struct InterposePair { const void* replacement; const void* replacee; };
__attribute__((used, section("__DATA,__interpose")))
static const InterposePair interposer = {
    reinterpret_cast<const void*>(block_update_dialog),
    reinterpret_cast<const void*>(original_dialog_exec),
};
