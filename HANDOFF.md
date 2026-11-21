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

`mdio-netlink` 支持在同一把 MDIO 锁内执行多条操作，但其指令集没有明确的等待指令，不能假设选页后立即访问符合硬件时序。下一步需要研究并实现**与当前内核匹配**的安全访问方案，例如小型测试模块，遵循现有驱动的切页等待、加锁和错误处理。先验证方案和工具，再只读确认交换机及 LED 寄存器；不要直接写未知寄存器。

计划识别面板 1 的 LED 输出时，需逐路临时强制灭/亮、记录现象、恢复并读回原值。必须保留串口恢复途径，避免改 VLAN、SGMII、strap、Flash 或 ART；如果验证表明方案不安全，停止并告知用户。

### 已有测试

- 在 Breed 下曾读取 LED_CTRL0/1/2 为 `0xcf35cf35`、LED_CTRL3 为 `0x03ffff00`。这是当时 Breed 环境的值，不应视作 H3C 原厂配置，也不能假设和当前 OpenWrt 一致。
- Port 5 千兆时分别临时清除三路 LED 规则的千兆位，黄灯均仍亮；三路最后均恢复为 `0xcf35` 并读回核对。该测试不足以判断灯的接线。
- 当前板级 DTS 的 `qca,ar8327-initvals` 未设置 LED_CTRL；适当值需要通过板级实测确定。

## 已完成的 SYS 灯修复

提交 `d9c5b63d24b0489ec3d474c4e96458c97b122f6f` 已推送：

- SYS 绿灯 GPIO 8、低电平点亮；SYS 黄灯 GPIO 7、高电平点亮，GPIO 与极性已实测。
- GPIO 6 和独立 WiFi 指示灯接线尚未确认。不要盲目操作未知 GPIO。
- 包含修复的固件已刷入，但最终面板灯效仍需用户确认。

## 本地待提交更改

交接时仓库还有以下未提交修改，应与本文件一起保留并上传：

- `apply.sh`：为全新和已应用过的 OpenWrt 源码树添加 USB 2.0、USB 存储、CDC ACM、CH341、CH348、CP210x、FTDI、PL2303 和 OpenWrt 24.10 packages feed 的 `kmod-usb-serial-xr_usb_serial_common`；重复运行不重复添加。
- `README.md`：更新上述 USB 驱动信息，并记录 U 盘不枚举问题。

已验证包名存在于 OpenWrt 24.10 源码及 packages feed，`bash -n` 通过，使用临时模拟源码树验证全新、旧树和重复运行；**尚未在真实 OpenWrt 源码树完整编译或实机验证**。当前工作区的具体状态以 `git status` 和 `git diff` 为准。

## 构建环境与已知问题

- 用户编译机上的 OpenWrt 源码目录为 `/home/honzon/devel/h3c-ap/openwrt`；此前用于连接串口的主机不是这台编译机。
- 用户曾遇到 `dnsdist`、`dnsdist-full`、`snort3`、`knot-resolver` 和 `openappid` 的 Kconfig 循环依赖，生成配置中包含自引用的 LuaJIT provider 条件。上游修复参考 [openwrt/openwrt#26444](https://github.com/openwrt/openwrt/pull/26444)，该补丁针对 25.12；24.10 必须先检查适用性。用户是否已应用及结果未知。
- `apply.sh` 默认会覆盖目标源码树 `.config` 并执行 `make defconfig`；仅应用设备支持可用 `--no-config`。不要覆盖用户配置前先确认。
- 编译内核模块时必须使用与 AP 当前运行内核匹配的源码、配置和构建产物；仅 `6.6.159` 版本号相同不够。

## 其他硬件和升级状态

- DC 冷启动曾在 ath9k OTP 回退读取时发生总线错误。现有板级保护和日志是防护/诊断，不是已验证的根因修复。此前 DC 成功启动时日志显示校准数据读到 1088 字节、`txrxMask=0x33` 被接受。
- USB 控制器已注册，但先前插入 U 盘只看到 root hub、没有枚举外部设备；增加驱动不等于已解决。
- sysupgrade 时旧 JFFS2 overlay 曾报 `Resource busy` 和 `Busy inodes`，随后升级报告完成。新系统已冷启动，SSH 可用，当前 `/overlay` 为读写 JFFS2，当前启动未见同类警告；配置持久性尚未单独确认。
- 保留本机原厂 ART，不要擦除或上传。未经用户同意不要刷写、重启或修改设备持久配置。
