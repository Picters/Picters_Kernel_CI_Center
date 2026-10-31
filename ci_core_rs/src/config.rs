use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct ProjectConfig {
    pub repo: String,
    pub defconfig: String,
    pub localversion_base: String,
    pub lto: Option<String>,
    pub supported_ksu: Option<Vec<String>>,
    pub toolchain_urls: Option<Vec<String>>,
    pub toolchain_sha256: Option<HashMap<String, String>>,
    pub toolchain_path_prefix: Option<String>,
    pub toolchain_path_exports: Option<Vec<String>>,
    pub anykernel_config: Option<String>,
    pub zip_name_prefix: Option<String>,
    pub version_method: Option<String>,
    pub extra_host_env: Option<bool>,
    pub disable_security: Option<Vec<String>>,
    pub readme_placeholders: Option<HashMap<String, String>>,
    pub susfs: Option<SusfsConfig>,
    pub bbg: Option<BbgConfig>,
    pub watch_upstream_variants: Option<Vec<String>>,
    // Extra modules: defconfig fragment merged on top of `defconfig`, and the
    // whitelist of module basenames packaged into the AnyKernel3 payload.
    pub extra_fragment: Option<String>,
    pub extra_modules: Option<String>,
    // Out-of-tree Wi-Fi injection drivers (aircrack rtl8812au/8814au/8188eus)
    // cloned + built best-effort against the just-built kernel; failures are
    // logged and never abort the main build.
    pub extra_oot_modules: Option<Vec<OotModule>>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct OotModule {
    pub repo: String,
    pub branch: Option<String>,
    // Path under the kernel source tree to clone into / build with `make M=`.
    pub subdir: String,
    // Extra make variables the driver needs, e.g. ["CONFIG_88XXAU=m"].
    pub make_args: Option<Vec<String>>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct SusfsConfig {
    pub repo: String,
    pub revision: Option<String>,
    pub branch: String,
    pub patch_path: String,
    pub fs_patch_dir: Option<String>,
    pub include_linux_patch_dir: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct BbgConfig {
    pub setup_url: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct GlobalConfig {
    pub broadcast_channel: Option<String>,
    pub resukisu_chat_id: Option<String>,
    pub resukisu_topic_id: Option<i32>,
}

pub type ProjectsMap = HashMap<String, serde_json::Value>;
pub type AnyKernelConfigMap = HashMap<String, AnyKernelConfig>;

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct AnyKernelConfig {
    pub kernel_string: String,
    pub device_check: bool,
    pub modules: bool,
    pub systemless: bool,
    pub cleanup: bool,
    pub cleanup_on_abort: bool,
    pub device_names: Vec<String>,
    pub supported_versions: Option<String>,
    pub supported_patchlevels: Option<String>,
    pub supported_vendorpatchlevels: Option<String>,
    pub block: String,
    pub is_slot_device: bool,
    pub ramdisk_compression: Option<String>,
    pub patch_vbmeta_flag: Option<String>,
    pub boot_setup: Option<String>,
    pub boot_finalize: Option<String>,
}

pub const KSU_CONFIG_JSON: &str = r#"{
    "bakasu": {
        "repo": "https://github.com/Baka-SU/BakaSU.git",
        "branch": "main",
        "setup_url": "https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh",
        "setup_args": ["main"]
    }
}"#;

#[derive(Deserialize)]
pub struct KsuConfigItem {
    pub repo: String,
    pub branch: String,
    pub setup_url: String,
}
