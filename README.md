# aws-auto-deploy

最小可行的自動部署練習：一個 FastAPI 服務，push 到 `main` 後由 GitHub Actions 跑測試，再透過 AWS Systems Manager (SSM) 在 EC2 上用 Docker 重建並重啟，最後驗證線上版本等於這次的 commit SHA。

> 這是部署練習用的 Demo API，不包含任何 ML 模型。

```
push main → GitHub Actions (pytest) → aws ssm send-command
          → EC2: git checkout <sha> → docker build/run → curl /health, /version == <sha>
          → Actions 讀回 SSM 結果，不成功就讓 pipeline 失敗
```

| Endpoint | 回傳 |
| --- | --- |
| `GET /health` | `{"status":"ok"}` |
| `GET /version` | `{"version":"<commit sha>"}`（本地預設 `dev`） |

## 1. 本地執行

```bash
pip install -r requirements-dev.txt
pytest -q

docker build --build-arg APP_VERSION=v1 -t aws-auto-deploy .
docker run --rm -p 8000:8000 aws-auto-deploy

curl http://localhost:8000/health    # {"status":"ok"}
curl http://localhost:8000/version   # {"version":"v1"}
```

## 2. AWS 一次性設定

**EC2**
- AMI：Ubuntu 24.04（已內建 SSM Agent），`t3.micro` 即可。
- IAM instance profile：附加 `AmazonSSMManagedInstanceCore`。沒有這個，SSM 看不到機器。
- Security group：inbound TCP 80 只開給自己的 IP。**不需要開 22**，部署全走 SSM。
- User data（開機時安裝 Docker 與 git）：

  ```bash
  #!/bin/bash
  apt-get update -y
  apt-get install -y docker.io git curl
  systemctl enable --now docker
  ```

- 確認：AWS Console → Systems Manager → Fleet Manager 看得到這台機器且狀態 Online。

**給 GitHub Actions 用的 IAM user**（只給最小權限）：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ssm:SendCommand",
      "Resource": [
        "arn:aws:ec2:<REGION>:<ACCOUNT_ID>:instance/<INSTANCE_ID>",
        "arn:aws:ssm:<REGION>::document/AWS-RunShellScript"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "ssm:GetCommandInvocation",
      "Resource": "*"
    }
  ]
}
```

**GitHub repo → Settings → Secrets and variables → Actions**

| Secret | 值 |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | 上面 IAM user 的 key |
| `AWS_SECRET_ACCESS_KEY` | 同上 |
| `AWS_REGION` | 例如 `ap-northeast-1` |
| `EC2_INSTANCE_ID` | 例如 `i-0abc123...` |

> Repo 需為 public，EC2 才能不帶憑證 `git clone`。

## 3. 驗證部署

```bash
git commit --allow-empty -m "trigger deploy" && git push
# Actions 綠燈後：
curl http://<EC2_PUBLIC_IP>/version   # 應等於最新 commit 的完整 SHA
```

## 4. 排查手冊

| 症狀 | 先看哪裡 |
| --- | --- |
| `send-command` 報 `InvalidInstanceId` | 機器不在 SSM：instance profile 沒掛、SSM Agent 沒跑、機器沒有對外網路 |
| `AccessDenied` | IAM user policy 的 instance ARN / region 是否正確 |
| SSM 狀態 `Failed`，stderr 有 `docker: command not found` | user data 沒跑完；用 Session Manager 登入確認 |
| 驗證失敗、版本不符 | Actions log 會印出 `docker logs`；在機器上 `docker ps -a`、`docker logs app` |
| Actions 綠燈但外部 curl 不通 | Security group 80 port、是否用 public IP、本機網路 |
| Container 一直重啟 | `docker logs app` 看 uvicorn 啟動錯誤 |

## 下一步（不在 MVP 範圍）

- 改用 GitHub OIDC + IAM role，移除長期 access key
- Image 推到 ECR，EC2 只 pull，不在機器上 build
- 加 `POST /predict` demo endpoint
- 部署失敗時自動回滾到上一版 image
