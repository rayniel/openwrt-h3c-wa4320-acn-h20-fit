# 会话交接：H3C WA4320 OpenWrt 适配

## 会话标识

- Copilot 会话 ID：`f1aabadd-fc9e-4107-a5f6-36c5a6e94037`
- 仓库：`rayniel/openwrt-h3c-wa4320-acn-h20-fit`
- 本次交接前的远端 `main` 提交：`d9c5b63d24b0489ec3d474c4e96458c97b122f6f`

会话 ID 可用于尝试查找历史，但跨机器能否恢复完整会话取决于会话存储是否可用。本文不包含密码、私钥或原厂 Flash 数据。

## 当前任务：在 OpenWrt 中测试 QCA8337 网口灯

- 用户的 AP 是 H3C WA4320-ACN-H20-FIT，使用的是 K2T Breed，**不是 K2T 硬件**。
- QCA8337 使用 OpenWrt 24.10 的 `ar8xxx` / `swconfig` 驱动，CPU port 为 0。面板 1 对应 switch port 5 / 内部 PHY 4；面板 2、3、4 和 PoE IN 分别对应 switch port 4、3、2、1。
- 面板 1 在千兆连接时亮黄灯，用户说原厂固件同一端口在千兆时亮绿灯。不要照搬 K2T 的 LED 或 strap 数值。
- 设备当前运行 OpenWrt 24.10-SNAPSHOT，内核 `6.6.159`，版本 `r29306-34fa4b1af5`。`mdio-tools`、`kmod-mdio-netlink` 已安装，模块已加载，`mdio` 能列出 `mdio.0`；读取 PHY 4 的标准标识寄存器成功，port 5 协商千兆。
- 用户选择**在 OpenWrt 中构建原子访问工具**，而不是再次重启到 Breed。

### 安全约束

QCA8337 的 32 位交换机寄存器通过分页 MDIO 窗口访问。OpenWrt 的 `ar8xxx_read` / `ar8xxx_write` 在同一个 `mii_bus->mdio_lock` 内选页、等待切页并访问寄存器。多条 `mdio ... phy ... raw` 命令分别加锁，可能被正在运行的交换机驱动穿插，读写错误寄存器；不要用这种方式测试 LED。

`mdio-netlink` 支持在同一把 MDIO 锁内执行多条操作，但其指令集没有明确的等待指令，不能假设选页后立即访问符合硬件时序。已构建 `tools/qca8337-atomic` 测试模块，在同一把锁内选页、等待并访问；模块必须与当前运行内核匹配。使用前先确认寄存器基线，不要直接写未知寄存器。

计划识别面板 1 的 LED 输出时，需逐路临时强制灭/亮、记录现象、恢复并读回原值。必须保留串口恢复途径，避免改 VLAN、SGMII、strap、Flash 或 ART；如果验证表明方案不安全，停止并告知用户。

### 已有测试

- 在 Breed 下曾读取 LED_CTRL0/1/2 为 `0xcf35cf35`、LED_CTRL3 为 `0x03ffff00`。这是当时 Breed 环境的值，不应视作 H3C 原厂配置，也不能假设和当前 OpenWrt 一致。
- Port 5 千兆时分别临时清除三路 LED 规则的千兆位，黄灯均仍亮；三路最后均恢复为 `0xcf35` 并读回核对。该测试不足以判断灯的接线。
- OpenWrt 运行时通过原子工具测试：面板 1 和 PoE IN 千兆绿闪，面板 2 百兆黄闪；候选规则使用 LED_CTRL0/1/2/3 分别为 `0xc731c731`、`0xc335c335`、`0x0f350f35`、`0x00f3cf00`。百兆流量、10M、面板 3/4 及包含新设备树的固件尚未验证。
- 每轮测试后均将寄存器恢复原值并读回，临时模块已卸载。候选规则已加入板级设备树，需先构建 initramfs 并经用户同意实机验证。

## 已完成的 SYS 灯修复

提交 `d9c5b63d24b0489ec3d474c4e96458c97b122f6f` 已推送：

- SYS 绿灯 GPIO 8、低电平点亮；SYS 黄灯 GPIO 7、高电平点亮，GPIO 与极性已实测。
- 独立 WiFi 绿灯经临时测试确认为 GPIO 19：低电平亮，高电平灭。测试后恢复为输入并取消导出。设备树及专用控制包配置任一无线频段运行时闪烁、全部关闭时熄灭；本地修改根据双频收发总速率调节闪烁速度，尚未实机验证。不要盲目操作其他未知 GPIO。
- 用户确认原厂 WiFi 灯曾亮黄色，希望 5 GHz 绿灯和 2.4 GHz 黄灯各自随流量闪烁、双频同时开启时两色同时工作。当前设备的 `phy0tpt`（5 GHz）和 `phy1tpt`（2.4 GHz）触发器可用；临时将 WiFi 绿灯切换到 `phy0tpt` 后，用户观察到闪烁，测试结束后原灯服务和 timer 已恢复。尚未验证随流量变化的速度，也未找到黄灯控制线、确认双通道能否同时工作。不要猜测或写入未知 GPIO。
- 包含修复的固件已刷入，但最终面板灯效仍需用户确认。

## USB 驱动

`apply.sh` 已加入 USB 2.0、USB 存储、CDC ACM、CH341、CH348、CP210x、FTDI、PL2303 和 OpenWrt 24.10 packages feed 的 `kmod-usb-serial-xr_usb_serial_common`。已验证包名、脚本语法和重复运行行为；包含这些默认驱动的新固件仍需完整编译和实机验证。当前工作区的具体状态以 `git status` 和 `git diff` 为准。

## 构建环境与已知问题

- 用户编译机上的 OpenWrt 源码目录为 `/home/honzon/devel/h3c-ap/openwrt`；此前用于连接串口的主机不是这台编译机。
- 用户曾遇到 `dnsdist`、`dnsdist-full`、`snort3`、`knot-resolver` 和 `openappid` 的 Kconfig 循环依赖，生成配置中包含自引用的 LuaJIT provider 条件。上游修复参考 [openwrt/openwrt#26444](https://github.com/openwrt/openwrt/pull/26444)，该补丁针对 25.12；24.10 必须先检查适用性。用户是否已应用及结果未知。
- `apply.sh` 默认会覆盖目标源码树 `.config` 并执行 `make defconfig`；仅应用设备支持可用 `--no-config`。不要覆盖用户配置前先确认。
- 编译内核模块时必须使用与 AP 当前运行内核匹配的源码、配置和构建产物；仅 `6.6.159` 版本号相同不够。

## 其他硬件和升级状态

- DC 冷启动曾在 ath9k OTP 回退读取时发生总线错误。现有板级保护和日志是防护/诊断，不是已验证的根因修复。此前 DC 成功启动时日志显示校准数据读到 1088 字节、`txrxMask=0x33` 被接受。
- USB 控制器已注册，但先前插入 U 盘只看到 root hub、没有枚举外部设备；增加驱动不等于已解决。
- 当前 DC 供电下，U 盘在电脑上可识别；临时将候选 USB 电源 GPIO 21 拉低后仍无枚举，测试结束已恢复输入并取消导出。原厂驱动中只有部分板型使用该 GPIO，不能据此认定本机接线或 USB 供电状态。
- 当前运行固件的 USB0/USB1 均已启动，但重新插入 U 盘后仍无枚举事件。只读检查发现两控制器指向同一 PHY 节点、使用 USB1 的 `rst2` 复位线路；设备树已将 USB0 PHY 恢复为 `rst`，测试选项为 USB1 配置独立 PHY 和 `rst2`。设备树编译检查了两种配置的 phandle 和复位映射，但未构建固件或实机验证，供电及 USB1 接线仍未知。测试镜像只应通过 Breed 从 RAM 启动；恢复常规设备树时重新运行 `apply.sh --no-config`。
- sysupgrade 时旧 JFFS2 overlay 曾报 `Resource busy` 和 `Busy inodes`，随后升级报告完成。新系统已冷启动，SSH 可用，当前 `/overlay` 为读写 JFFS2，当前启动未见同类警告；配置持久性尚未单独确认。
- 上游 [openwrt/openwrt#25025](https://github.com/openwrt/openwrt/issues/25025) 报告了相同卸载警告；[openwrt/openwrt#26520](https://github.com/openwrt/openwrt/pull/26520) 提出修复 JFFS2 whiteout inode 引用泄漏，尚未合并。已将该修复回移为 ath79 Linux 6.6 目标补丁；是否消除本机警告及独立的 `Resource busy` 提示仍需构建和实机验证。
- 保留本机原厂 ART，不要擦除或上传。未经用户同意不要刷写、重启或修改设备持久配置。
