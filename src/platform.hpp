#pragma once

// 控制台输出编码：程序内部字面量与输出统一使用 UTF-8，而 Windows 控制台默认
// 按本地代码页解释字节，中文帮助/提示会显示成乱码。
//
// 约定：
//   * stdout / stderr 一律输出 **UTF-8** 字节；
//   * 启动时把控制台输出代码页切到 UTF-8。
namespace platform {

// 把控制台输出代码页切到 UTF-8；非 Windows 为空操作。
void setupConsole();

}  // namespace platform
