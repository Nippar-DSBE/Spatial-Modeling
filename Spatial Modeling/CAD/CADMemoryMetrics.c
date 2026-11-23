/* Copyright (c) 2026 Design Studio Butterfly Effect
 * SPDX-License-Identifier: MIT */

#include "CAD-Bridging-Header.h"
#include <mach/mach.h>
#include <mach/task_info.h>
uint64_t cad_memory_bytes(void) {
    task_vm_info_data_t info = {0};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
    return result == KERN_SUCCESS ? info.phys_footprint : 0;
}
