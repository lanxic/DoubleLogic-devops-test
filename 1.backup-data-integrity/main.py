import os
import sys
from dotenv import load_dotenv
import subprocess
import shutil
from datetime import datetime

# Load konfigurasi dari file .env
load_dotenv()

HOST = os.getenv("DB_HOST")
USER = os.getenv("DB_USERNAME")
PASSWORD = os.getenv("DB_PASSWORD")
DATABASE = os.getenv("DB_DATABASE")
RCLONE_DIR = os.getenv("RCLONE_DIR", "rclone-gdrive")

# Path untuk Wallet Logs
WALLET_LOGS_PATH = "/data/wallet_logs"
DATE_STR = datetime.now().strftime("%Y%m%d")

def backup_all():
    try:
        # --- 1. BACKUP DATABASE ---
        db_sql = f"{DATE_STR}_{DATABASE}.sql"
        db_gz = f"{db_sql}.gz"
        
        print(f"[*] Memulai backup database {DATABASE}...")
        subprocess.run(f"mysqldump -h {HOST} -u {USER} -p'{PASSWORD}' {DATABASE} > {db_sql}", shell=True, check=True)
        subprocess.run(["gzip", "-f", db_sql], check=True)
        
        shutil.move(db_gz, os.path.join(RCLONE_DIR, db_gz))
        print(f"[V] Database berhasil di-backup ke {RCLONE_DIR}")

        # --- 2. BACKUP WALLET LOGS ---
        log_tar = f"{DATE_STR}_wallet_logs.tar.gz"
        
        print(f"[*] Memulai kompresi folder logs: {WALLET_LOGS_PATH}...")
        # Menggunakan tar -czf untuk kompresi direktori
        subprocess.run(["tar", "-czf", log_tar, "-C", os.path.dirname(WALLET_LOGS_PATH), os.path.basename(WALLET_LOGS_PATH)], check=True)
        
        shutil.move(log_tar, os.path.join(RCLONE_DIR, log_tar))
        print(f"[V] Wallet logs berhasil di-backup ke {RCLONE_DIR}")

    except Exception as e:
        print(f"[X] Terjadi kesalahan saat backup: {str(e)}")

def restore_all(backup_date):
    try:
        # Variabel file berdasarkan tanggal input
        db_gz = f"{backup_date}_{DATABASE}.sql.gz"
        db_sql = f"{backup_date}_{DATABASE}.sql"
        log_tar = f"{backup_date}_wallet_logs.tar.gz"

        # --- 1. RESTORE DATABASE ---
        db_path = os.path.join(RCLONE_DIR, db_gz)
        if os.path.exists(db_path):
            print(f"[*] Me-restore database dari {db_gz}...")
            # Uncompress sementara untuk restore
            subprocess.run(f"gunzip -c {db_path} > {db_sql}", shell=True, check=True)
            
            # Reset DB & Load Data
            import mysql.connector
            conn = mysql.connector.connect(host=HOST, user=USER, password=PASSWORD)
            cursor = conn.cursor()
            cursor.execute(f"DROP DATABASE IF EXISTS {DATABASE}")
            cursor.execute(f"CREATE DATABASE {DATABASE}")
            conn.close()
            
            subprocess.run(f"mysql -h {HOST} -u {USER} -p'{PASSWORD}' {DATABASE} < {db_sql}", shell=True, check=True)
            os.remove(db_sql)
            print("[V] Database berhasil dipulihkan.")
        
        # --- 2. RESTORE LOGS ---
        log_path = os.path.join(RCLONE_DIR, log_tar)
        if os.path.exists(log_path):
            print(f"[*] Me-restore wallet logs dari {log_tar}...")
            # Ekstrak kembali ke folder asal (pastikan folder tujuan ada)
            subprocess.run(["tar", "-xzf", log_path, "-C", "/"], check=True)
            print("[V] Wallet logs berhasil dipulihkan ke /data/wallet_logs.")

    except Exception as e:
        print(f"[X] Terjadi kesalahan saat restore: {str(e)}")

if __name__ == '__main__':
    if len(sys.argv) > 1:
        choice = sys.argv[1]
    else:
        print("Pilih operasi:\n1. Backup All (DB & Logs)\n2. Restore All")
        choice = input("Masukkan pilihan (1/2): ")

    if choice == '1':
        backup_all()
    elif choice == '2':
        target_date = input("Masukkan tanggal backup (format YYYYMMDD, misal 20260413): ")
        restore_all(target_date)
    else:
        print("Pilihan tidak valid.")
