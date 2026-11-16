# H3C WA4320-ACN-H20-FIT 的 OpenWrt 24.10 适配

SoC 是 QCA9563，交换芯片是 QCA8337（SGMII 接 eth0），16MB SPI NOR（W25Q128），128MB 内存，
5G 为 PCIe ath10k，2.4G 为内置 wmac。

## 使用

在 Linux 下准备好 OpenWrt 24.10 源码，并先执行 `./scripts/feeds update -a && ./scripts/feeds install -a`：

```sh
git clone -b openwrt-24.10 https://github.com/openwrt/openwrt.git
./apply.sh ./openwrt --build     # 打补丁、生成 .config、下载源码并编译
```

只打补丁用 `./apply.sh ./openwrt`；打补丁并生成 `.config`（之后自己 `make menuconfig`）用 `--config`。
脚本可重复执行。镜像生成在 `bin/targets/ath79/generic/`。

## 脚本做了什么

- 复制 `files/qca9563_h3c_wa4320-acn-h20-fit.dts` 到 `target/linux/ath79/dts/`
- 向 `image/generic.mk` 追加设备定义（firmware 分区 16000k）
- 向 `02_network` 添加交换机配置，已用 Breed 的 MDIO 实测端口对应关系：

| 面板口 | PHY | 交换机端口 | OpenWrt 名称 |
|---|---|---|---|
| 1 | 4 | 5 | lan1 |
| 2 | 3 | 4 | lan2 |
| 3 | 2 | 3 | lan3 |
| 4 | 1 | 2 | lan4 |
| PoE IN | 0 | 1 | lan5 |

## Flash 分区（按 Breed 的 K2T 布局）

| 区域 | 偏移 | 大小 |
|---|---|---|
| u-boot（Breed） | 0x000000 | 0x1e000 |
| breed-env（Breed 内部环境变量，`ethaddr` 在 +0xc） | 0x01e000 | 0x1000 |
| devicedata（原厂数据，未使用） | 0x0a0000 | 0x10000 |
| art（2.4G 校准 +0x1000，5G 校准 +0x5000） | 0x0e0000 | 0x10000 |
| firmware | 0x100000 | 0xf00000 |

## MAC 地址

MAC 来自 Breed 内部环境变量（Breed 网页 → 环境变量设置，选 [Breed 内部]，位置 0x1e000）。
在 Breed 里设置 `ethaddr=XX:XX:XX:XX:XX:XX`，重刷 OpenWrt 不会丢失。

- `ethaddr` 必须是环境变量里的**第一个**变量（OpenWrt 按固定偏移 0xc 读取 17 个字符）
- eth0 用 `ethaddr`，2.4G 用 +1，5G 用 +2
- 若未设置 `ethaddr`，MAC 会读取失败，使用随机地址

### WAN 口的 MAC

五个网口都挂在同一个 `eth0` 上，由 QCA8337 交换芯片用 VLAN 划分。当前没有给 WAN 单独指定 MAC：

- 未配置 WAN 时，`br-lan` 继承 `eth0` 的 MAC（`ethaddr`）。
- 配置了 WAN（如 `eth0.2`）时，WAN 同样继承 `eth0` 的 MAC，与 LAN 相同。LAN 和 WAN 属于不同二层域，通常没有问题。
- 需要不同的 WAN MAC（如运营商绑定 MAC）时，可在 LuCI 的 WAN 接口里手动设置，或在 `02_network` 中使用 `ucidef_set_interface_macaddr "wan" "$(macaddr_add $(cat /sys/class/net/eth0/address) 3)"`。
- 2.4G 已用 +1，5G 已用 +2，所以 WAN 建议用 +3，避免重复。

## 尚未实测的项目

- LED 的 GPIO 极性（GPIO 6/7/8 来自 Breed）
- 网口的链路速率和实际转发（目前只在 Breed 里验证了 PHY 链路状态）
- 5G 的 PCIe 设备已实测为 QCA9888（168c:0056），使用 ath10k-firmware-qca9888-ct
- 各 MAC 的递增规则已实现（eth0 +0，2.4G +1，5G +2），待实测

## GitHub Actions

推送到 GitHub 后，在 Actions 页选择 **Build OpenWrt**，点 Run workflow，默认分支 openwrt-24.10。完成后在 Artifacts 下载 initramfs-kernel 和 sysupgrade 镜像。
