<p align="right">English | <a href="ru#readme">Русский</a></p>


### OpenWRT firmware installer for Xiaomi AX3000T

This installer automates [installation instructions from OpenWRT docs](https://openwrt.org/inbox/toh/xiaomi/ax3000t#installation), some of the code has been taken directly from there.

Works on Linux. Can be run on Windows with Windows Subsystem for Linux (WSL) or virtual machine.

[Video demo, ⏱️ 2 min.](https://youtu.be/FMnWNaDLeDU)


0. [Download OpenWRT](https://firmware-selector.openwrt.org/?target=mediatek/filogic&id=xiaomi_mi-router-ax3000t) `initramfs-factory` and `sysupgrade` images

1. Download this installer to the same directory:

    ```sh
    wget https://github.com/shvchk/openwrt-installer-ax3000t/raw/main/flash.sh
    ```

2. Disconnect from your current network

3. Turn on your Xiaomi AX3000T router

    It should be connected to your computer with Ethernet cable

4. Inspect the script, then run it:

    ```sh
    bash flash.sh
    ```
