#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="cli-proxy"
CONTAINER_NAME="cli-proxy-api"
DEFAULT_INSTALL_DIR="/opt/${PROJECT_NAME}"
CLI_IMAGE="eceasy/cli-proxy-api:latest"
CADDY_IMAGE="caddy:2-alpine"
CADDY_CONTAINER_NAME="caddy"
CADDY_DIR="/opt/caddy"
DEFAULT_NETWORK="caddy-net"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }

die() {
  red "[ERROR] $*"
  exit 1
}

usage() {
  cat <<EOF
用法:
  bash deploy-cliproxy.sh              交互式部署或更新
  bash deploy-cliproxy.sh --upgrade    拉取最新镜像并平滑升级容器
  bash deploy-cliproxy.sh --uninstall  交互式完全卸载
  bash deploy-cliproxy.sh --help       显示帮助
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

random_hex() {
  local bytes="${1:-16}"
  if require_cmd openssl; then
    openssl rand -hex "$bytes"
    return
  fi
  if require_cmd od; then
    od -An -N "$bytes" -tx1 /dev/urandom | tr -d ' \n'
    printf '\n'
    return
  fi
  die "无法生成随机值：需要 openssl 或 od。"
}

prompt() {
  local label="$1"
  local default_value="$2"
  local value

  if [ -n "$default_value" ]; then
    read -r -p "${label} [${default_value}]: " value
    printf '%s' "${value:-$default_value}"
  else
    read -r -p "${label}: " value
    printf '%s' "$value"
  fi
}

prompt_yes_no() {
  local label="$1"
  local default_value="$2"
  local answer
  local suffix="[y/N]"

  if [ "$default_value" = "y" ]; then
    suffix="[Y/n]"
  fi

  read -r -p "${label} ${suffix}: " answer
  answer="${answer:-$default_value}"
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
    return
  fi
  if require_cmd docker-compose; then
    docker-compose "$@"
    return
  fi
  die "未找到 Docker Compose。"
}

validate_domain() {
  local domain="$1"
  [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  [[ "$domain" == *.* ]] || return 1
  [[ "$domain" != .* && "$domain" != *. ]] || return 1
}

install_docker_debian() {
  if [ "$(id -u)" -ne 0 ]; then
    die "安装 Docker 需要 root 权限。请用 root 运行脚本，或先手动安装 Docker。"
  fi

  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) die "自动安装 Docker 仅支持 Debian/Ubuntu，当前系统是 ${ID:-unknown}。" ;;
  esac

  info "安装 Docker Engine 和 Compose 插件..."
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  local codename
  codename="${VERSION_CODENAME:-}"
  [ -n "$codename" ] || die "无法识别系统版本代号。"

  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
    "$(dpkg --print-architecture)" "$ID" "$codename" \
    >/etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

check_docker() {
  if ! require_cmd docker; then
    if prompt_yes_no "未检测到 Docker，是否自动安装 Debian/Ubuntu 版 Docker" "y"; then
      install_docker_debian
    else
      die "缺少 Docker，无法继续。"
    fi
  fi
  compose_cmd version >/dev/null 2>&1 || die "未找到可用的 Docker Compose。"
}

ensure_caddy_and_network() {
  local network_name="$DEFAULT_NETWORK"

  if ! docker network inspect "$network_name" >/dev/null 2>&1; then
    info "创建共享 Docker 网络: ${network_name}..."
    docker network create "$network_name"
  fi

  mkdir -p "${CADDY_DIR}/conf.d"

  if [ ! -f "${CADDY_DIR}/Caddyfile" ]; then
    cat >"${CADDY_DIR}/Caddyfile" <<'EOF'
import /etc/caddy/conf.d/*.caddy
EOF
  fi

  if docker ps -a --filter "name=^/${CADDY_CONTAINER_NAME}$" --format '{{.Names}}' | grep -wq "${CADDY_CONTAINER_NAME}"; then
    if ! docker ps --filter "name=^/${CADDY_CONTAINER_NAME}$" --format '{{.Names}}' | grep -wq "${CADDY_CONTAINER_NAME}"; then
      info "启动已存在的 ${CADDY_CONTAINER_NAME} 容器..."
      docker start "${CADDY_CONTAINER_NAME}"
    fi

    local caddy_nets
    caddy_nets="$(docker inspect "${CADDY_CONTAINER_NAME}" --format '{{range $net, $v := .NetworkSettings.Networks}}{{$net}} {{end}}')"
    if [[ ! " ${caddy_nets} " =~ " ${network_name} " ]]; then
      info "将 ${CADDY_CONTAINER_NAME} 容器接入网络 ${network_name}..."
      docker network connect "$network_name" "${CADDY_CONTAINER_NAME}"
    fi
    reload_caddy
  else
    info "未检测到 ${CADDY_CONTAINER_NAME} 容器，正在自动拉取并启动..."
    docker run -d \
      --name "${CADDY_CONTAINER_NAME}" \
      --restart unless-stopped \
      --network "$network_name" \
      -p 80:80 \
      -p 443:443 \
      -v "${CADDY_DIR}/Caddyfile:/etc/caddy/Caddyfile:ro" \
      -v "${CADDY_DIR}/conf.d:/etc/caddy/conf.d:ro" \
      -v caddy_data:/data \
      -v caddy_config:/config \
      "$CADDY_IMAGE"
    green "${CADDY_CONTAINER_NAME} 网关已启动。"
  fi
}

detect_caddy_host_caddyfile() {
  if ! docker ps -a --filter "name=^/${CADDY_CONTAINER_NAME}$" --format '{{.Names}}' | grep -wq "${CADDY_CONTAINER_NAME}"; then
    printf '%s/Caddyfile' "$CADDY_DIR"
    return
  fi

  # 通过 inspect 查找容器内 /etc/caddy/Caddyfile 挂载对应的宿主机真实文件路径
  local host_path
  host_path="$(docker inspect "${CADDY_CONTAINER_NAME}" --format '{{range .Mounts}}{{if eq .Destination "/etc/caddy/Caddyfile"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || true)"
  if [ -n "$host_path" ] && [ -f "$host_path" ]; then
    printf '%s' "$host_path"
    return
  fi

  if [ -f "${CADDY_DIR}/Caddyfile" ]; then
    printf '%s/Caddyfile' "$CADDY_DIR"
    return
  fi

  printf '%s/Caddyfile' "$CADDY_DIR"
}

render_managed_routes() {
  local conf_d="${CADDY_DIR}/conf.d"
  local cp_domain=""
  local v2_domain=""
  local v2_ws_path=""

  if [ -f "${conf_d}/cliproxy.meta" ]; then
    # shellcheck disable=SC1090
    . "${conf_d}/cliproxy.meta"
    cp_domain="${CLIPROXY_DOMAIN:-}"
  fi

  if [ -f "${conf_d}/v2ray.meta" ]; then
    # shellcheck disable=SC1090
    . "${conf_d}/v2ray.meta"
    v2_domain="${V2RAY_DOMAIN:-}"
    v2_ws_path="${V2RAY_WS_PATH:-}"
  fi

  if [ -n "$cp_domain" ] && [ -n "$v2_domain" ] && [ "$cp_domain" = "$v2_domain" ]; then
    cat <<EOF
${cp_domain} {
	@v2ray_ws path ${v2_ws_path}
	reverse_proxy @v2ray_ws v2ray:10000

	reverse_proxy ${CONTAINER_NAME}:8317
}
EOF
  else
    if [ -n "$cp_domain" ]; then
      cat <<EOF
${cp_domain} {
	reverse_proxy ${CONTAINER_NAME}:8317
}
EOF
    fi

    if [ -n "$v2_domain" ]; then
      cat <<EOF
${v2_domain} {
	@v2ray_ws path ${v2_ws_path}
	reverse_proxy @v2ray_ws v2ray:10000
}
EOF
    fi
  fi
}

sync_caddy_routes() {
  local conf_d="${CADDY_DIR}/conf.d"
  mkdir -p "$conf_d"

  local active_caddyfile
  active_caddyfile="$(detect_caddy_host_caddyfile)"
  mkdir -p "$(dirname "$active_caddyfile")"
  [ -f "$active_caddyfile" ] || touch "$active_caddyfile"

  local generated_routes
  generated_routes="$(render_managed_routes)"

  # 如果宿主机的主配置文件是 /opt/caddy/Caddyfile，且容器包含 conf.d 挂载，则使用模块化维护
  if [ "$active_caddyfile" = "${CADDY_DIR}/Caddyfile" ]; then
    if ! grep -Fq "import /etc/caddy/conf.d/*.caddy" "$active_caddyfile"; then
      cat >"$active_caddyfile" <<'EOF'
import /etc/caddy/conf.d/*.caddy
EOF
    fi
    rm -f "${conf_d}"/*.caddy
    if [ -n "$generated_routes" ]; then
      printf '%s\n' "$generated_routes" >"${conf_d}/managed_services.caddy"
    fi
  else
    # 针对第三方或已有自定义 Caddyfile，采用无侵入的标记区块注入
    local start_marker="# >>> STACK-MANAGED-ROUTES-BEGIN >>>"
    local end_marker="# <<< STACK-MANAGED-ROUTES-END <<<"
    local tmp_file
    tmp_file="$(mktemp)"

    if grep -Fq "$start_marker" "$active_caddyfile"; then
      awk -v s="$start_marker" -v e="$end_marker" '
        $0 ~ s { skip=1; next }
        $0 ~ e { skip=0; next }
        !skip { print }
      ' "$active_caddyfile" >"$tmp_file"
    else
      cp "$active_caddyfile" "$tmp_file"
    fi

    if [ -n "$generated_routes" ]; then
      {
        printf '\n%s\n' "$start_marker"
        printf '%s\n' "$generated_routes"
        printf '%s\n' "$end_marker"
      } >>"$tmp_file"
    fi

    mv "$tmp_file" "$active_caddyfile"
  fi
}

reload_caddy() {
  if docker ps --filter "name=^/${CADDY_CONTAINER_NAME}$" --format '{{.Names}}' | grep -wq "${CADDY_CONTAINER_NAME}"; then
    info "重载 ${CADDY_CONTAINER_NAME} 网关配置..."
    if ! docker exec "${CADDY_CONTAINER_NAME}" caddy reload --config /etc/caddy/Caddyfile 2>/dev/null; then
      yellow "Caddy 热重载未立即生效，尝试重启容器..."
      docker restart "${CADDY_CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi
  fi
}

write_env_file() {
  local file="$1"
  cat >"$file" <<EOF
DOMAIN=${DOMAIN}
INSTALL_DIR=${INSTALL_DIR}
MANAGEMENT_KEY=${MANAGEMENT_KEY}
API_KEY=${API_KEY}
DOCKER_NETWORK=${DEFAULT_NETWORK}
EOF
  chmod 600 "$file"
}

write_compose_file() {
  local file="$1"
  cat >"$file" <<EOF
services:
  ${CONTAINER_NAME}:
    image: ${CLI_IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    volumes:
      - ./cliproxyapi/config.yaml:/CLIProxyAPI/config.yaml
      - ./cliproxyapi/auth:/root/.cli-proxy-api
      - ./cliproxyapi/static:/CLIProxyAPI/static
    networks:
      - ${DEFAULT_NETWORK}

networks:
  ${DEFAULT_NETWORK}:
    external: true
EOF
}

write_cliproxy_config() {
  local file="$1"
  cat >"$file" <<EOF
host: ""
port: 8317

tls:
  enable: false
  cert: ""
  key: ""

remote-management:
  allow-remote: true
  secret-key: "${MANAGEMENT_KEY}"
  disable-control-panel: false
  panel-github-repository: "https://github.com/router-for-me/Cli-Proxy-API-Management-Center"

auth-dir: "~/.cli-proxy-api"
api-keys:
  - "${API_KEY}"

debug: false
commercial-mode: false
logging-to-file: true
logs-max-total-size-mb: 100
usage-statistics-enabled: false
request-retry: 3
max-retry-interval: 30
ws-auth: false

quota-exceeded:
  switch-project: true
  switch-preview-model: true
  antigravity-credits: true

routing:
  strategy: "round-robin"
  session-affinity: false
  session-affinity-ttl: "1h"

streaming:
  keepalive-seconds: 15
  bootstrap-retries: 1
EOF
}

print_summary() {
  cat <<EOF

==================================================
CLI-Proxy-API 部署信息
==================================================
安装目录:      ${INSTALL_DIR}
Web 管理页:    https://${DOMAIN}/management.html
API Base URL:  https://${DOMAIN}/v1
Web 管理密钥:  ${MANAGEMENT_KEY}
API Key:       ${API_KEY}
(API Key 为客户端连接平台的验证密钥)

常用命令
--------
查看日志:
  cd ${INSTALL_DIR} && docker compose logs -f

重启服务:
  cd ${INSTALL_DIR} && docker compose restart

停止服务:
  cd ${INSTALL_DIR} && docker compose down

升级容器:
  bash deploy-cliproxy.sh --upgrade

EOF
}

upgrade_service() {
  local install_dir="$1"

  cat <<'EOF'
CLI-Proxy-API 平滑升级
======================
保留所有已有配置、挂载数据、认证 Token 与密钥，拉取最新镜像并重新启动容器。

EOF

  if [ -z "$install_dir" ]; then
    local detected_dir
    detected_dir="$(detect_installed_dir)"
    install_dir="$(prompt "检测到安装目录，回车确认或输入其他路径" "$detected_dir")"
  fi

  [ -n "$install_dir" ] || die "安装目录不能为空。"
  [ -f "$install_dir/docker-compose.yml" ] || die "未在 $install_dir 找到 docker-compose.yml，请先部署。"

  check_docker
  ensure_caddy_and_network

  info "拉取最新镜像: ${CLI_IMAGE}..."
  (cd "$install_dir" && compose_cmd pull)

  info "重新创建并启动 ${CONTAINER_NAME} 容器..."
  (cd "$install_dir" && compose_cmd up -d --force-recreate)

  reload_caddy

  green "CLI-Proxy-API 升级完成！容器已运行最新镜像并保留全部配置与认证数据。"
}

detect_installed_dir() {
  # 1. 尝试从运行中的容器挂载获取宿主机安装目录
  if docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format '{{.Names}}' | grep -wq "${CONTAINER_NAME}"; then
    local host_config
    host_config="$(docker inspect "${CONTAINER_NAME}" --format '{{range .Mounts}}{{if eq .Destination "/CLIProxyAPI/config.yaml"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || true)"
    if [ -n "$host_config" ]; then
      # host_config 通常是 /opt/cli-proxy/cliproxyapi/config.yaml
      local candidate
      candidate="$(dirname "$(dirname "$host_config")")"
      if [ -d "$candidate" ]; then
        printf '%s' "$candidate"
        return
      fi
    fi
  fi

  # 2. 检查默认目录是否存在
  if [ -d "$DEFAULT_INSTALL_DIR" ]; then
    printf '%s' "$DEFAULT_INSTALL_DIR"
    return
  fi

  printf '%s' "$DEFAULT_INSTALL_DIR"
}

uninstall_service() {
  cat <<'EOF'
CLI-Proxy-API 卸载
==================
将停止并删除本服务容器、网络配置与路由，并可选择清理安装目录。

EOF

  local detected_dir
  detected_dir="$(detect_installed_dir)"

  # 如果检测到的目录存在，或者允许用户确认/修改
  if [ -d "$detected_dir" ]; then
    INSTALL_DIR="$(prompt "检测到安装目录，回车确认或输入其他路径" "$detected_dir")"
  else
    INSTALL_DIR="$(prompt "请输入要卸载的安装目录，留空使用默认值" "$DEFAULT_INSTALL_DIR")"
  fi

  [ -n "$INSTALL_DIR" ] || die "安装目录不能为空。"

  if [ ! -d "$INSTALL_DIR" ] && ! docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format '{{.Names}}' | grep -wq "${CONTAINER_NAME}"; then
    die "未找到安装目录 ($INSTALL_DIR) 且未检测到运行中的容器。"
  fi

  if ! prompt_yes_no "确认卸载 ${INSTALL_DIR} 及其容器服务" "y"; then
    die "用户已取消卸载。"
  fi

  if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    if require_cmd docker; then
      info "停止并删除容器与相关卷..."
      (cd "$INSTALL_DIR" && compose_cmd down --volumes --remove-orphans) || true
    else
      yellow "未检测到 Docker，跳过容器清理。"
    fi
  fi

  if [ -f "${CADDY_DIR}/conf.d/cliproxy.meta" ]; then
    info "清理 Caddy 中的反代路由配置..."
    rm -f "${CADDY_DIR}/conf.d/cliproxy.meta"
    sync_caddy_routes
    reload_caddy
  fi

  if require_cmd docker && prompt_yes_no "是否同时删除 CLI-Proxy-API 镜像 (${CLI_IMAGE})" "n"; then
    docker image rm "$CLI_IMAGE" >/dev/null 2>&1 || true
  fi

  if prompt_yes_no "是否删除安装目录及其中的配置、密钥和认证文件" "y"; then
    rm -rf -- "$INSTALL_DIR"
    green "安装目录已删除：$INSTALL_DIR"
  else
    yellow "已保留安装目录：$INSTALL_DIR"
  fi

  if require_cmd docker && [ -f "${CADDY_DIR}/conf.d/v2ray.meta" ]; then
    info "检测到 V2Ray 服务仍在运行，已保留 Caddy 网关与共享网络。"
  elif require_cmd docker && docker ps -a --filter "name=^/${CADDY_CONTAINER_NAME}$" --format '{{.Names}}' | grep -wq "${CADDY_CONTAINER_NAME}"; then
    if prompt_yes_no "未检测到其他服务使用 Caddy，是否同时停止并删除 Caddy 网关及共享网络" "n"; then
      info "清理 Caddy 网关..."
      docker stop "${CADDY_CONTAINER_NAME}" >/dev/null 2>&1 || true
      docker rm "${CADDY_CONTAINER_NAME}" >/dev/null 2>&1 || true
      docker network rm "$DEFAULT_NETWORK" >/dev/null 2>&1 || true
      rm -rf -- "$CADDY_DIR"
      green "Caddy 网关与共享网络已清理。"
    fi
  fi

  green "CLI-Proxy-API 卸载流程完成。"
}

main() {
  cat <<'EOF'
CLI-Proxy-API 独立部署向导
==========================
独立部署模型代理平台，自动检测并接入 Caddy 网关。

EOF

  DOMAIN="$(prompt "请输入域名，例如 api.example.com" "")"
  validate_domain "$DOMAIN" || die "域名格式不正确。"

  INSTALL_DIR="$(prompt "请输入安装目录，留空使用默认值" "$DEFAULT_INSTALL_DIR")"
  [ -n "$INSTALL_DIR" ] || die "安装目录不能为空。"

  MANAGEMENT_KEY="$(prompt "请输入 Web 管理密钥，留空使用随机值" "")"
  MANAGEMENT_KEY="${MANAGEMENT_KEY:-mgmt_$(random_hex 24)}"

  API_KEY="$(prompt "请输入 API Key（客户端连接平台的验证密钥，留空使用随机值）" "")"
  API_KEY="${API_KEY:-cpa_$(random_hex 24)}"

  check_docker

  if [ -e "$INSTALL_DIR" ] && [ -n "$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
    if ! prompt_yes_no "安装目录非空，是否覆盖同名配置文件并继续" "n"; then
      die "用户取消。"
    fi
  fi

  mkdir -p "${CADDY_DIR}/conf.d"
  cat >"${CADDY_DIR}/conf.d/cliproxy.meta" <<EOF
CLIPROXY_DOMAIN=${DOMAIN}
EOF
  sync_caddy_routes

  ensure_caddy_and_network

  mkdir -p \
    "$INSTALL_DIR/cliproxyapi/auth" \
    "$INSTALL_DIR/cliproxyapi/static"

  write_env_file "$INSTALL_DIR/.env"
  write_compose_file "$INSTALL_DIR/docker-compose.yml"
  write_cliproxy_config "$INSTALL_DIR/cliproxyapi/config.yaml"
  chmod 600 "$INSTALL_DIR/cliproxyapi/config.yaml"

  if prompt_yes_no "是否现在拉取镜像并启动服务" "y"; then
    info "启动服务..."
    (cd "$INSTALL_DIR" && compose_cmd pull && compose_cmd up -d)
    green "CLI-Proxy-API 服务已启动。"
  else
    yellow "已生成配置，但尚未启动服务。"
  fi

  print_summary
}

case "${1:-}" in
  --upgrade|-u)
    upgrade_service "${2:-}"
    ;;
  --uninstall)
    uninstall_service
    ;;
  --help|-h)
    usage
    ;;
  "")
    main "$@"
    ;;
  *)
    usage
    die "未知参数：$1"
    ;;
esac
