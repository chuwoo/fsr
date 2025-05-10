#!/bin/sh
# entrypoint.sh

set -e # Exit immediately if a command exits with a non-zero status.
       # 如果任何命令失败，立即退出。

# --- frpc.ini File Download Configuration ---
# --- frpc.ini 文件下载配置 ---

# 1. Hardcoded base URL for the INI files in the GitHub repository.
#    Ensure this URL ends with a slash (/).
#    硬编码的 GitHub 仓库中存放 INI 文件的原始基础 URL。
#    确保末尾有斜杠 /。
FIXED_GITHUB_REPO_RAW_BASE_URL="https://raw.githubusercontent.com/chuwoo/fsr/refs/heads/main/conf/"
# 2. Path to the default INI file pre-included in the image.
#    镜像内预置的默认 INI 文件的路径。
DEFAULT_CONFIG_SOURCE_PATH="/etc/default.frpc.ini"

# 3. Name of the INI file to download from GitHub.
#    This MUST be specified via the GITHUB_INI_FILENAME environment variable.
#    要从 GitHub 下载的 INI 文件的名称。
#    必须通过环境变量 GITHUB_INI_FILENAME 指定。
if [ -z "${FRP_CONF}" ]; then
  #echo "信息：环境变量 GITHUB_INI_FILENAME 未设置。"
  # If GITHUB_INI_FILENAME is not set, we will proceed to use the default config directly.
  # 如果 GITHUB_INI_FILENAME 未设置，我们将直接尝试使用默认配置。
  REMOTE_INI_SOURCE_URL="" # Mark that no download will be attempted
else
  # Construct the full remote INI file URL
  # 组合成完整的远程 INI 文件 URL
  REMOTE_INI_SOURCE_URL="${FIXED_GITHUB_REPO_RAW_BASE_URL}${FRP_CONF}"
fi


# --- Target path for frpc.ini inside the container ---
# --- frpc.ini 在容器内的目标路径 ---
TARGET_CONFIG_FINAL_PATH=""

# Iterate through the arguments passed to the script ($@) to find the -c option and its value.
# 迭代处理传递给脚本的参数 ($@)，以找到 -c 选项及其值。
count=0
while [ "$count" -lt "$#" ]; do
  count=$((count + 1))
  eval "current_arg=\${$count}" # Get current argument / 获取当前参数

  if [ "${current_arg}" = "-c" ]; then
    if [ "$count" -lt "$#" ]; then # Check if there's an argument after -c / 检查 -c 后面是否还有参数
      next_arg_index=$((count + 1))
      eval "TARGET_CONFIG_FINAL_PATH=\${$next_arg_index}" # Get the path argument after -c / 获取 -c 后面的路径参数
    fi
    break # Found -c, exit loop / 找到 -c，跳出循环
  fi
done

# If the target config path could not be parsed from arguments
# 如果未能从参数中解析出目标配置文件路径
if [ -z "${TARGET_CONFIG_FINAL_PATH}" ]; then
  echo "错误：未能在启动参数中找到 -c <路径> 来确定配置文件的目标路径。"
  echo "Dockerfile 的 CMD 指令应类似：CMD [\"-c\", \"/var/fsr/frpc.ini\"]"
  echo "当前接收到的参数为: $@"
  exit 1
fi

# Create the target directory if it doesn't exist
# 创建目标目录 (如果不存在)
TARGET_CONFIG_DIR=$(dirname "${TARGET_CONFIG_FINAL_PATH}")
mkdir -p "${TARGET_CONFIG_DIR}"


# Attempt to download the configuration file if GITHUB_INI_FILENAME was provided
# 如果提供了 GITHUB_INI_FILENAME，则尝试下载配置文件
download_successful=false
if [ -n "${REMOTE_INI_SOURCE_URL}" ]; then
  #echo "尝试从 GitHub 路径 ${FIXED_GITHUB_REPO_RAW_BASE_URL} 下载配置文件: ${GITHUB_INI_FILENAME}"
  #echo "完整的下载 URL 为: ${REMOTE_INI_SOURCE_URL}"
  #echo "下载后将在容器内保存为: ${TARGET_CONFIG_FINAL_PATH}"

  if wget -S -q -O "${TARGET_CONFIG_FINAL_PATH}" "${REMOTE_INI_SOURCE_URL}"; then
    #echo "成功下载 ${GITHUB_INI_FILENAME} 并另存为 ${TARGET_CONFIG_FINAL_PATH}"
    chmod 644 "${TARGET_CONFIG_FINAL_PATH}" # Set appropriate permissions / 设置适当的权限
    download_successful=true
  else
    #echo "警告：从 ${REMOTE_INI_SOURCE_URL} 下载 ${GITHUB_INI_FILENAME} 失败。"
    # download_successful remains false
  fi
else
  #echo "信息：未指定 GITHUB_INI_FILENAME，将跳过下载步骤。"
  # download_successful remains false, we need to use default or pre-existing.
fi


# If download was not successful, try to use the default config or an existing one.
# 如果下载不成功，则尝试使用默认配置或已存在的配置。
if [ "${download_successful}" = "false" ]; then
  #echo "下载未成功或未尝试下载。"
  # Check if the target file already exists (e.g., from a volume mount or previous successful run before restart)
  # 检查目标文件是否已存在（例如，通过卷挂载或在重启前上次成功运行后留下的文件）
  if [ -f "${TARGET_CONFIG_FINAL_PATH}" ] && [ -n "${REMOTE_INI_SOURCE_URL}" ]; then
    # This case means: download was attempted for a specific file, it failed, but a file already exists at target.
    # We prioritize the default config over a potentially stale/incorrect pre-existing file if download fails.
    # So, we'll proceed to check for default. If user explicitly wants to use a volume-mounted file
    # even on download failure, they should not set GITHUB_INI_FILENAME.
    #echo "警告：下载 ${GITHUB_INI_FILENAME} 失败，但目标路径 ${TARGET_CONFIG_FINAL_PATH} 已存在文件。"
    #echo "将优先尝试使用镜像内预置的默认配置文件（如果下载指定文件失败）。"
  elif [ -f "${TARGET_CONFIG_FINAL_PATH}" ] && [ -z "${REMOTE_INI_SOURCE_URL}" ]; then
    # This case means: GITHUB_INI_FILENAME was NOT set, so no download was attempted.
    # A file exists at the target path, likely from a volume or a previous run.
    # We should use this existing file.
    #echo "信息：未指定 GITHUB_INI_FILENAME 进行下载，且目标路径 ${TARGET_CONFIG_FINAL_PATH} 已存在文件。将使用此现有文件。"
    # frpc will use this existing TARGET_CONFIG_FINAL_PATH
  fi

  # If download failed OR no download was attempted AND the target file isn't already what we want,
  # try to use the default configuration.
  # This condition means:
  # 1. Download was attempted and failed (download_successful=false, REMOTE_INI_SOURCE_URL is not empty)
  # OR
  # 2. No download was attempted (REMOTE_INI_SOURCE_URL is empty) AND target file doesn't exist (covered by next check)
  # We need to ensure that if GITHUB_INI_FILENAME was not set, and a file exists at TARGET_CONFIG_FINAL_PATH, we don't overwrite it with default.
  # The logic is: if download was specified and failed, use default. If no download specified, use existing or default if no existing.

  should_use_default=false
  if [ -n "${REMOTE_INI_SOURCE_URL}" ] && [ "${download_successful}" = "false" ]; then
    # Download was specified and failed
    should_use_default=true
    #echo "由于远程文件下载失败，将尝试使用默认配置文件。"
  elif [ -z "${REMOTE_INI_SOURCE_URL}" ] && [ ! -f "${TARGET_CONFIG_FINAL_PATH}" ]; then
    # No download specified, and no file exists at target path
    should_use_default=true
    #echo "未指定远程文件下载，且目标路径不存在配置文件，将尝试使用默认配置文件。"
  fi

  if [ "${should_use_default}" = "true" ]; then
    if [ -f "${DEFAULT_CONFIG_SOURCE_PATH}" ]; then
      #echo "正在从 ${DEFAULT_CONFIG_SOURCE_PATH} 复制默认配置文件到 ${TARGET_CONFIG_FINAL_PATH}"
      if cp "${DEFAULT_CONFIG_SOURCE_PATH}" "${TARGET_CONFIG_FINAL_PATH}"; then
        #echo "已成功将默认配置文件复制到 ${TARGET_CONFIG_FINAL_PATH}"
        chmod 644 "${TARGET_CONFIG_FINAL_PATH}"
      else
        #echo "错误：复制默认配置文件从 ${DEFAULT_CONFIG_SOURCE_PATH} 到 ${TARGET_CONFIG_FINAL_PATH} 失败。"
        #echo "请检查路径和权限。正在退出。"
        exit 1
      fi
    else
      # This case should ideally not happen if Dockerfile is correct and default.frpc.ini was included
      echo "严重错误：尝试使用默认配置失败，镜像内预置的默认配置文件 ${DEFAULT_CONFIG_SOURCE_PATH} 未找到！"
      echo "请检查 Dockerfile 配置。正在退出。"
      exit 1
    fi
  elif [ "${download_successful}" = "false" ] && [ ! -f "${TARGET_CONFIG_FINAL_PATH}" ]; then
    # All attempts failed: download failed (or not specified) AND no default found AND no target file exists
     echo "严重错误：配置文件处理失败。无法下载，也找不到默认配置，目标路径 ${TARGET_CONFIG_FINAL_PATH} 也不存在文件。"
     exit 1
  fi
fi


if [ ! -f "${TARGET_CONFIG_FINAL_PATH}" ]; then
  echo "最终错误：配置文件 ${TARGET_CONFIG_FINAL_PATH} 未找到。frpc 无法启动。"
  exit 1
fi

#echo "frpc 将使用配置文件: ${TARGET_CONFIG_FINAL_PATH}"
#echo "正在使用参数 $@ 启动 frpc..."
exec ./frpc "$@"
