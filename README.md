# Iambadguy

CCDC red-team lab tooling. A set of attack payloads that sabotage student
Linux VMs (so the blue team has something to fix), an SSH deployer to push them
to every target, and a cleanup script that reverts the boxes to their
out-of-the-box state.

> For authorized CCDC/lab use only, on machines you own or are permitted to test.

## 1. Install (on the red-team VM, 192.168.4.241)

Clone the repo and run the installer. It pulls the latest code, installs the
tools it needs (`git`, `sshpass`), and stages everything under `/opt/ccdc`:

```bash
git clone https://github.com/MarkAblai/Iambadguy.git
cd Iambadguy/Linux/Utils
sudo ./install_all.sh
```

After it runs, all scripts live under **`/opt/ccdc`**:

```
/opt/ccdc/attacks/   Level_1.sh ... Level_5.sh      (the payloads)
/opt/ccdc/deploy/    deploy_level1.sh ... deploy_level5.sh, deploy_cleanup.sh, targets.conf
/opt/ccdc/utils/     cleanup.sh                      (the revert script)
```

Edit targets and the root password in one place before deploying:

```bash
sudo nano /opt/ccdc/deploy/targets.conf
```

Re-run `install_all.sh` anytime to pull the latest from the repo.

## 2. Deploy the attacks

Each `deploy_levelN.sh` pushes its payload to every target in `targets.conf`
over SSH and runs it as root. Run them from the deploy directory, one level at a
time:

```bash
cd /opt/ccdc/deploy
./deploy_level1.sh     # stop apache + block port 80
./deploy_level2.sh     # kill mail services (cron) + break /var/mail
./deploy_level3.sh     # deface the web index + cow distractions
./deploy_level4.sh     # break postfix + remove dovecot
./deploy_level5.sh     # iptables deny-all + break the Enter key
```

Each run prints `[+] <ip> done` or `[!] <ip> FAILED` per target.

## 3. Clean up (revert everything)

When you're done, revert every box to a clean system in one command:

```bash
cd /opt/ccdc/deploy
./deploy_cleanup.sh
```

`deploy_cleanup.sh` pushes `cleanup.sh` to each target and runs it as root. It
undoes all five levels by restoring the original state each attack snapshotted
before it ran (firewall rules, `/var/mail` ownership, the web index, postfix
config, dovecot, and `bash.bashrc`), then removes its own traces.

**Note:** a box that already has the Level 5 lockdown applied drops inbound SSH,
so `deploy_cleanup.sh` can't reach it (shown as `FAILED (locked down ...)`). For
those, run `cleanup.sh` from the VM console / QEMU guest agent instead.
