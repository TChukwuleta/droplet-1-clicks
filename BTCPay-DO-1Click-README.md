# BTCPay Server — DigitalOcean 1-Click App

A self-hosted, open-source Bitcoin and Lightning payment processor,
packaged as a DigitalOcean Marketplace 1-Click Droplet.

---

## For Users: Installing and Using BTCPay Server

### 1. Deploy the Droplet

1. Find **BTCPay Server** on the DigitalOcean Marketplace, or select it
   from your Snapshots if you were given direct access.
2. Choose a Droplet plan. **Minimum: 1 vCPU, 2 GB RAM, 50 GB SSD.**
   Smaller plans will not run reliably, BTCPay runs 7 containers
   at once (Bitcoin node, Lightning, database, BTCPay itself, Tor,
   and the reverse proxy).
3. Pick a region and add your SSH key, then create the Droplet.

### 2. Point a domain at it (do this before connecting)

BTCPay requires HTTPS to function at all, it will not let you create
an account over a bare IP address. Before you SSH in:

1. Note your Droplet's public IPv4 address (shown on its Overview page).
2. In your domain registrar or DNS provider, add an **A record**
   pointing a domain or subdomain (e.g. `btcpay.yourdomain.com`) at
   that IP address.
3. Wait for DNS to propagate. This can take a few minutes, sometimes
   longer. You can check with `nslookup yourdomain.com` from your own
   computer, once it returns your Droplet's IP, you're ready.

### 3. Connect and run setup

```
ssh root@your_droplet_public_ipv4
```

On first login, a welcome message explains the process, then a setup
wizard runs automatically:

1. **Choose a Lightning implementation**: Core Lightning (default),
   LND, or phoenixd.
2. **Enter your domain.** The wizard checks that it actually resolves
   to this Droplet before continuing. If DNS isn't ready yet, you can
   exit and rerun the wizard later with:
   ```
   sudo /root/configure-domain.sh
   ```
3. Once confirmed, BTCPay installs automatically with HTTPS via
   Let's Encrypt. This takes several minutes on first run.

### 4. Create your account

Visit `https://yourdomain.com` in a browser once setup finishes, and
create your admin account.

### 5. Keeping BTCPay up to date

This is entirely independent of this Droplet image, BTCPay updates
itself. To update to the latest release at any time:

```
ssh root@your_droplet_public_ipv4
cd /root/btcpayserver-docker
btcpay-update.sh
```

Note: major version upgrades (e.g. a jump to a new major release) can
be one-way with no rollback. Check BTCPay's release notes before
updating a production instance.

---

## For Maintainers: Rebuilding and Resubmitting the Image

### What's in the build

- `btcpay-server-24-04/template.json` — Packer build definition
- `btcpay-server-24-04/scripts/030-clone-btcpay.sh` — clones BTCPay,
  does not install yet
- `btcpay-server-24-04/scripts/014-ufw-web.sh` — opens 80/443
  (explicit ports, not the "Nginx Full" ufw profile, which doesn't
  exist on this image since nginx runs in a container)
- `btcpay-server-24-04/scripts/015-ufw-lightning.sh` — opens 9735
- `btcpay-server-24-04/scripts/895-clear-build-ssh-key.sh` — wipes
  Packer's temporary build SSH key before snapshot (security-critical,
  see "Why this exists" below)
- `btcpay-server-24-04/files/root/configure-domain.sh` — the
  first-login wizard (Lightning choice, domain + DNS check, install
  with HTTPS + pruning)
- `btcpay-server-24-04/files/var/lib/cloud/scripts/per-instance/001_onboot`
  — unlocks SSH on first boot, hooks the wizard into first login
- `btcpay-server-24-04/files/etc/update-motd.d/99-one-click` — welcome
  message
- `common/scripts/999-img_check.sh` — DigitalOcean's official
  pre-submission validator (**not included by default in a fresh
  `droplet-1-clicks` checkout, must be added manually or via
  `make update-scripts`**)

### Prerequisites (one-time machine setup)

```powershell
winget install HashiCorp.Packer
```

Create `plugins.pkr.hcl` at the repo root:
```hcl
packer {
  required_plugins {
    digitalocean = {
      version = ">= 1.4.1"
      source  = "github.com/digitalocean/digitalocean"
    }
  }
}
```
Then run `packer init plugins.pkr.hcl` once.

### Rebuilding

1. Set your API token for the current terminal session (this does
   **not** persist between sessions, you'll need to redo this each
   time you open a new terminal):
   ```powershell
   $env:DIGITALOCEAN_API_TOKEN="your_token_here"
   ```
2. Validate:
   ```powershell
   packer validate btcpay-server-24-04/template.json
   ```
3. Build:
   ```powershell
   packer build btcpay-server-24-04/template.json
   ```
4. **Read the end of the output carefully.** Confirm:
   - The chmod check shows `-rwxr-xr-x` on all three scripts
   - `ufw status` shows `80/tcp ALLOW` and `443/tcp ALLOW`
   - The validator summary shows `0 Tests FAILED`
5. Note the new snapshot name/ID printed at the very end.

### Testing before resubmitting

1. Deploy a Droplet from the new snapshot (1 vCPU / 2GB RAM / 50GB
   plan should be selectable, if it forces a bigger plan, the
   builder's disk size is wrong, see "Known pitfalls" below).
2. Point a fresh test subdomain at it, confirm with `nslookup`.
3. SSH in fresh, confirm the MOTD, Lightning prompt, domain prompt,
   and install all fire automatically without manual intervention.
4. Confirm `https://yourtestdomain.com` loads with a valid cert and
   account creation works.
5. Destroy the test Droplet once confirmed, it's not needed after.

### Resubmitting to the Marketplace

1. **Rebuild right before resubmitting**, not days in advance. Ubuntu
   security patches can land in the gap between your build and
   DigitalOcean's review, causing a false-seeming `img_check.sh`
   failure that isn't a real defect, just staleness. Minimizing the
   gap avoids this.
2. Go to `cloud.digitalocean.com/vendorportal`.
3. Open the BTCPay Server listing.
4. Update **System Image** to the new snapshot.
5. Update **App Version** if BTCPay has released a new version since
   the last submission (this is a display label only, see note below).
6. Fill in **Reason for update**, referencing what was fixed.
7. Submit for review.

### Important: App Version is cosmetic, not a pin

The `application_version` field in `template.json` and the Vendor
Portal's "App Version" field are just display labels. They do **not**
control what actually gets installed. The real version comes from
whatever `btcpayserver-docker`'s repository has pinned at the moment
you run `git clone`, i.e. whatever was current the day you built the
image. Keep this field updated so it doesn't drift from reality, but
know that changing it alone does nothing functionally.

### Why the build-key-clearing script exists

Packer provisions the build Droplet using a temporary SSH key.
DigitalOcean's cloud-init **appends** new keys to `authorized_keys`
rather than replacing them, so if that temporary key isn't explicitly
removed before the snapshot is taken, it remains a valid login
credential on every Droplet ever created from the image, a permanent
backdoor. `895-clear-build-ssh-key.sh` wipes it before the validator
runs and the snapshot is created. Confirm this worked by checking for
`[ OK ] User root has no SSH keys present` in the validator output.

### Known pitfalls (already fixed, but worth understanding)

- **Builder disk size**: the Packer builder's `size` setting
  determines the *minimum* disk any future Droplet made from the
  snapshot can use. Use `s-1vcpu-2gb` (50GB disk), not a larger
  size, or deploys will be forced onto a pricier plan for no reason.
- **The "Nginx Full" ufw profile doesn't exist here**: it only gets
  registered when nginx is installed as a host package. BTCPay's
  nginx runs inside Docker, installed later, so use explicit
  `ufw allow 80/tcp` / `443/tcp` instead.
- **Don't delete text in `001_onboot` that looks like comments
  without checking first**: this file is short and every line is
  functional (`sed`, `systemctl restart ssh`, the `.bashrc` hook).
  Deleting any of it silently breaks the SSH unlock for every future
  Droplet, with no obvious error, just a permanent "please wait"
  lock on first login.
- **BTCPay refuses to work over plain HTTP**: don't attempt an
  HTTP-first, reconfigure-later flow, it doesn't work, BTCPay blocks
  account creation without HTTPS or Tor. Domain + HTTPS must be
  confirmed before the install step runs at all.

---

## Support

- Official docs: https://docs.btcpayserver.org
- Official repo: https://github.com/btcpayserver/btcpayserver
