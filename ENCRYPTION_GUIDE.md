# Encrypting Secrets for Git

Three practical approaches for storing encrypted credentials in git:

1. **age** - Simple, modern, recommended for personal/small team use
2. **SOPS** - More features, supports partial file encryption, good for teams
3. **git-crypt** - Transparent encryption, seamless git workflow

---

## Option 1: age (Recommended - Simplest)

[age](https://github.com/FiloSottile/age) is a simple, modern encryption tool. No configuration, no key servers, just works.

### Install age

```bash
# macOS
brew install age

# Ubuntu/Debian/Raspberry Pi
sudo apt install age

# Or download binary
# https://github.com/FiloSottile/age/releases
```

### Generate a Key Pair

```bash
# Generate key pair (do this once, on your main machine)
age-keygen -o ~/.age/key.txt

# Output shows your public key:
# Public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# View your public key anytime
cat ~/.age/key.txt | grep "public key"
```

### Encrypt the Config File

```bash
# Encrypt with your public key
age -r age1your-public-key-here -o config.env.age config.env

# Or encrypt using the key file directly
age -R ~/.age/key.txt -o config.env.age config.env
```

### Decrypt the Config File

```bash
# Decrypt using your private key
age -d -i ~/.age/key.txt config.env.age > config.env
```

### Git Workflow

```bash
# .gitignore
config.env          # Never commit plaintext!
*.age.bak

# Commit only encrypted version
git add config.env.age
git commit -m "Update encrypted config"
```

### Setup Script for Raspberry Pi

```bash
#!/bin/bash
# decrypt-config.sh - Run on Pi after git pull

AGE_KEY="${AGE_KEY:-$HOME/.age/key.txt}"

if [[ ! -f "$AGE_KEY" ]]; then
    echo "ERROR: age key not found at $AGE_KEY"
    echo "Copy your key file to the Pi or set AGE_KEY env var"
    exit 1
fi

age -d -i "$AGE_KEY" config.env.age > /etc/cf-tunnel/config.env
chmod 600 /etc/cf-tunnel/config.env
echo "Config decrypted successfully"
```

### Multiple Recipients (Team Use)

```bash
# Encrypt for multiple people
age -r age1alice... -r age1bob... -r age1charlie... -o config.env.age config.env

# Or use a recipients file
cat > .age-recipients << 'EOF'
# Alice (laptop)
age1alicepublickeyhere
# Bob (server)  
age1bobpublickeyhere
# Deploy key (CI/CD)
age1deploykeyhere
EOF

age -R .age-recipients -o config.env.age config.env
```

---

## Option 2: SOPS (More Features)

[SOPS](https://github.com/getsops/sops) (Secrets OPerationS) by Mozilla supports partial encryption, multiple backends (age, GPG, AWS KMS, etc.), and structured files.

### Install SOPS

```bash
# macOS
brew install sops

# Linux - download from releases
# https://github.com/getsops/sops/releases
wget https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.arm64
sudo mv sops-v3.8.1.linux.arm64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
```

### Configure SOPS with age

```bash
# Generate age key if you haven't
age-keygen -o ~/.age/key.txt

# Get your public key
AGE_PUBLIC_KEY=$(cat ~/.age/key.txt | grep "public key" | cut -d: -f2 | tr -d ' ')

# Create .sops.yaml in your repo root
cat > .sops.yaml << EOF
creation_rules:
  - path_regex: \.env\.enc$
    age: >-
      ${AGE_PUBLIC_KEY}
  - path_regex: secrets\.yaml$
    age: >-
      ${AGE_PUBLIC_KEY}
EOF
```

### Encrypt with SOPS

```bash
# Set the age key location
export SOPS_AGE_KEY_FILE=~/.age/key.txt

# Encrypt entire file
sops -e config.env > config.env.enc

# Or encrypt in-place (creates encrypted version)
sops -e -i config.env.enc
```

### Decrypt with SOPS

```bash
export SOPS_AGE_KEY_FILE=~/.age/key.txt

# Decrypt to stdout
sops -d config.env.enc

# Decrypt to file
sops -d config.env.enc > config.env

# Edit encrypted file directly (decrypts, opens editor, re-encrypts)
sops config.env.enc
```

### SOPS with YAML (Partial Encryption)

SOPS can encrypt only the values in structured files, leaving keys readable:

```yaml
# secrets.yaml (before encryption)
cloudflare:
  api_token: "xYz123ABCdef456"
  account_id: "a1b2c3d4e5f6"
  zone_id: "z9y8x7w6v5u4"
  domain: "example.com"
```

```bash
sops -e secrets.yaml > secrets.enc.yaml
```

```yaml
# secrets.enc.yaml (after encryption) - keys visible, values encrypted
cloudflare:
    api_token: ENC[AES256_GCM,data:xxxxx,iv:xxxxx,tag:xxxxx]
    account_id: ENC[AES256_GCM,data:xxxxx,iv:xxxxx,tag:xxxxx]
    zone_id: ENC[AES256_GCM,data:xxxxx,iv:xxxxx,tag:xxxxx]
    domain: ENC[AES256_GCM,data:xxxxx,iv:xxxxx,tag:xxxxx]
sops:
    age:
        - recipient: age1xxxxxxxxx
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            ...
            -----END AGE ENCRYPTED FILE-----
    lastmodified: "2024-01-15T10:30:00Z"
    version: 3.8.1
```

---

## Option 3: git-crypt (Transparent)

[git-crypt](https://github.com/AGWA/git-crypt) provides transparent encryption - files are automatically decrypted on checkout and encrypted on commit.

### Install git-crypt

```bash
# macOS
brew install git-crypt

# Ubuntu/Debian
sudo apt install git-crypt

# From source (for Raspberry Pi if not in repos)
sudo apt install g++ make libssl-dev
git clone https://github.com/AGWA/git-crypt.git
cd git-crypt
make
sudo make install
```

### Initialize in Repository

```bash
cd your-repo

# Initialize git-crypt (generates symmetric key)
git-crypt init

# Export key for backup/sharing (KEEP THIS SAFE!)
git-crypt export-key ../git-crypt-key.bin
```

### Configure Files to Encrypt

```bash
# Create .gitattributes
cat > .gitattributes << 'EOF'
# Encrypt these files
config.env filter=git-crypt diff=git-crypt
*.secret filter=git-crypt diff=git-crypt
secrets/** filter=git-crypt diff=git-crypt
EOF

git add .gitattributes
```

### Usage

```bash
# Lock the repo (encrypt files in working directory)
git-crypt lock

# Unlock the repo (decrypt files)
git-crypt unlock ../git-crypt-key.bin

# Check status
git-crypt status
```

### On Raspberry Pi

```bash
# Copy the key to the Pi
scp git-crypt-key.bin pi@raspberry:/home/pi/.git-crypt-key

# Clone and unlock
git clone your-repo
cd your-repo
git-crypt unlock ~/.git-crypt-key
```

---

## Comparison

| Feature | age | SOPS | git-crypt |
|---------|-----|------|-----------|
| Simplicity | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ |
| Partial encryption | ❌ | ✅ | ❌ |
| Git integration | Manual | Manual | Transparent |
| Multiple recipients | ✅ | ✅ | Via GPG |
| Cloud KMS support | ❌ | ✅ | ❌ |
| Audit trail | ❌ | ✅ | ❌ |
| Dependencies | None | age/GPG | OpenSSL |

---

## Recommended Setup for Your Use Case

For Raspberry Pi field deployments, I recommend **age** for simplicity:

### Directory Structure

```
cf-tunnel-service/
├── .gitignore
├── config.env              # NEVER COMMITTED - local only
├── config.env.age          # Encrypted - safe to commit
├── config.env.example      # Template - committed
├── .age-recipients         # Public keys - committed
├── decrypt.sh              # Helper script - committed
├── install.sh
├── cf-tunnel-provisioner.sh
└── ...
```

### .gitignore

```gitignore
# Sensitive files - NEVER commit
config.env
*.key
*.pem

# age private keys
.age/

# Backups
*.bak
*.backup

# Allow encrypted versions
!*.age
!*.enc
```

### Workflow

```bash
# On your development machine:

# 1. Edit plaintext config
nano config.env

# 2. Encrypt before commit
age -R .age-recipients -o config.env.age config.env

# 3. Commit encrypted version
git add config.env.age
git commit -m "Update config"
git push


# On Raspberry Pi:

# 1. Pull latest
git pull

# 2. Decrypt (key must be on Pi)
./decrypt.sh

# 3. Restart service
sudo systemctl restart cf-tunnel
```

---

## Security Notes

1. **Never commit plaintext secrets** - Add to .gitignore first!

2. **Backup your keys** - If you lose the private key, you lose access to all encrypted files

3. **Key distribution** - Copy private keys securely (scp, USB), never through git

4. **Rotate secrets** - If you suspect compromise, generate new credentials in Cloudflare

5. **Verify encryption** - Before pushing, check the file is actually encrypted:
   ```bash
   file config.env.age  # Should show "data" not "ASCII text"
   head config.env.age  # Should be binary garbage, not readable
   ```
