# AWS + Cloudflare deployment guide

This repository currently contains only a minimal scaffold, so the instructions below provide a production-ready baseline you can apply as your application code is added.

## 1) Codebase review (current state)

- The repo has only a minimal `README.md` and no runnable application yet.
- Before first deploy, add your app code (for example, Node/Next.js, Python, or containerized service) and make sure it listens on a server port (commonly `3000`).
- The CI/CD workflow in this repo is prepared for an EC2 + Docker Compose deployment pattern.

## 2) Target architecture (recommended)

- **AWS EC2** hosts your application.
- **Nginx** on EC2 terminates HTTPS (using Let's Encrypt) and reverse proxies to your app.
- **Cloudflare** manages DNS for `handofai.work` and `www.handofai.work`.
- **GitHub Actions** deploys automatically to EC2 when code is pushed to `main`.
- If your app uses agent tools, run a dedicated **sandbox service** (container or VM) and pass its reachable URL/IP to the app.

## 3) Manual AWS setup

### 3.1 Launch EC2

1. Go to **EC2 > Instances > Launch instance**.
2. Name: `handofai-prod-web`.
3. AMI: Ubuntu 22.04 LTS.
4. Instance type: `t3.small` (or `t3.micro` for lower traffic).
5. Key pair: create or select your existing key.
6. Network/security group inbound rules:
   - SSH `22` from your IP only.
   - HTTP `80` from `0.0.0.0/0`.
   - HTTPS `443` from `0.0.0.0/0`.
7. Launch instance.

### 3.2 Attach Elastic IP

1. Go to **EC2 > Elastic IPs** and allocate a new Elastic IP.
2. Associate it with `handofai-prod-web`.
3. Keep this IP; you will use it in Cloudflare DNS.

### 3.3 Prepare server

SSH in:

```bash
ssh -i /path/to/your-key.pem ubuntu@<EC2_PUBLIC_IP>
```

Install dependencies:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y nginx certbot python3-certbot-nginx git docker.io docker-compose-plugin ufw
sudo systemctl enable --now nginx docker
sudo usermod -aG docker ubuntu
```

Configure firewall:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
```

### 3.4 Clone repo on EC2

```bash
sudo mkdir -p /var/www/amazon_hackhathon
sudo chown -R ubuntu:ubuntu /var/www/amazon_hackhathon
git clone <YOUR_GITHUB_REPO_URL> /var/www/amazon_hackhathon
```

> If the repo is private, configure SSH deploy keys on the instance first.

### 3.5 Configure Nginx

Create site config:

```bash
sudo tee /etc/nginx/sites-available/handofai.work >/dev/null <<'NGINX'
server {
    listen 80;
    server_name handofai.work www.handofai.work;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
```

Enable config:

```bash
sudo ln -sf /etc/nginx/sites-available/handofai.work /etc/nginx/sites-enabled/handofai.work
sudo nginx -t
sudo systemctl reload nginx
```

### 3.6 Issue SSL certificate

Run after DNS is pointed to EC2:

```bash
sudo certbot --nginx -d handofai.work -d www.handofai.work
```

Choose HTTP->HTTPS redirect when prompted.

## 4) Manual Cloudflare setup

In your Cloudflare DNS for `handofai.work`, add or update:

1. **A record**
   - Name: `@`
   - IPv4: `<EC2_ELASTIC_IP>`
   - Proxy status: **Proxied** (orange cloud)
2. **CNAME record**
   - Name: `www`
   - Target: `handofai.work`
   - Proxy status: **Proxied**

SSL/TLS settings in Cloudflare:

- Set **SSL/TLS mode** to **Full (strict)**.
- Enable **Always Use HTTPS**.

## 5) GitHub Actions automatic deploy

This repo includes `.github/workflows/deploy.yml`.

When you push to `main`, GitHub Actions will:

1. Connect to EC2 over SSH.
2. Pull latest `main`.
3. Validate Docker Compose config.
4. Build/start containers with Docker Compose.
5. Reload Nginx.

### 5.1 Required GitHub secrets

Go to **GitHub repo > Settings > Secrets and variables > Actions** and add:

- `EC2_HOST` = public IP or DNS of EC2.
- `EC2_USER` = `ubuntu`.
- `EC2_SSH_KEY` = full private key content used for SSH.
- `EC2_PORT` = `22`.
- `DEPLOY_PATH` = `/var/www/amazon_hackhathon`.

## 6) App runtime expectation for deployment

For the workflow to succeed, your repository should include a working `docker-compose.yml` that starts your app on port `3000`.

If your app supports agent tool execution, include a sandbox service and pass a reachable URL to the app.

Example:

```yaml
services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      # Use the variable name your app expects, e.g. SANDBOX_URL/AGENT_SANDBOX_URL
      SANDBOX_URL: "http://sandbox:8080"
    depends_on:
      - sandbox
    restart: always

  sandbox:
    image: ghcr.io/your-org/your-sandbox:latest
    expose:
      - "8080"
    restart: always
```

## 7) Fix for error: `Agent Error - Failed to execute command: bad request: no IP address found. Is the Sandbox started?`

This means your app can answer chat text, but the **agent execution backend** cannot locate a running sandbox endpoint.

### 7.1 Verify sandbox container is running on EC2

```bash
cd /var/www/amazon_hackhathon
docker compose ps
docker compose logs --tail=100 sandbox
```

If `sandbox` is missing or exited, your app cannot run tools.

### 7.2 Verify app has correct sandbox endpoint config

```bash
docker compose exec app env | grep -E 'SANDBOX|AGENT'
```

- Ensure the env var your app uses points to a reachable host/IP.
- Inside Docker Compose, prefer service DNS (`http://sandbox:8080`) instead of public IP.

### 7.3 Confirm network reachability from app to sandbox

```bash
docker compose exec app sh -lc 'getent hosts sandbox || true'
docker compose exec app sh -lc 'curl -sS http://sandbox:8080/health || true'
```

If host resolution or health request fails, fix Compose networking/service names.

### 7.4 Redeploy after env/config fix

```bash
docker compose down
docker compose up -d --build
docker compose ps
```

## 8) Verification checklist

After setup:

1. Push a small commit to `main`.
2. Confirm GitHub Action `Deploy to AWS EC2` succeeds.
3. Visit:
   - `https://handofai.work`
   - `https://www.handofai.work`
4. Validate Cloudflare DNS is proxied and SSL mode is `Full (strict)`.
5. Run:

```bash
curl -I https://handofai.work
```

You should receive `HTTP/2 200` or a valid app response code.
