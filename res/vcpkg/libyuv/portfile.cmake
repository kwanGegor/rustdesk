vcpkg_check_linkage(ONLY_STATIC_LIBRARY)

vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL https://chromium.googlesource.com/libyuv/libyuv
    REF 0faf8dd0e004520a61a603a4d2996d5ecc80dc3f
    # Check https://chromium.googlesource.com/libyuv/libyuv/+/refs/heads/main/include/libyuv/version.h for a version!
    PATCHES
        fix-cmakelists.patch
)

# 新增：提前初始化 BUILD_OPTIONS，避免未定义警告
set(BUILD_OPTIONS "")

vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# 修改点1：移除 UWP 判断，强制所有 MSVC 环境使用 Clang-Cl，彻底规避纯 MSVC 编译
if (VCPKG_DETECTED_CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    # Most of libyuv accelerated features need to be compiled by clang/gcc, so force use clang-cl, otherwise the performance is too poor.
    # Manually build the port with clang-cl when using MSVC as compiler
    message(STATUS "Set compiler to clang-cl for libyuv (avoid slow MSVC build)")

    # 保留架构检查跳过策略，适配 x86_64 平台
    set(VCPKG_POLICY_SKIP_ARCHITECTURE_CHECK enabled)

    # 修改点2：指定 Clang 版本要求，确保获取有效编译器
    vcpkg_find_acquire_program(CLANG)
    if (CLANG MATCHES "-NOTFOUND")
        message(FATAL_ERROR "Clang is required for libyuv build. Please install Clang via vcpkg or system path.")
    endif ()
    get_filename_component(CLANG_BIN_DIR "${CLANG}" DIRECTORY)

    # 修改点3：完善 x86_64 架构映射，确保目标架构正确
    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm")
        set(CLANG_TARGET "arm")
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
        set(CLANG_TARGET "aarch64")
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86")
        set(CLANG_TARGET "i686")
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
        set(CLANG_TARGET "x86_64")
    else()
        message(FATAL_ERROR "Unsupported target architecture for libyuv: ${VCPKG_TARGET_ARCHITECTURE}")
    endif()

    set(CLANG_TARGET "${CLANG_TARGET}-pc-windows-msvc")
    message(STATUS "Using clang target for libyuv: ${CLANG_TARGET}")

    # 修改点4：避免字符串追加溢出，直接设置编译标志
    set(VCPKG_DETECTED_CMAKE_CXX_FLAGS "--target=${CLANG_TARGET}")
    set(VCPKG_DETECTED_CMAKE_C_FLAGS "--target=${CLANG_TARGET}")

    # 完善编译选项，指定 Clang-Cl 路径，添加静态编译标志
    set(BUILD_OPTIONS
            -DCMAKE_CXX_COMPILER=${CLANG_BIN_DIR}/clang-cl.exe
            -DCMAKE_C_COMPILER=${CLANG_BIN_DIR}/clang-cl.exe
            -DCMAKE_CXX_FLAGS=${VCPKG_DETECTED_CMAKE_CXX_FLAGS}
            -DCMAKE_C_FLAGS=${VCPKG_DETECTED_CMAKE_C_FLAGS}
            -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug> # 静态运行时，避免依赖问题
    )
endif ()

vcpkg_cmake_configure(
    SOURCE_PATH ${SOURCE_PATH}
    DISABLE_PARALLEL_CONFIGURE
    OPTIONS
        ${BUILD_OPTIONS}
    OPTIONS_DEBUG
        -DCMAKE_DEBUG_POSTFIX=d
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()

vcpkg_cmake_config_fixup(CONFIG_PATH share/cmake/libyuv)

# 清理冗余文件，避免构建缓存冲突
file(REMOVE_RECURSE ${CURRENT_PACKAGES_DIR}/debug/include)
file(REMOVE_RECURSE ${CURRENT_PACKAGES_DIR}/debug/share)

# 复制配置文件，确保 libyuv 可被其他包找到
configure_file(${CMAKE_CURRENT_LIST_DIR}/libyuv-config.cmake ${CURRENT_PACKAGES_DIR}/share/${PORT} COPYONLY)
file(INSTALL ${SOURCE_PATH}/LICENSE DESTINATION ${CURRENT_PACKAGES_DIR}/share/${PORT} RENAME copyright)

# 修改点5：优化警告提示，明确 x86_64 平台的编译状态
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")
if (VCPKG_DETECTED_CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    message(STATUS "libyuv built with Clang-Cl on MSVC environment (x86_64), performance issue resolved.")
    file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage-msvc" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME "usage")
else ()
    file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
endif ()