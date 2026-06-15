#!/bin/bash
# =============================================================================
# 北京萨博安通官网 — ECS 服务器初始化脚本
# 适用: Alibaba Cloud Linux 3.2104 LTS
# 执行方式: ssh root@<ECS_IP> 'bash -s' < setup-server.sh
# =============================================================================
set -euo pipefail

APP_NAME="bjsbat"
DEPLOY_USER="deploy"
WEB_ROOT="/usr/share/nginx/html"

echo "=== [1/6] 安装 Nginx ==="
dnf install -y nginx rsync

echo "=== [2/6] 创建部署用户 ==="
if ! id "${DEPLOY_USER}" &>/dev/null; then
    useradd -m -s /bin/bash "${DEPLOY_USER}"
    echo "用户 ${DEPLOY_USER} 已创建"
else
    echo "用户 ${DEPLOY_USER} 已存在，跳过"
fi

echo "=== [3/6] 设置网站目录权限 ==="
mkdir -p "${WEB_ROOT}"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${WEB_ROOT}"
chmod 755 "${WEB_ROOT}"

# 创建测试页面（部署后会被覆盖）
cat > "${WEB_ROOT}/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="UTF-8"><title>萨博安通 - 部署就绪</title></head>
<body>
<h1>🟢 Nginx is running</h1>
<p>网站文件将通过 GitHub Actions 自动部署到此目录。</p>
</body>
</html>
HTML

echo "=== [4/6] 配置 Nginx ==="
# 备份默认配置
if [ -f /etc/nginx/nginx.conf ]; then
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
fi

# 写入站点配置
cat > /etc/nginx/conf.d/bjsbat.conf <<'NGINX'
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    # 安全头
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Content-Security-Policy "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; script-src 'self'" always;

    # 静态资源
    location / {
        try_files $uri $uri/ =404;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
    }

    # robots.txt / sitemap.xml 不缓存
    location = /robots.txt  { expires -1; }
    location = /sitemap.xml  { expires -1; }

    # 禁止访问隐藏文件
    location ~ /\. { return 404; }
}
NGINX

echo "=== [5/6] 启动 Nginx ==="
systemctl enable nginx
systemctl reload nginx || systemctl start nginx
systemctl status nginx --no-pager

echo "=== [6/6] 验证 ==="
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost/
echo ""
echo "=============================================="
echo "  ✅ 初始化完成"
echo "  访问 http://<ECS公网IP> 应显示部署就绪页面"
echo "=============================================="
