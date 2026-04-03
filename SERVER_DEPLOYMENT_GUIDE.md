# Rescue Mesh 云服务器部署完整指南

本指南将带你从零开始，在腾讯云上购买服务器并部署救援指挥系统后端服务。

---

## 📦 第一阶段：购买和初始化服务器

### 1. 购买云服务器

**访问腾讯云**：https://cloud.tencent.com/product/cvm

**选择配置**：
- **镜像**：Ubuntu 22.04 LTS
- **CPU**：2核
- **内存**：4GB
- **硬盘**：50GB SSD
- **带宽**：3 Mbps（最低 1Mbps，建议 3M 起）
- **地域**：选离你用户近的（如华南→广州，华东→上海）

**安全组规则（防火墙）**：
购买时或购买后，在"安全组"添加入站规则：

| 端口范围 | 协议 | 授权对象 | 说明 |
|---------|------|----------|------|
| 22 | TCP | 0.0.0.0/0 | SSH 远程连接 |
| 3000 | TCP | 0.0.0.0/0 | 后端 API 服务 |
| 27017 | TCP | 127.0.0.1/0 | MongoDB（仅本地访问，更安全） |

**设置登录密码**：记住用户名（通常是 `ubuntu` 或`root`）和你设置的密码。

**记录服务器信息**：
- 公网 IP：如 `123.45.67.89`
- 用户名：`ubuntu`
- 密码：你设置的密码

---

## 🔧 第二阶段：连接服务器并安装环境

### 2. SSH 连接到服务器

#### 方法 A：使用 PowerShell（Windows 自带）

打开 PowerShell，执行：

```powershell
ssh ubuntu@你的公网IP
```

首次连接会提示：
```
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```
输入 `yes`，然后输入密码（输入时不显示，正常）。

#### 方法 B：使用 VS Code Remote-SSH（推荐）

1. 在 VS Code 中安装 "Remote - SSH" 扩展
2. 按 `Ctrl+Shift+P` → 输入 "Remote-SSH: Connect to Host"
3. 输入 `ssh ubuntu@你的公网IP`
4. 输入密码
5. 连接成功后，可以直接在 VS Code 中编辑服务器文件

---

### 3. 更新系统软件包

连接成功后，在终端执行：

```bash
sudo apt update && sudo apt upgrade -y
```

等待更新完成。

---

### 4. 安装 Node.js 20.x

```bash
# 下载并运行 NodeSource 安装脚本
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -

# 安装 Node.js
sudo apt install -y nodejs

# 验证安装
node -v
npm -v
```

应该看到 `v20.x.x` 和对应的 npm 版本号。

---

### 5. 安装 PM2（进程管理器）

```bash
sudo npm install -g pm2

# 验证
pm2 -v
```

PM2 用于让 Node.js 应用在后台持续运行，即使关闭 SSH 也不会停止。

---

### 6. 安装 MongoDB 数据库

```bash
# 导入 MongoDB GPG 密钥
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-archive-keyring.gpg

# 添加 MongoDB 源
echo "deb [ signed-by=/usr/share/keyrings/mongodb-archive-keyring.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

# 更新并安装
sudo apt update
sudo apt install -y mongodb-org

# 启动 MongoDB 服务
sudo systemctl start mongod
sudo systemctl enable mongod

# 检查状态（应该是 active (running)）
sudo systemctl status mongod
```

按 `q` 退出状态查看。

MongoDB 已启动并设置为开机自启。

---

## 📤 第三阶段：上传并部署后端代码

### 7. 在服务器上创建项目目录

```bash
mkdir -p /home/ubuntu/rescue-mesh-server
cd /home/ubuntu/rescue-mesh-server
```

---

### 8. 上传后端代码到服务器

#### 方法 A：使用 WinSCP（图形化，推荐新手）

1. 下载 WinSCP：https://winscp.net
2. 安装并打开 WinSCP
3. 新建会话：
   - 主机名：你的公网 IP（如 `123.45.67.89`）
   - 用户名：`ubuntu`
   - 密码：你的密码
4. 点击"登录"
5. 登录后界面：
   - 左边是本地文件（你的电脑）
   - 右边是服务器文件
6. 在右边导航到 `/home/ubuntu/rescue-mesh-server/`
7. 在左边找到本地的 `e:\MyProject\rescue_mesh_app\server\` 文件夹
8. 选中所有文件，拖到右边的 `/home/ubuntu/rescue-mesh-server/`

#### 方法 B：使用 SCP 命令（在本地 PowerShell 执行）

在你的电脑上打开新的 PowerShell窗口（不是 SSH 里的）：

```powershell
# 切换到 server 目录
cd e:\MyProject\rescue_mesh_app\server

# 递归复制所有文件到服务器（替换成你的公网 IP）
scp -r * ubuntu@你的公网IP:/home/ubuntu/rescue-mesh-server/
```

输入密码后开始传输，等待完成。

---

### 9. 安装后端依赖

回到 SSH 会话（或在 WinSCP 中打开终端），在项目目录下：

```bash
cd /home/ubuntu/rescue-mesh-server

# 安装生产环境依赖
npm install --production
```

这会安装 `package.json` 中定义的所有依赖包。

---

### 10. 配置环境变量

```bash
# 查看示例配置内容
cat .env.example

# 复制并编辑实际配置
cp .env.example .env
nano .env
```

在 nano 编辑器中修改以下内容（用键盘方向键移动光标）：

```env
PORT=3000
MONGODB_URI=mongodb://localhost:27017/rescue-mesh
NODE_ENV=production
```

修改完成后：
- 按 `Ctrl+O` 保存
- 按 `Enter` 确认文件名
- 按 `Ctrl+X` 退出编辑器

---

### 11. 用 PM2 启动后端服务

```bash
# 启动应用，命名为 "rescue-mesh-api"
pm2 start npm --name "rescue-mesh-api" -- start

# 设置开机自启动（会输出一行命令，复制并执行它）
pm2 startup

# 保存当前进程列表（这样重启后会自动恢复）
pm2 save

# 查看运行状态
pm2 status

# 查看实时日志
pm2 logs rescue-mesh-api
```

按 `Ctrl+C` 退出日志查看。

如果看到 `online` 状态，说明服务已成功启动！

---

## 🔓 第四阶段：验证服务可用

### 12. 测试 API 是否正常运行

#### 方法 A：在浏览器访问

打开浏览器，访问：
```
http://你的公网IP:3000/api/sos/sync
```

如果能访问（即使是返回错误信息），说明服务通了。

#### 方法 B：用 curl 命令测试

在 SSH 终端执行：

```bash
curl http://localhost:3000/api/sos/sync
```

如果看到 JSON 响应或错误信息（不是"Connection refused"），说明服务已启动！

---

## 📱 第五阶段：修改 App 和 Dashboard 配置

### 13. 修改 Flutter App 配置

打开文件：`e:\MyProject\rescue_mesh_app\lib\services\network_sync_service.dart`

找到第 31 行左右：

```dart
_endpoint = Uri.parse('http://192.168.36.155:3000/api/sos/sync')
```

改成你的服务器公网 IP：

```dart
_endpoint = Uri.parse('http://你的公网IP:3000/api/sos/sync')
```

例如，如果你的公网 IP 是 `123.45.67.89`：

```dart
_endpoint = Uri.parse('http://123.45.67.89:3000/api/sos/sync')
```

保存文件。

---

### 14. 修改 Dashboard 配置

打开文件：`e:\MyProject\rescue_mesh_app\dashboard\src\composables\useSocket.js`

找到第 4-5 行：

```javascript
const SOCKET_URL = import.meta.env.VITE_SOCKET_URL || 'http://192.168.36.155:3000'
const API_BASE   = import.meta.env.VITE_API_BASE   || 'http://192.168.36.155:3000'
```

改成你的服务器公网 IP：

```javascript
const SOCKET_URL = import.meta.env.VITE_SOCKET_URL || 'http://你的公网IP:3000'
const API_BASE   = import.meta.env.VITE_API_BASE   || 'http://你的公网IP:3000'
```

或者，在 `dashboard/` 目录下创建 `.env.local` 文件：

```env
VITE_SOCKET_URL=http://你的公网IP:3000
VITE_API_BASE=http://你的公网IP:3000
```

保存文件。

---

### 15. 重新编译项目

#### Flutter App

在项目根目录执行：

```bash
flutter clean
flutter build apk --release
```

生成的 APK 文件在：`build/app/outputs/flutter-apk/app-release.apk`

或者直接在真机上调试：

```bash
flutter run
```

#### Dashboard

在 `dashboard/` 目录下执行：

```bash
cd dashboard
npm install
npm run build
```

构建产物在 `dashboard/dist/` 目录。

---

## ✅ 第六阶段：最终测试

### 16. 完整功能测试

1. **确保手机能上网**（不需要和服务器在同一 WiFi，4G/5G 即可）
2. 安装或运行修改后的 App
3. 在 App 中触发 SOS 消息发送
4. 观察是否能成功同步

#### 在服务器上查看同步日志

在 SSH 终端执行：

```bash
pm2 logs rescue-mesh-api --lines 50
```

你应该能看到类似这样的日志：
```
POST /api/sos/sync 200 - - ms
```

这表示数据已成功同步到服务器！

---

## 🛠️ 常用运维命令速查表

### 查看服务状态

```bash
# 查看所有 PM2 管理的服务
pm2 status

# 查看某个服务的详细信息
pm2 show rescue-mesh-api

# 查看 CPU 和内存占用
pm2 monit
```

### 查看日志

```bash
# 所有服务的日志
pm2 logs

# 只看后端服务的日志
pm2 logs rescue-mesh-api

# 查看最近 100 行日志
pm2 logs --lines 100

# 清空日志
pm2 flush
```

### 重启/停止服务

```bash
# 重启后端服务
pm2 restart rescue-mesh-api

# 重启所有服务
pm2 restart all

# 停止后端服务
pm2 stop rescue-mesh-api

# 停止所有服务
pm2 stop all

# 删除服务（从 PM2 列表中移除）
pm2 delete rescue-mesh-api
```

### MongoDB 数据库管理

```bash
# 查看数据库状态
sudo systemctl status mongod

# 重启数据库
sudo systemctl restart mongod

# 停止数据库
sudo systemctl stop mongod

# 启动数据库
sudo systemctl start mongod

# 查看数据库日志
sudo journalctl -u mongod -f
```

### 系统资源监控

```bash
# 查看磁盘使用情况
df -h

# 查看各文件夹大小
du -sh /home/ubuntu/*

# 查看内存使用
free -h

# 查看 CPU 负载
top
```

### 其他实用命令

```bash
# 查看当前目录
pwd

# 列出文件
ls -la

# 切换目录
cd /path/to/dir

# 查看文件大小
ls -lh filename

# 编辑文件
nano filename

# 查看文件内容
cat filename

# 尾随查看日志文件
tail -f /var/log/syslog
```

---

## 🎉 部署完成！

恭喜！现在你的救援指挥系统已经成功部署到云服务器了！

### 现在的状态：

✅ **后端服务**：运行在服务器的 3000 端口  
✅ **数据库**：MongoDB 正在运行，存储所有 SOS 数据  
✅ **App 配置**：已指向云服务器公网 IP  
✅ **Dashboard 配置**：已指向云服务器公网 IP  

### 接下来可以做什么：

1. **任何地方都能访问**：手机在有网络的地方（4G/5G/WiFi）都能同步数据
2. **实时监控**：通过 Dashboard 查看救援人员位置和状态
3. **数据持久化**：所有数据保存在 MongoDB 中，不会丢失
4. **自动重启**：服务器重启后，PM2 会自动启动服务

---

## ❓ 常见问题解答

### Q1: 连接超时怎么办？

**A**: 检查以下几点：
1. 确认服务器公网 IP 是否正确
2. 检查腾讯云安全组是否放行了 3000 端口
3. 在服务器上执行 `sudo ufw status` 查看防火墙状态
4. 临时关闭防火墙测试：`sudo ufw disable`

### Q2: PM2 显示 errored 状态怎么办？

**A**: 查看详细错误：
```bash
pm2 logs rescue-mesh-api --err
```

常见原因：
- 端口被占用：修改 `.env` 中的 PORT
- MongoDB未启动：`sudo systemctl start mongod`
- 依赖缺失：`npm install --production`

### Q3: 如何升级后端代码？

**A**: 
1. 重新上传修改后的代码到服务器（覆盖原文件）
2. 重启服务：`pm2 restart rescue-mesh-api`
3. 查看日志确认：`pm2 logs rescue-mesh-api`

### Q4: 服务器重启后需要重新配置吗？

**A**: 不需要！因为我们已经设置了：
- `pm2 startup`：PM2 开机自启
- `pm2 save`：保存进程列表
- `systemctl enable mongod`：MongoDB 开机自启

重启后会自动恢复所有服务。

### Q5: 如何备份数据？

**A**: 导出 MongoDB 数据：
```bash
mongodump --out /backup/rescue-mesh-$(date +%Y%m%d)
```

下载到本地：
```bash
scp -r ubuntu@你的公网IP:/backup/rescue-mesh-* ./local-backup/
```

### Q6: 需要 HTTPS 加密怎么办？

**A**: 
1. 购买域名并备案
2. 将域名解析到你的服务器 IP
3. 使用 Certbot 申请免费 SSL 证书：
   ```bash
   sudo apt install certbot python3-certbot-nginx
   sudo certbot --nginx -d yourdomain.com
   ```
4. 配置 Nginx反向代理（需要额外配置）

---

## 📞 技术支持

如果在部署过程中遇到任何问题：
1. 截图或复制完整的错误信息
2. 说明你在哪一步遇到的问题
3. 提供相关日志输出

这样可以更快地定位和解决问题！

---

**祝你部署顺利！** 🚀
