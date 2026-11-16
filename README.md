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
- 向 `image/generic.mk` 追加设备定义（firmware 分区 15360k）
- 向 `02_network` 添加交换机配置，已用 Breed 的 MDIO 实测端口对应关系：

| 面板口 | PHY | 交换机端口 | OpenWrt 名称 |
|---|---|---|---|
| 1 | 4 | 5 | lan1 |
| 2 | 3 | 4 | lan2 |
| 3 | 2 | 3 | lan3 |
| 4 | 1 | 2 | lan4 |
| PoE IN | 0 | 1 | lan5 |

## Flash 分区（沿用原厂位置）

| 区域 | 偏移 | 大小 |
|---|---|---|
| u-boot（Breed） | 0x000000 | 0x80000 |
| devicedata（MAC 在 +0x800） | 0x0a0000 | 0x10000 |
| art（2.4G 校准 +0x1000，5G 校准 +0x5000） | 0x0e0000 | 0x10000 |
| firmware | 0x100000 | 0xf00000 |

## 尚未实测的项目

- LED 的 GPIO 极性（GPIO 6/7/8 来自 Breed）
- 网口的链路速率和实际转发（目前只在 Breed 里验证了 PHY 链路状态）
- 5G 的 PCIe 设备是否为 QCA9880 系列
- 各 MAC 的递增规则（目前 eth0 和 wmac 共用 devicedata 里的同一个 MAC）

## GitHub Actions

���͵� GitHub ���� Actions ҳѡ�� **Build OpenWrt**���� Run workflow��Ĭ�Ϸ�֧ openwrt-24.10����ɺ��� Artifacts ���� initramfs-kernel �� sysupgrade ����
