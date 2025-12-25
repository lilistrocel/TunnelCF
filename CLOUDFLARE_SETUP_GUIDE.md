# Cloudflare Credentials Setup Guide

This guide walks you through getting the three required credentials for the Cloudflare Tunnel Auto-Provisioner:

1. **Account ID**
2. **Zone ID**
3. **API Token**

---

## Prerequisites

Before starting, you need:

- A Cloudflare account (free tier works)
- A domain added to Cloudflare (nameservers pointing to Cloudflare)

If you don't have a domain on Cloudflare yet, see [Adding a Domain](#adding-a-domain-to-cloudflare) at the end of this guide.

---

## Step 1: Get Your Account ID and Zone ID

### 1.1 Log into Cloudflare Dashboard

Go to [https://dash.cloudflare.com](https://dash.cloudflare.com) and log in.

### 1.2 Select Your Domain

From the home page, click on the domain you want to use for your tunnels.

```
┌─────────────────────────────────────────────────────────────┐
│  Cloudflare Dashboard                                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Websites                                                   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  yourdomain.com                          [Active]   │   │  ◄── Click here
│  │  Free Plan                                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 Find the IDs in the Right Sidebar

Once you're on your domain's overview page, scroll down on the **right sidebar**. You'll see an "API" section:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  yourdomain.com  │  Overview                                                 │
├──────────────────┴───────────────────────────────────────────────────────────┤
│                                                                              │
│  [Main content area]                     │  API                              │
│                                          │  ─────────────────────────────    │
│                                          │                                   │
│                                          │  Zone ID                          │
│                                          │  ┌─────────────────────────────┐  │
│                                          │  │ a1b2c3d4e5f6g7h8i9j0k1l2m3 │  │  ◄── ZONE ID
│                                          │  └─────────────────────────────┘  │
│                                          │        [Copy]                     │
│                                          │                                   │
│                                          │  Account ID                       │
│                                          │  ┌─────────────────────────────┐  │
│                                          │  │ z9y8x7w6v5u4t3s2r1q0p9o8n7 │  │  ◄── ACCOUNT ID
│                                          │  └─────────────────────────────┘  │
│                                          │        [Copy]                     │
│                                          │                                   │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 1.4 Copy Both IDs

Click the **Copy** button next to each ID and save them:

```
CF_ACCOUNT_ID="z9y8x7w6v5u4t3s2r1q0p9o8n7"
CF_ZONE_ID="a1b2c3d4e5f6g7h8i9j0k1l2m3"
```

---

## Step 2: Create an API Token

### 2.1 Go to API Tokens Page

**Option A:** Click on "Get your API token" link in the same API section of the sidebar.

**Option B:** Navigate directly to: [https://dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)

**Option C:** Click your profile icon (top right) → My Profile → API Tokens

### 2.2 Create a Custom Token

Click the **"Create Token"** button.

```
┌─────────────────────────────────────────────────────────────┐
│  API Tokens                                                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  API Tokens                          [Create Token]  ◄──────│── Click here
│                                                             │
│  User API Tokens                                            │
│  ─────────────────────────────────                          │
│  No tokens yet                                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 Select "Create Custom Token"

You'll see several templates. Scroll down to the bottom and click **"Get started"** next to **"Create Custom Token"**:

```
┌─────────────────────────────────────────────────────────────┐
│  Create Token                                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  API token templates                                        │
│  ─────────────────────────────────                          │
│                                                             │
│  Edit zone DNS                         [Use template]       │
│  Read analytics & logs                 [Use template]       │
│  ...                                                        │
│                                                             │
│  ─────────────────────────────────────────────────────────  │
│                                                             │
│  Custom token                                               │
│  Create Custom Token                   [Get started]  ◄─────│── Click here
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.4 Configure Token Permissions

Fill in the token configuration:

#### Token Name
```
Token name: Raspberry Pi Tunnel Provisioner
```

#### Permissions (Add TWO permissions)

Click **"+ Add more"** after the first one to add the second permission:

| Permission # | Category | Resource | Access Level |
|--------------|----------|----------|--------------|
| 1 | **Account** | **Cloudflare Tunnel** | **Edit** |
| 2 | **Zone** | **DNS** | **Edit** |

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Permissions                                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐   ┌─────────────────────┐   ┌────────────┐               │
│  │ Account    ▼ │   │ Cloudflare Tunnel ▼ │   │  Edit    ▼ │   [X]        │
│  └──────────────┘   └─────────────────────┘   └────────────┘               │
│                                                                             │
│  ┌──────────────┐   ┌─────────────────────┐   ┌────────────┐               │
│  │ Zone       ▼ │   │ DNS               ▼ │   │  Edit    ▼ │   [X]        │
│  └──────────────┘   └─────────────────────┘   └────────────┘               │
│                                                                             │
│  [+ Add more]                                                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Account Resources

Select which account(s) this token can access:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Account Resources                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐   ┌─────────────────────────────────────┐             │
│  │ Include       ▼ │   │ Your Account Name                 ▼ │             │
│  └─────────────────┘   └─────────────────────────────────────┘             │
│                                                                             │
│  (Select your account or "All accounts" if you only have one)              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Zone Resources

Select which zone(s)/domain(s) this token can modify DNS for:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Zone Resources                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐   ┌─────────────────────────────────────┐             │
│  │ Include       ▼ │   │ Specific zone                     ▼ │             │
│  └─────────────────┘   └─────────────────────────────────────┘             │
│                                                                             │
│                        ┌─────────────────────────────────────┐             │
│                        │ yourdomain.com                    ▼ │             │
│                        └─────────────────────────────────────┘             │
│                                                                             │
│  (Choose "Specific zone" and select your domain, or "All zones")           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Client IP Address Filtering (Optional but Recommended)

Leave blank for now, or restrict to your IP ranges for extra security.

#### TTL (Optional)

You can set an expiration date for the token, or leave blank for no expiration.

### 2.5 Continue and Create

Click **"Continue to summary"** at the bottom.

Review the summary:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Summary                                                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Raspberry Pi Tunnel Provisioner                                            │
│                                                                             │
│  This API token will affect the below accounts and zones.                   │
│                                                                             │
│  Your Account Name - Cloudflare Tunnel:Edit                                 │
│  yourdomain.com - DNS:Edit                                                  │
│                                                                             │
│                                              [Back]  [Create Token]  ◄──────│
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

Click **"Create Token"**.

### 2.6 Copy Your Token

**⚠️ IMPORTANT: You will only see this token ONCE!**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  API Token Created                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ✓ Raspberry Pi Tunnel Provisioner token was created successfully          │
│                                                                             │
│  This is your API token. Store it safely because you won't be able         │
│  to see it again.                                                           │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ xYz123ABCdef456GHIjkl789MNOpqr012STUvwx345YZabc678DEFghi901JKL     │   │  ◄── YOUR TOKEN
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                [Copy]       │
│                                                                             │
│  Test this token:                                                           │
│  curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \   │
│       -H "Authorization: Bearer <token>"                                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

Copy the token and save it securely:

```
CF_API_TOKEN="xYz123ABCdef456GHIjkl789MNOpqr012STUvwx345YZabc678DEFghi901JKL"
```

---

## Step 3: Verify Your Token (Optional)

Test that your token works:

```bash
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer YOUR_TOKEN_HERE" \
     -H "Content-Type: application/json"
```

Expected response:
```json
{
  "result": {
    "id": "...",
    "status": "active"
  },
  "success": true,
  "errors": [],
  "messages": [...]
}
```

---

## Step 4: Configure Your Raspberry Pi

Now you have all three values:

```bash
# Your credentials (example - use your actual values!)
CF_API_TOKEN="xYz123ABCdef456GHIjkl789MNOpqr012STUvwx345YZabc678DEFghi901JKL"
CF_ACCOUNT_ID="z9y8x7w6v5u4t3s2r1q0p9o8n7m6l5k4"
CF_ZONE_ID="a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
CF_DOMAIN="yourdomain.com"
```

### Option A: Interactive Install

Run the installer and enter values when prompted:

```bash
cd cf-tunnel-service
sudo ./install.sh
```

### Option B: Pre-configure

Create the config file before installing:

```bash
sudo mkdir -p /etc/cf-tunnel

sudo tee /etc/cf-tunnel/config.env << 'EOF'
CF_API_TOKEN="your-actual-token"
CF_ACCOUNT_ID="your-actual-account-id"
CF_ZONE_ID="your-actual-zone-id"
CF_DOMAIN="yourdomain.com"
NODE_PREFIX="rpi"
SSH_PORT="22"
ADDITIONAL_SERVICES=""
EOF

sudo chmod 600 /etc/cf-tunnel/config.env
```

Then run the installer:

```bash
sudo ./install.sh
```

---

## Adding a Domain to Cloudflare

If you don't have a domain on Cloudflare yet:

### Option 1: Register a New Domain with Cloudflare

1. Go to [Cloudflare Registrar](https://dash.cloudflare.com/?to=/:account/domains/register)
2. Search for an available domain
3. Purchase (Cloudflare offers at-cost pricing with no markup)

### Option 2: Transfer an Existing Domain

1. Go to Cloudflare Dashboard → Add a Site
2. Enter your domain name
3. Select the Free plan (sufficient for tunnels)
4. Cloudflare will scan existing DNS records
5. Update your domain's nameservers at your registrar to:
   - `*.ns.cloudflare.com` (Cloudflare will provide specific names)
6. Wait for propagation (usually 5-30 minutes, can take up to 24 hours)

---

## Security Best Practices

### 1. Limit Token Scope

Only grant permissions the token actually needs:
- ✅ Cloudflare Tunnel: Edit
- ✅ DNS: Edit
- ❌ Don't add other permissions

### 2. Restrict to Specific Zones

Instead of "All zones", select only the domain(s) you'll use.

### 3. Set Token Expiration

For production deployments, consider setting a TTL (e.g., 1 year) and rotating tokens periodically.

### 4. IP Restrictions

If your Pis have static IPs or come from known ranges, add them to the token's IP filter.

### 5. Use Cloudflare Access

Add authentication to your SSH tunnels:

1. Zero Trust Dashboard → Access → Applications
2. Add Application → Self-hosted
3. Domain: `*.yourdomain.com` (or specific hostnames)
4. Add policies (email verification, SSO, etc.)

---

## Troubleshooting

### "Authentication error" when creating tunnel

- Verify your API token is correct (no extra spaces)
- Check token has `Cloudflare Tunnel: Edit` permission
- Ensure token is for the correct account

### "Could not find zone" error

- Verify Zone ID is correct
- Check token has `DNS: Edit` permission for that zone
- Ensure the domain is active in Cloudflare

### Token verification fails

```bash
# Test your token
curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer $CF_API_TOKEN" | jq
```

If status is not "active", create a new token.

---

## Quick Reference

| Credential | Where to Find | Example |
|------------|---------------|---------|
| Account ID | Domain Overview → Right sidebar → API section | `a1b2c3d4e5f6...` |
| Zone ID | Domain Overview → Right sidebar → API section | `z9y8x7w6v5u4...` |
| API Token | Profile → API Tokens → Create Token | `xYz123ABC...` |
| Domain | Your domain added to Cloudflare | `example.com` |

---

## Summary Checklist

- [ ] Logged into Cloudflare Dashboard
- [ ] Domain added and active in Cloudflare
- [ ] Copied **Account ID** from domain overview
- [ ] Copied **Zone ID** from domain overview
- [ ] Created API Token with:
  - [ ] Account > Cloudflare Tunnel > Edit
  - [ ] Zone > DNS > Edit
- [ ] Saved token securely (won't be shown again!)
- [ ] Tested token with curl verify command
- [ ] Configured `/etc/cf-tunnel/config.env` on Raspberry Pi
