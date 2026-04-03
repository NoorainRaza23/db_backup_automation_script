# 📦 DB Backup Automation Script

Automated MySQL database backup solution with compression, AWS S3 upload, email notifications, and retention management.

---

## 🚀 Features

* ✅ Automated MySQL database backup using `mysqldump`
* ✅ Compression using `gzip` for storage efficiency
* ✅ Upload backups to AWS S3
* ✅ Email notifications (success/failure)
* ✅ Retry mechanism for reliability
* ✅ Large table handling (separate dump)
* ✅ Logging and monitoring
* ✅ Cron-based scheduling
* ✅ Retention policy (local + S3 lifecycle)

---

## 📂 Repository Structure

```
.
├── sample_db_script1.sh   # Basic backup script
├── sample_db_script2.sh   # Advanced production-ready script
├── msmtprc.txt           # Sample SMTP config for Gmail
└── README.md             # Documentation
```

---

## ⚙️ Prerequisites

Install required packages:

```bash
sudo apt update
sudo apt install mysql-client awscli msmtp mailutils -y
```

---

## 🔐 Gmail SMTP Setup (for Email Alerts)

1. Enable **2-Step Verification** in your Google account
2. Generate an **App Password**
3. Configure `msmtp`

Create config:

```bash
nano ~/.msmtprc
```

Paste:

```
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account gmail
host smtp.gmail.com
port 587
from your_email@gmail.com
user your_email@gmail.com
password your_app_password

account default : gmail
```

Set permission:

```bash
chmod 600 ~/.msmtprc
```

---

## 🛠️ Configuration

Edit script variables:

```bash
DB_NAME="your_database_name"
DB_USER="your_database_user"
DB_PASS="your_database_password"
DB_HOST="localhost"

BACKUP_DIR="/path/to/backup"
S3_BUCKET="s3://your-bucket-name/path/"
```

---

## 🔒 Secure Credentials (Recommended)

Instead of hardcoding credentials, use:

```bash
nano ~/.my.cnf
```

```
[client]
user=your_db_user
password=your_db_password
```

```bash
chmod 600 ~/.my.cnf
```

---

## ☁️ AWS Setup

Configure AWS CLI:

```bash
aws configure
```

Ensure access to S3 bucket:

```bash
aws s3 ls
```

---

## 📤 S3 Lifecycle Policy (Recommended)

Set lifecycle rule:

* Delete backups after **7 days**
* Delete noncurrent versions after **30 days**

This removes the need for manual cleanup in scripts.

---

## ▶️ Usage

Make script executable:

```bash
chmod +x sample_db_script2.sh
```

Run manually:

```bash
./sample_db_script2.sh
```

---

## ⏰ Schedule with Cron

```bash
crontab -e
```

Example (daily at 2 AM):

```bash
0 2 * * * /path/to/sample_db_script2.sh >> /var/log/db_backup.log 2>&1
```

---

## 📊 Logging

* Logs stored in:

  ```
  /path/to/log/db_backup.log
  ```
* Includes:

  * Backup status
  * Errors
  * Upload progress

---

## 📧 Email Notifications

You will receive:

* 🔄 Backup started
* ✅ Backup successful
* ❌ Failure alerts
* ☁️ S3 upload status

---

## 🧠 Script Versions

### 🔹 `sample_db_script1.sh`

* Basic backup
* Simple S3 upload
* Minimal logging

### 🔹 `sample_db_script2.sh` (Recommended)

* Retry mechanism
* Schema + data separation
* Large table handling
* Detailed email reports
* Execution time tracking

---

## ⚠️ Best Practices

* ❌ Do NOT hardcode passwords
* ✅ Use `.my.cnf` or environment variables
* ✅ Use AWS IAM roles (if on EC2)
* ✅ Monitor logs regularly
* ✅ Test restore process periodically

---

## 🔄 Backup Flow

```
MySQL → mysqldump → gzip → Local Storage → AWS S3 → Email Notification
```

---

## 🧪 Testing

Test backup:

```bash
./sample_db_script2.sh
```

Test restore:

```bash
gunzip < backup.sql.gz | mysql -u user -p db_name
```

---

## 📌 Future Improvements

* Docker support
* Slack/Discord alerts
* Terraform integration
* Multi-region backups
* CloudWatch monitoring

---

## 👤 Author

**Noorain Raza**

---

## 📄 License

This project is open-source and available under the MIT License.

---

## ⭐ Contribute

Feel free to fork, improve, and submit PRs!

---
