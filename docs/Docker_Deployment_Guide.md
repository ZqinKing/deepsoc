# DeepSOC Docker 完整部署指南

本文档详细说明如何通过 Docker 容器化方式完整部署 DeepSOC 及其依赖的 OctoMation (SOAR) 系统。

---

## 目录

- [架构总览](#架构总览)
- [前置要求](#前置要求)
- [第一部分：部署 OctoMation (SOAR)](#第一部分部署-octomation-soar)
- [第二部分：部署 DeepSOC](#第二部分部署-deepsoc)
- [第三部分：配置 SOAR 剧本](#第三部分配置-soar-剧本)
- [运维操作](#运维操作)
- [常见问题](#常见问题)

---

## 架构总览

完整的 DeepSOC 系统由以下组件构成：

```text
┌─────────────────────────────────────────────────────────┐
│                    DeepSOC 平台                          │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │        docker-compose (同一主机)                    │   │
│  │                                                    │   │
│  │  ┌─────────────┐  ┌──────────┐  ┌─────────────┐  │   │
│  │  │  DeepSOC App │  │  MySQL   │  │  RabbitMQ   │  │   │
│  │  │  :5007       │  │  :3306   │  │  :5672      │  │   │
│  │  │  (Flask +    │  │  (数据库) │  │  :15672     │  │   │
│  │  │   多Agent)   │  │          │  │  (消息队列)  │  │   │
│  │  └──────┬───────┘  └──────────┘  └─────────────┘  │   │
│  └─────────┼─────────────────────────────────────────┘   │
│            │ API 调用                                     │
└────────────┼─────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────┐
│   OctoMation (SOAR)     │  ← 独立部署（另一台服务器或同机不同端口）
│   :443 / :18443         │
│   (编排自动化平台)        │
└─────────────────────────┘
```

- DeepSOC App (:5007) + MySQL (:3306) + RabbitMQ (:5672/:15672) 通过 docker-compose 部署在同一主机
- OctoMation (SOAR) (:443/:18443) 独立部署在另一台服务器
- DeepSOC 通过 API 调用 OctoMation
- 部署顺序：先部署 OctoMation → 再部署 DeepSOC

## 前置要求

| 组件 | 要求 |
|------|------|
| DeepSOC 主机 | Docker 20.10+, Docker Compose 1.29+, 2核4GB+ |
| OctoMation 主机 | CentOS 7.8+/8.x 或 Rocky Linux 8/9, 4核8GB, 200GB硬盘, 静态IP |
| 大模型 API | 需提前申请 API Key |
| 网络 | 两台主机网络互通 |

## 第一部分：部署 OctoMation (SOAR)

### 1.1 服务器要求
| 项目 | 要求 |
|------|------|
| 操作系统 | CentOS 7.8+/8.x，Rocky Linux 8/9，openEuler 22 |
| CPU 架构 | X86_64 |
| CPU | 4核+ |
| 内存 | 8GB+ |
| 硬盘 | 200GB+（默认安装在 `/opt` 目录） |
| Swap | 不少于 8GB |
| 网络 | **必须使用静态 IP**，不可 DHCP |
| 防火墙 | `firewalld` 必须处于运行状态 |
| Docker | 20.10.12+ |
| Docker Compose | 1.29.2 |

### 1.2 环境检查
检查操作系统版本、磁盘空间、Swap、防火墙的命令：

```bash
# 查看操作系统版本
cat /etc/redhat-release
# 查看磁盘空间
df -h
# 检查 Swap 空间
free -h
# 检查防火墙状态
firewall-cmd --state
```

包含创建 Swap 的命令和启动防火墙的命令：
```bash
# 创建 Swap 分区
sudo dd if=/dev/zero of=/swapfile count=8192 bs=1MiB
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness = 1' >> /etc/sysctl.conf
sysctl -p

# 启动防火墙
systemctl start firewalld
systemctl enable firewalld
```

### 1.3 安装方式一：离线安装（推荐）
阿里云盘下载链接 + 执行安装脚本的命令：
> 下载地址：https://www.alipan.com/s/VJnrd92fhBh （提取码：11pt）

```bash
chmod +x octomation_community_docker_install_offline_<VERSION>.sh
./octomation_community_docker_install_offline_<VERSION>.sh
```

### 1.4 安装方式二：在线安装
包含：更换 YUM 源、安装 Docker、配置镜像加速、安装 Docker Compose、下载执行安装脚本的完整命令：
```bash
# 更换国内 YUM 源（推荐国内用户执行）
bash <(curl -sSL https://linuxmirrors.cn/main.sh)

# 安装工具
yum install yum-utils screen -y

# 卸载可能冲突的 podman
yum -y erase podman buildah

# 使用阿里云镜像安装 Docker
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
systemctl start docker
systemctl enable docker

# 配置镜像加速
cat > /etc/docker/daemon.json << 'MIRRORS'
{
  "registry-mirrors": [
    "https://docker.nju.edu.cn",
    "https://docker.mirrors.sjtug.sjtu.edu.cn",
    "https://docker.m.daocloud.io",
    "https://hub-mirror.c.163.com"
  ]
}
MIRRORS
systemctl restart docker

# 安装 Docker Compose
curl -L https://github.com/docker/compose/releases/download/1.29.2/docker-compose-Linux-x86_64 \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# 下载执行安装脚本
curl -o octomation_install.sh \
  https://ghproxy.com/https://raw.githubusercontent.com/flagify-com/OctoMation/main/octomation_community_docker_install_1.1.4.sh
chmod +x octomation_install.sh
./octomation_install.sh
```

### 1.5 首次登录与激活
1. **访问 Web 界面**：浏览器打开 `https://<OctoMation服务器IP>`
2. **登录系统**：默认管理员账号 `admin`，密码 `octomation`
3. **修改密码**：首次登录后系统会强制要求修改默认密码
4. **申请 License**：访问 [OctoMation 社区免费版 License 申请地址](https://flagify.com/e1598bd6f9a583) 申请免费 License
5. **导入 License**：登录后在右上角点击"导入 License"，上传获取到的授权文件

### 1.6 获取 API Token
进入设置→认证授权→Token管理，创建并复制 Token
同时记录 API 访问地址。注意：创建Token时，勾选的角色务必拥有剧本执行权限。

## 第二部分：部署 DeepSOC

### 2.1 获取代码
git clone 命令:
```bash
git clone https://github.com/flagify-com/deepsoc.git
cd deepsoc
```

### 2.2 配置环境变量
```bash
cp docker.env.example .env
```
列出必须修改的参数：
- `LLM_API_KEY`
- `SOAR_API_TOKEN`
- `SOAR_API_URL`
- `SECRET_KEY`
- `JWT_SECRET_KEY`

### 2.3 环境变量详解
按分组列出完整的环境变量表格：

#### 数据库配置
| 变量 | 默认值 | 说明 | 获取方式 |
|------|--------|------|----------|
| `DATABASE_URL` | `mysql+pymysql://deepsoc_user:deepsoc_password@mysql:3306/deepsoc` | 数据库连接字符串 | 保持默认（Docker 环境中 `mysql` 为服务名） |

#### 大模型配置
| 变量 | 默认值 | 说明 | 获取方式 |
|------|--------|------|----------|
| `LLM_API_KEY` | 无 | 大模型 API 密钥 | 从服务商控制台获取 |
| `LLM_MODEL` | `deepseek-v3` | 主模型 | 根据服务商填写 |
| `LLM_MODEL_LONG_TEXT` | `qwen-long` | 长文本模型 | 根据服务商填写 |
| `LLM_BASE_URL` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | API Base URL | 根据服务商填写 |
| `LLM_TEMPERATURE` | `0.6` | 采样温度 | 保持默认 |

#### 应用配置
| 变量 | 默认值 | 说明 | 获取方式 |
|------|--------|------|----------|
| `FLASK_APP` | `main.py` | Flask App | 保持默认 |
| `FLASK_ENV` | `development` | 运行环境 | 生产环境改为 `production` |
| `SECRET_KEY` | `deepsoc_secret_key_change_in_production` | Secret Key | 自行生成 |
| `LISTEN_HOST` | `0.0.0.0` | 监听主机 | 保持默认 |
| `LISTEN_PORT` | `5007` | 监听端口 | 保持默认 |
| `DEBUG` | `true` | 调试模式 | 生产环境改为 `false` |

#### JWT 配置
| 变量 | 默认值 | 说明 | 获取方式 |
|------|--------|------|----------|
| `JWT_SECRET_KEY` | `deepsoc_jwt_secret_key_change_in_production` | JWT Secret | 自行生成 |
| `JWT_ACCESS_TOKEN_EXPIRES` | `86400` | 过期时间(秒) | 保持默认 |

#### SOAR 配置
| 变量 | 默认值 | 说明 | 获取方式 |
|------|--------|------|----------|
| `SOAR_API_URL` | `https://hg-auto.wuzhi-ai.com:18443` | SOAR URL | OctoMation 服务器 IP:端口 |
| `SOAR_API_TOKEN` | 无 | API Token | OctoMation 后台创建 |
| `SOAR_API_TIMEOUT` | `30` | 超时时间 | 保持默认 |
| `SOAR_RETRY_COUNT` | `3` | 重试次数 | 保持默认 |
| `SOAR_RETRY_DELAY` | `5` | 重试延迟 | 保持默认 |
| `SOAR_VERIFY_SSL` | `False` | 验证 SSL | 保持默认 |

#### RabbitMQ 配置
| 变量 | 默认值 | 说明 | 获取方式 |
|------|--------|------|----------|
| `RABBITMQ_HOST` | `rabbitmq` | 主机名 | 保持默认 |
| `RABBITMQ_PORT` | `5672` | 端口 | 保持默认 |
| `RABBITMQ_USER` | `guest` | 用户名 | 建议生产环境修改 |
| `RABBITMQ_PASSWORD`| `guest` | 密码 | 建议生产环境修改 |
| `RABBITMQ_VHOST` | `/` | VHost | 保持默认 |

#### Expert 服务轮询间隔
| 变量 | 默认值 | 说明 |
|------|--------|------|
| `EXPERT_EXECUTION_SUMMARY_INTERVAL` | `10` | - |
| `EXPERT_COMMAND_STATUS_INTERVAL` | `10` | - |
| `EXPERT_TASK_STATUS_INTERVAL` | `15` | - |
| `EXPERT_EVENT_ROUND_STATUS_INTERVAL`| `20` | - |
| `EXPERT_EVENT_SUMMARY_INTERVAL` | `30` | - |
| `EXPERT_EVENT_NEXT_ROUND_INTERVAL` | `25` | - |

### 2.4 启动容器
```bash
docker-compose up -d --build
```
说明启动顺序：MySQL→RabbitMQ→DeepSOC
说明 docker-entrypoint.sh 的自动化行为: 启动入口脚本会自动等待 MySQL/RabbitMQ 就绪、自动检测并初始化数据库（如果为空，执行 `python main.py -init-with-demo`）、启动 Web 服务及所有 Agent。

### 2.5 验证部署
```bash
docker-compose ps
docker-compose logs -f deepsoc
```
访问 `http://<IP>:5007` 访问 DeepSOC。
访问 RabbitMQ 管理界面: `http://<IP>:15672` (默认 guest/guest)。

## 第三部分：配置 SOAR 剧本
请参考 `docs/soar-config-help.md`。
如何获取剧本 ID 和参数: 在 OctoMation 后台【安全剧本】列表点击进入剧本，地址栏可得剧本ID；点击【编辑参数】可得参数列表。
YAML 配置示例 (`prompts` 表的 `background_soar_playbooks`):
```yaml
playbooks:
  - id: 12321435630187042
    name: query_asset_info_by_ip
    desc: 根据IP地址查询资产信息
    logic: 根据给定的IP地址，查询资产信息
    params:
      - name: dst
        desc: 待查询的IP地址
        required: true
```

## 运维操作
常用 docker-compose 命令: `docker-compose up -d`, `docker-compose down`, `docker-compose restart deepsoc`
数据持久化说明（mysql_data volume）: MySQL 数据挂载在 `mysql_data` 卷，重新部署不会丢失。如需清空，执行 `docker-compose down -v`。
版本升级步骤: 
```bash
git pull origin main
docker-compose up -d --build deepsoc
```

## 常见问题
- Q1: DeepSOC 容器启动后退出 → 检查日志 `docker-compose logs deepsoc`，常见原因是缺 LLM_API_KEY 或网络不通。
- Q2: 无法连接 OctoMation → 检查 URL/Token/网络/SSL。
- Q3: OctoMation 安装防火墙问题 → 执行 `systemctl start firewalld`。
- Q4: OctoMation shakespeare-executor 启动慢 → 属于正常现象，如果报错，重新执行安装脚本。
- Q5: 生产环境安全加固建议 → 修改数据库密码、RabbitMQ密码、更换 SECRET_KEY、禁用 DEBUG、限制端口外部访问。

---
**相关文档链接**：[SOAR 配置指南](soar-config-help.md) | [系统架构](Architecture.md)  
**文档版本**：1.0  
**日期**：2026-02-24
