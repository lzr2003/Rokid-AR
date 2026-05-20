#ifndef ROKID_REGISTER_TYPES_H
#define ROKID_REGISTER_TYPES_H

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// 不要包在额外的 namespace 里
void initialize_rokid_module(ModuleInitializationLevel p_level);
void uninitialize_rokid_module(ModuleInitializationLevel p_level);

#endif // ROKID_REGISTER_TYPES_H