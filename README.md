# AlipayQRCodeAuth（支付宝显码 · 侦查版）

TrollStore 免签名安装。设备**不安装支付宝**时，第三方 App（百度极速版等）发起「支付宝提现/登录」会打开 `alipays://` / `alipay://`，本 App 注册这些 scheme 后会被系统拉起。

当前为**侦查版**：只负责接收并完整展示跳转数据（原始 URL、参数、深度解码的授权 payload、回调 scheme、剪贴板），不取码、不回跳，用于确认百度发起的支付宝授权参数结构。

- Bundle ID：`com.alipayqr.qrauth`
- 注册 scheme：`alipay`、`alipays`、`alipayqr`
- 无签名、无后端、无第三方密钥
- GitHub Actions（macos-15）产出未签名 arm64 IPA，TrollStore 直接安装
