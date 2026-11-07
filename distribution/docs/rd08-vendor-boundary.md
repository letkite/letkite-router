# Xiaomi BE6500 Pro RD08 — Qualcomm OEM boundary

This is **not** a supported stock-to-OpenWrt flashing target for this distribution.

Offline analysis of Xiaomi RD08 1.1.96 and 1.1.123 stock images established:
- Qualcomm IPQ5332 / OpenWrt 18.06 vendor branch / Linux 5.4.213.
- QCA kernel modules include wifi_3_0, qca_ol, qdf, ipq_cnss2, qca-ssdk, qca-nss-ppe, ecm; 24 radio-related and other modules/firmware blobs changed between compared releases even though kernel release remained 5.4.213.
- Original /lib/read_caldata_to_fs.sh reads device-specific calibration from partition 0:ART. Its ap-mi01.2* path references IPQ5332 offset 4096 and QCN9224 offset 157696; verify active board-specific branch and actual partition layout on the real device before interpreting those offsets.
- OEM boot and firmware sections, including uboot and 0:WIFIFW, have dedicated update handlers. Recovery via official MIWIFIRepairTool Windows program appears to use DHCP/TFTP; actual device-side partition overwrite scope remains unproven.
- Preserve OEM bootloader, ART, board/identity data, radio firmware, kernel and NSS/PPE module pairing. Never include another device's calibration, or claim generic images are flashable on RD08.

Recommended separate development sequence: (1) read-only device inventory; (2) encrypted local backups and hashed immutable ART/boot copies; (3) OEM-compatible application experiment, no flash; (4) full signed firmware research only after reproducing OEM update and recovery authorization checks. Do not include OEM proprietary components in public releases without rights.

Current experimental build profiles intentionally do **not** enable RD08. Research path on Compute-1: /home/cp1/workspace/rd08-firmware-research/.
